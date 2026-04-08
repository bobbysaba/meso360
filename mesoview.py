#!/usr/bin/env python3
"""
mesoview — Flask Blueprint for the real-time data dashboard.

Registered by supervisor.py at /view. Not runnable standalone.
"""

from flask import Blueprint, Response, jsonify, render_template
from pathlib import Path
from datetime import datetime, timezone, timedelta
import math, csv, time, json, threading

from common import DEFAULT_DATA_DIR, HEADER, load_config

mesoview_bp = Blueprint('mesoview', __name__, template_folder='templates')

# Set by supervisor before registering this blueprint.
TEST_MODE: bool = False
TEST_FILE = Path(__file__).parent / 'test_data' / 'test.txt'

_CFG = load_config()
DATA_DIR = Path(_CFG.get('data_dir', str(DEFAULT_DATA_DIR))).expanduser()

_HDR = HEADER.split(',')
IDX = {
    'wspd':        _HDR.index('sfc_wspd'),
    'wdir':        _HDR.index('sfc_wdir'),
    't':           _HDR.index('t_fast'),
    'td':          _HDR.index('dewpoint'),
    'pressure':    _HDR.index('pressure'),
    'compass_dir': _HDR.index('compass_dir'),
    'date':        _HDR.index('gps_date'),
    'time_':       _HDR.index('gps_time'),
    'lat':         _HDR.index('lat'),
    'lon':         _HDR.index('lon'),
    'rh':          _HDR.index('der_rh'),
}

# ── In-memory data cache ──────────────────────────────────────────────────────
_data_buf: list = []
_data_lock = threading.Lock()
_data_cond = threading.Condition(_data_lock)
_data_seq  = 0
_MAX_BUF   = 7200  # 2 hours at 1 Hz


def _log(msg: str) -> None:
    from datetime import datetime, timezone
    ts = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')
    print(f'[{ts}] [mesoview] {msg}', flush=True)


def today_file() -> Path:
    return DATA_DIR / f"{datetime.now(timezone.utc).strftime('%Y%m%d')}.txt"


def parse_row(row: list):
    if len(row) <= max(IDX.values()):
        return None
    try:
        ts = datetime.strptime(
            row[IDX['date']] + row[IDX['time_']], '%d%m%y%H%M%S'
        ).replace(tzinfo=timezone.utc).timestamp()

        def f(idx):
            try:
                v = float(row[idx])
                return v if math.isfinite(v) else None
            except (ValueError, IndexError):
                return None

        t           = f(IDX['t'])
        td          = f(IDX['td'])
        wspd        = f(IDX['wspd'])
        wdir        = f(IDX['wdir'])
        pressure    = f(IDX['pressure'])
        compass_dir = f(IDX['compass_dir'])
        lat         = f(IDX['lat'])
        lon         = f(IDX['lon'])
        rh          = f(IDX['rh'])

        if all(v is None for v in (t, td, wspd, wdir, pressure, compass_dir)):
            return None

        return dict(ts=ts, t=t, td=td, wspd=wspd, wdir=wdir,
                    pressure=pressure, compass_dir=compass_dir,
                    lat=lat, lon=lon, rh=rh)
    except (ValueError, IndexError):
        return None


def _append_point(p) -> None:
    global _data_seq
    with _data_cond:
        _data_buf.append(p)
        if len(_data_buf) > _MAX_BUF:
            del _data_buf[0]
        _data_seq += 1
        _data_cond.notify_all()


def start_cache_worker() -> None:
    """Called by supervisor after blueprint registration."""
    threading.Thread(target=_cache_worker, daemon=True).start()


def _cache_worker() -> None:
    if TEST_MODE:
        _run_test_cache()
    else:
        _run_live_cache()


def _run_test_cache() -> None:
    """Load test file into cache then replay it in a loop at 1 Hz."""
    data = []
    with open(TEST_FILE) as fh:
        reader = csv.reader(fh)
        next(reader, None)
        for row in reader:
            p = parse_row(row)
            if p:
                data.append(p)
    if not data:
        _log('WARNING: test file empty')
        return
    # Pre-load history (first 2 hours of test data)
    cutoff = data[0]['ts'] + 2 * 60 * 60
    for p in data:
        if p['ts'] <= cutoff:
            _append_point(p)
    _log(f'TEST cache: preloaded {len(_data_buf)} points, replaying at 1 Hz')
    while True:
        for p in data:
            _append_point(p)
            time.sleep(1)


def _run_live_cache() -> None:
    now    = datetime.now(timezone.utc)
    cutoff = now.timestamp() - 2 * 60 * 60
    yesterday = DATA_DIR / f"{(now - timedelta(days=1)).strftime('%Y%m%d')}.txt"
    for f in (yesterday, today_file()):
        if f.exists():
            with open(f) as fh:
                reader = csv.reader(fh)
                next(reader, None)
                for row in reader:
                    p = parse_row(row)
                    if p and p['ts'] >= cutoff:
                        _append_point(p)

    path = today_file()
    _wait_start = time.monotonic()
    _last_warn  = -60.0
    while not path.exists():
        elapsed = time.monotonic() - _wait_start
        if elapsed - _last_warn >= 60:
            _log(f'WARNING: still waiting for data file {path} ({int(elapsed)}s elapsed)')
            _last_warn = elapsed
        time.sleep(2)
        path = today_file()
    pos = path.stat().st_size

    while True:
        new_path = today_file()
        if new_path != path:
            path = new_path
            pos  = 0
        if path.exists():
            with open(path) as fh:
                end = fh.seek(0, 2)
                if pos > end:
                    _log(f'WARNING: data file truncated; resetting read position')
                    pos = 0
                fh.seek(pos)
                if pos == 0:
                    fh.readline()
                    pos = fh.tell()
                lines = fh.readlines()
                pos = fh.tell()
            for line in lines:
                p = parse_row(next(csv.reader([line.strip()]), []))
                if p:
                    _append_point(p)
        time.sleep(1)


# ── Routes ────────────────────────────────────────────────────────────────────

@mesoview_bp.route('/')
def index():
    return render_template('index.html')


@mesoview_bp.route('/initial')
def initial():
    empty = {k: [] for k in ('ts', 't', 'td', 'wspd', 'wdir', 'pressure',
                              'compass_dir', 'lat', 'lon', 'rh')}
    cutoff = datetime.now(timezone.utc).timestamp() - 2 * 60 * 60
    with _data_lock:
        snapshot = list(_data_buf)
    result = {k: [] for k in empty}
    for p in snapshot:
        if p['ts'] >= cutoff:
            for k, v in p.items():
                result[k].append(v)
    return jsonify(result)


@mesoview_bp.route('/stream')
def stream():
    def generate():
        keepalive_interval = 2
        with _data_lock:
            last_seq = _data_seq
        try:
            while True:
                with _data_cond:
                    changed = _data_cond.wait_for(
                        lambda: _data_seq != last_seq, timeout=keepalive_interval
                    )
                    if changed:
                        point    = _data_buf[-1] if _data_buf else None
                        last_seq = _data_seq
                    else:
                        point = None
                if point is None:
                    yield ': keep-alive\n\n'
                else:
                    yield f'data: {json.dumps(point)}\n\n'
        except GeneratorExit:
            pass

    return Response(
        generate(),
        mimetype='text/event-stream',
        headers={'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no'},
    )


def cache_stats() -> dict:
    """Called by supervisor's /api/status to report cache health."""
    with _data_lock:
        n = len(_data_buf)
        fname = today_file().name if not TEST_MODE else TEST_FILE.name
    return {'points': n, 'current_file': fname}

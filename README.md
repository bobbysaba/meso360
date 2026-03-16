# Mesoview

Real-time web dashboard for NSSL Mobile Mesonet data. Fetches observations from the Campbell Scientific datalogger at 1 Hz, writes them to daily txt files, and serves live interactive charts over a local network.

---

## Requirements

- Python 3.10 or later
- [Miniforge](https://github.com/conda-forge/miniforge/releases) (recommended) **or** any Python installation with pip
- OpenSSH client — built into macOS, Linux, and Windows 10/11 (no WSL required)
- `~/.ssh/clamps_rsa` — the NSSL/BLISS RSA key must be present on each vehicle machine before the SSH tunnel will connect

---

## 1 — Clone the repo

```bash
git clone <repo-url>
cd mesoview
```

---

## 2 — Set up the Python environment

### Option A — conda (recommended)

```bash
conda env create -f environment.yml
conda activate mesoview
```

To update later after a `git pull`:

```bash
conda env update -f environment.yml --prune
```

### Option B — pip / venv

```bash
python -m venv .venv

# macOS / Linux
source .venv/bin/activate

# Windows
.venv\Scripts\activate

pip install -r requirements.txt
```

---

## 3 — Configure

Copy the example config and edit it:

```bash
cp mesoview.config.example.json mesoview.config.json
```

`mesoview.config.json` is git-ignored so your local settings won't be overwritten by `git pull`. Open it and set your values:

```json
{
  "data_dir":           "~/data/raw/mesonet",
  "log_dir":            "~/mesoview_logs",
  "logger_ip":          "192.168.4.6",
  "http_port":          8080,
  "mdns_hostname":      "mesoview",
  "ingest_retry_max":   100,
  "ingest_retry_delay": 5,
  "rtun_port":          2222
}
```

| Key | Description | Default |
|-----|-------------|---------|
| `data_dir` | Where daily `.txt` data files are written and read | `~/data/raw/mesonet` |
| `log_dir` | Where daily log files are written (`mesoview.YYYYMMDD.log`) | `~/mesoview_logs` |
| `logger_ip` | IP address of the Campbell datalogger on the vehicle network | `192.168.4.6` |
| `http_port` | Port the web viewer listens on | `8080` |
| `mdns_hostname` | mDNS hostname for the viewer (if your network supports it) | `mesoview` |
| `ingest_retry_max` | Max fetch attempts before the ingest script exits | `100` |
| `ingest_retry_delay` | Seconds between retry attempts | `5` |
| `rtun_port` | Port for the SSH reverse tunnel to `remote.bliss.science` — **unique per vehicle** to avoid conflicts | *(required)* |

> **SSH tunnel** — `supervisor.py` automatically maintains a reverse SSH tunnel to `clamps@remote.bliss.science` using `~/.ssh/clamps_rsa`. Each vehicle must use a unique `rtun_port`. The tunnel is managed cross-platform (Windows/macOS/Linux) via the system `ssh` client; no WSL or additional tooling is required. If the tunnel drops, the supervisor restarts it automatically.

---

## 4 — Run manually

`supervisor.py` starts the ingest script, the viewer, and the SSH reverse tunnel together, and automatically restarts any of them if they crash.

```bash
# Make sure your environment is active first
conda activate mesoview   # or: source .venv/bin/activate

python supervisor.py
```

Open a browser on any device connected to the same network and go to:

```
http://<host-machine-ip>:8080
```

### Status indicator

The colored dot in the top-left of the dashboard shows the current data feed health:

| Color | Meaning |
|-------|---------|
| Green | Connected and receiving data normally |
| Orange | Connected but no data received in the last 30 seconds — ingest may be down, the datalogger may be unreachable, or the rack may not be powered on |
| Red | SSE connection to the viewer server lost — the viewer process may be down or the network between your browser and the host machine is interrupted |

If the dot is orange, check the log file for `WARNING` messages from ingest.

All output from both scripts is written to `~/mesoview_logs/mesoview.YYYYMMDD.log` (configurable via `log_dir`). To watch it live:

```bash
tail -f ~/mesoview_logs/mesoview.$(date +%Y%m%d).log
```

To run in test/replay mode (no datalogger needed):

```bash
python viewer.py --test
```

---

## 5 — Run on startup

The goal is to have `supervisor.py` launch automatically when the host machine boots, using the Python executable from your environment. Find that path first:

```bash
# conda
conda activate mesoview
which python          # macOS / Linux
where python          # Windows — copy the full path shown

# venv
# macOS / Linux: /path/to/mesoview/.venv/bin/python
# Windows:       C:\path\to\mesoview\.venv\Scripts\python.exe
```

---

### macOS — launchd

Create `~/Library/LaunchAgents/com.mesoview.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>             <string>com.mesoview</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/YOUR_USER/miniforge3/envs/mesoview/bin/python</string>
    <string>/path/to/mesoview/supervisor.py</string>
  </array>
  <key>WorkingDirectory</key>  <string>/path/to/mesoview</string>
  <key>RunAtLoad</key>         <true/>
  <key>KeepAlive</key>         <true/>
</dict>
</plist>
```

Replace the Python path and repo path, then load it:

```bash
launchctl load ~/Library/LaunchAgents/com.mesoview.plist
```

To stop / unload:

```bash
launchctl unload ~/Library/LaunchAgents/com.mesoview.plist
```

---

### Linux — cron

```bash
crontab -e
```

Add this line (replace paths):

```
@reboot cd /path/to/mesoview && /path/to/conda/envs/mesoview/bin/python supervisor.py
```

Or use a **systemd user service** for better logging and control. Create `~/.config/systemd/user/mesoview.service`:

```ini
[Unit]
Description=Mesoview supervisor
After=network.target

[Service]
WorkingDirectory=/path/to/mesoview
ExecStart=/path/to/conda/envs/mesoview/bin/python supervisor.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

Enable and start:

```bash
systemctl --user enable mesoview
systemctl --user start mesoview
systemctl --user status mesoview   # check logs
```

---

### Windows — Task Scheduler

1. Open **Task Scheduler** → **Create Task**
2. **General** tab: give it a name (e.g. `Mesoview`); check *Run whether user is logged on or not*
3. **Triggers** tab: New → *At startup*
4. **Actions** tab: New →
   - **Program/script**: full path to your env's Python, e.g.
     `C:\Users\YOU\miniforge3\envs\mesoview\python.exe`
   - **Add arguments**: `supervisor.py`
   - **Start in**: full path to the repo directory, e.g.
     `C:\path\to\mesoview`
5. **Settings** tab: check *If the task fails, restart every 1 minute*
6. Click OK and enter your Windows password when prompted

To test without rebooting: right-click the task → **Run**.

---

## Updating

```bash
git pull
conda env update -f environment.yml --prune   # pick up any new dependencies
```

No other steps needed — the config file is not touched by git updates.

---

## File layout

```
mesoview/
├── supervisor.py          # start here — runs ingest, viewer, and SSH tunnel; auto-restarts all
├── ingest.py              # fetches data from the datalogger at 1 Hz
├── viewer.py              # Flask SSE server + web dashboard
├── mesoview.config.example.json   # copy to mesoview.config.json and edit
├── environment.yml        # conda environment spec
├── requirements.txt       # pip fallback
├── templates/
│   └── index.html         # single-page dashboard
├── static/                # uPlot chart library
└── test_data/
    └── test.txt           # sample data for --test mode
```

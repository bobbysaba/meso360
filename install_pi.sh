#!/bin/bash
# install_pi.sh — sets up meso360 as a headless boot service on a Raspberry Pi
# (or any systemd Linux box). Run once from the repo, as the user that should
# own the service (not root):
#
#   bash install_pi.sh
#
# Safe to re-run: reuses the existing .venv and config, rewrites the unit file.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE=meso360
UNIT="/etc/systemd/system/$SERVICE.service"
RUN_USER="$(id -un)"

if [ "$(id -u)" -eq 0 ]; then
    echo "Run this as your normal user, not root (sudo is used only where needed)." >&2
    exit 1
fi

# ── System packages ──────────────────────────────────────────────────────────
echo "Installing system packages (python3-venv, git, openssh-client) ..."
sudo apt-get update -qq
sudo apt-get install -y -qq python3-venv python3-pip git openssh-client

# ── Python environment ───────────────────────────────────────────────────────
if [ ! -x "$REPO_DIR/.venv/bin/python" ]; then
    echo "Creating virtualenv at $REPO_DIR/.venv ..."
    python3 -m venv "$REPO_DIR/.venv"
fi
"$REPO_DIR/.venv/bin/pip" install -q --upgrade pip
"$REPO_DIR/.venv/bin/pip" install -q -r "$REPO_DIR/requirements.txt"

# ── Config ───────────────────────────────────────────────────────────────────
if [ ! -f "$REPO_DIR/meso360.config.json" ]; then
    cp "$REPO_DIR/meso360.config.example.json" "$REPO_DIR/meso360.config.json"
    echo "  note : created meso360.config.json from the example — edit logger_ip, rtun_port, etc."
fi

if [ ! -f "$HOME/.ssh/clamps_rsa" ]; then
    echo "  note : ~/.ssh/clamps_rsa not found — mesosync will not connect until it is copied over"
fi

# ── systemd unit ─────────────────────────────────────────────────────────────
echo "Writing $UNIT ..."
sudo tee "$UNIT" > /dev/null << UNITFILE
[Unit]
Description=meso360 supervisor
Wants=network-online.target
After=network-online.target

[Service]
User=$RUN_USER
WorkingDirectory=$REPO_DIR
ExecStart=$REPO_DIR/.venv/bin/python supervisor.py --no-browser
Restart=on-failure
RestartSec=5
KillSignal=SIGTERM
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
UNITFILE

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE"
sudo systemctl restart "$SERVICE"

PORT="$("$REPO_DIR/.venv/bin/python" -c "import json; print(json.load(open('$REPO_DIR/meso360.config.json')).get('http_port', 8080))" 2>/dev/null || echo 8080)"
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

echo
echo "Done. meso360 is running and will start on every boot."
echo "  dashboard : http://${IP:-<pi-ip>}:$PORT"
echo "  status    : sudo systemctl status $SERVICE"
echo "  logs      : journalctl -u $SERVICE -f"

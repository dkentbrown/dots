#!/usr/bin/env bash
# Update the world server to the latest commit and restart it. Run on the server:
#   ssh ubuntu@<ip> 'bash -s' < deploy/aws/update.sh
# The world is saved on stop and resumed on start (/home/noema/world.save), so it carries on.
# The service file is re-installed in case it changed.
set -euo pipefail
BRANCH="${BRANCH:-main}"
cd /opt/noema
sudo -u noema git fetch -q origin "$BRANCH"
# reset rather than pull: headless runs rewrite project.godot on exit (the MCP plugin's
# autoload cleanup), which would block a pull.
sudo -u noema git reset -q --hard "origin/$BRANCH"
sudo -u noema HOME=/home/noema godot --headless --path /opt/noema --import >/dev/null 2>&1 || true
sudo install -m 644 /opt/noema/deploy/aws/noema-server.service /etc/systemd/system/noema-server.service
sudo systemctl daemon-reload
sudo systemctl restart noema-server
echo "Now at $(sudo -u noema git log --oneline -1)"

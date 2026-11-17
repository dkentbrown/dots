#!/usr/bin/env bash
# Update the world server to the latest commit and restart it. Run on the server:
#   ssh ubuntu@<ip> 'bash -s' < deploy/aws/update.sh
# NOTE: there is no world saving yet, so a restart starts a fresh world.
set -euo pipefail
BRANCH="${BRANCH:-main}"
cd /opt/noema
sudo -u noema git fetch -q origin "$BRANCH"
# reset rather than pull: headless runs rewrite project.godot on exit (the MCP plugin's
# autoload cleanup), which would block a pull.
sudo -u noema git reset -q --hard "origin/$BRANCH"
sudo -u noema HOME=/home/noema godot --headless --path /opt/noema --import >/dev/null 2>&1 || true
sudo systemctl restart noema-server
echo "Now at $(git log --oneline -1)"

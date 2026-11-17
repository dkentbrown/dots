#!/usr/bin/env bash
# One-time setup of the Noema world server on a fresh Ubuntu 24.04 machine (EC2 t4g.small, ARM).
# Run as the default `ubuntu` user, from a checkout of this repo or piped over SSH:
#   ssh ubuntu@<ip> 'bash -s' < deploy/aws/setup.sh
#
# It installs Godot (headless) and cloudflared, clones the repo to /opt/noema, and installs three
# systemd pieces: the world server, the Cloudflare Tunnel, and daily rotation of telemetry.jsonl.
# The tunnel's credentials are NOT in the repo: copy them to /etc/cloudflared/ before starting
# the tunnel (see DEVNOTES, "Hosting on AWS").
set -euo pipefail

GODOT_VERSION="4.6.3"
REPO="https://github.com/dkentbrown/dots.git"
BRANCH="${BRANCH:-main}"
APP_DIR="/opt/noema"

case "$(uname -m)" in
	aarch64) GODOT_ARCH="arm64"; CF_ARCH="arm64" ;;
	x86_64)  GODOT_ARCH="x86_64"; CF_ARCH="amd64" ;;
	*) echo "unsupported architecture: $(uname -m)"; exit 1 ;;
esac

sudo apt-get update -q
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q unzip git logrotate ca-certificates curl

# Godot: the standard Linux build runs headless with no display or GPU.
if [ ! -x /usr/local/bin/godot ]; then
	tmp=$(mktemp -d)
	curl -fsSL -o "$tmp/godot.zip" \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH}.zip"
	unzip -q "$tmp/godot.zip" -d "$tmp"
	sudo install -m 755 "$tmp/Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH}" /usr/local/bin/godot
	rm -rf "$tmp"
fi

# cloudflared, from Cloudflare's release .deb.
if ! command -v cloudflared >/dev/null; then
	tmp=$(mktemp -d)
	curl -fsSL -o "$tmp/cloudflared.deb" \
		"https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}.deb"
	sudo dpkg -i "$tmp/cloudflared.deb"
	rm -rf "$tmp"
fi

# A dedicated user owns the checkout and runs the server.
id noema >/dev/null 2>&1 || sudo useradd --system --create-home --home-dir /home/noema --shell /usr/sbin/nologin noema
if [ ! -d "$APP_DIR/.git" ]; then
	sudo git clone --branch "$BRANCH" "$REPO" "$APP_DIR"
fi
sudo chown -R noema:noema "$APP_DIR"
# First import (builds .godot/), so the server's first start isn't an import.
sudo -u noema HOME=/home/noema godot --headless --path "$APP_DIR" --import >/dev/null 2>&1 || true

sudo install -m 644 "$APP_DIR/deploy/aws/noema-server.service" /etc/systemd/system/noema-server.service
sudo install -m 644 "$APP_DIR/deploy/aws/noema-tunnel.service" /etc/systemd/system/noema-tunnel.service
sudo install -m 644 "$APP_DIR/deploy/aws/noema-logrotate" /etc/logrotate.d/noema
sudo mkdir -p /etc/cloudflared
sudo systemctl daemon-reload
sudo systemctl enable --now noema-server
echo
echo "World server installed and started: systemctl status noema-server"
if [ -f /etc/cloudflared/noema.yml ]; then
	sudo systemctl enable --now noema-tunnel
	echo "Tunnel started: systemctl status noema-tunnel"
else
	echo "Tunnel NOT started: copy the tunnel credentials and noema.yml to /etc/cloudflared/, then"
	echo "  sudo systemctl enable --now noema-tunnel"
fi

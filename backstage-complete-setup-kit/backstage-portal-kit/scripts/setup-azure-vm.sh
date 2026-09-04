#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y ca-certificates curl git nginx jq unzip

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi

sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

sudo mkdir -p /opt/backstage
sudo chown -R "$USER":"$USER" /opt/backstage

echo
echo "VM bootstrap complete."
echo "Log out/in so Docker group membership takes effect."

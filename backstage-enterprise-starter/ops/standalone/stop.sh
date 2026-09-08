#!/usr/bin/env bash
set -euo pipefail

pkill -f "backstage-cli package start" || true
pkill -f "yarn start" || true

echo "Backstage stop requested."

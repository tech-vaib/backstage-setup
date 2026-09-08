#!/usr/bin/env bash
set -euo pipefail

if pgrep -f "backstage-cli package start" >/dev/null 2>&1; then
  echo "Backstage: RUNNING"
else
  echo "Backstage: STOPPED"
fi

if systemctl is-active --quiet postgresql; then
  echo "PostgreSQL: RUNNING"
else
  echo "PostgreSQL: STOPPED"
fi

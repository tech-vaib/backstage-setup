#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/backstage}"
cd "$APP_DIR"

test -f .env || { echo ".env missing"; exit 1; }

docker compose pull || true
docker compose up -d

docker compose ps
docker compose logs --tail=100 backstage

curl -fsS http://127.0.0.1:7007 >/dev/null
echo "Backstage is responding on localhost:7007"

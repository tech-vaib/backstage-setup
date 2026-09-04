#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo ".env not found. Copy .env.example to .env and configure it."
  exit 1
fi

docker compose -f docker-compose.standalone-db.yml up -d
yarn start

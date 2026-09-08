#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-ops/config/postgres.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE"
  echo "Copy ops/config/postgres.env.example to ops/config/postgres.env and edit it."
  exit 1
fi

set -a
source "$ENV_FILE"
if [[ -f ops/config/backstage.env ]]; then
  source ops/config/backstage.env
fi
set +a

export BACKSTAGE_IMAGE="${BACKSTAGE_IMAGE:-company-backstage:latest}"

docker compose \
  --env-file "$ENV_FILE" \
  -f ops/docker/docker-compose.yml \
  up -d

docker compose \
  --env-file "$ENV_FILE" \
  -f ops/docker/docker-compose.yml \
  ps

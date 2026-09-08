#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
docker compose --env-file ops/config/postgres.env -f ops/docker/docker-compose.yml stop

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if [[ -f ops/config/postgres.env ]]; then
  set -a
  source ops/config/postgres.env
  set +a
fi

exec yarn start

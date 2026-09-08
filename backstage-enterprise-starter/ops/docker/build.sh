#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

IMAGE_NAME="${IMAGE_NAME:-company-backstage}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

yarn install --immutable
yarn tsc
yarn build:backend

docker build \
  -f packages/backend/Dockerfile \
  -t "${IMAGE_NAME}:${IMAGE_TAG}" \
  .

echo "Built ${IMAGE_NAME}:${IMAGE_TAG}"

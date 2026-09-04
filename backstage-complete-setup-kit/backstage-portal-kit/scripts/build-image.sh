#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:-backstage:$(git rev-parse --short HEAD)}"

yarn install --immutable
yarn tsc
yarn build:backend

docker image build \
  . \
  -f packages/backend/Dockerfile \
  -t "$TAG"

echo "Built $TAG"

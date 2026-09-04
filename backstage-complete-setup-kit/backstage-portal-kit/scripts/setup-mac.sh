#!/usr/bin/env bash
set -euo pipefail

BACKSTAGE_VERSION="${BACKSTAGE_VERSION:-1.54.6}"
APP_NAME="${APP_NAME:-backstage-portal}"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required."
  exit 1
fi

brew install node@22 git yarn
export PATH="/opt/homebrew/opt/node@22/bin:$PATH"

echo "Node: $(node --version)"
echo "Yarn: $(yarn --version)"

mkdir -p "$HOME/backstage"
cd "$HOME/backstage"

if [ -d "$APP_NAME" ]; then
  echo "$HOME/backstage/$APP_NAME already exists. Remove/rename it or set APP_NAME."
  exit 1
fi

npx "@backstage/create-app@${BACKSTAGE_VERSION}"

cd "$APP_NAME"
yarn install

echo
echo "Backstage created at $PWD"
echo "Next:"
echo "  1. Copy this kit's configuration/catalog/scripts/docs into the app."
echo "  2. cp .env.example .env"
echo "  3. docker compose -f docker-compose.standalone-db.yml up -d"
echo "  4. yarn start"

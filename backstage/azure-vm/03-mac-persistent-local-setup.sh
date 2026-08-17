#!/usr/bin/env bash
#
# ============================================================================
#  Backstage.io — MAC PERSISTENT LOCAL INSTANCE  (NOT for production/internet)
# ============================================================================
#  This is the Mac equivalent of "always running without me typing `yarn
#  dev`" — using launchd (macOS's process supervisor) instead of systemd,
#  and Homebrew Postgres instead of a Docker container, so it survives
#  reboots and restarts if it crashes.
#
#  What this is NOT:
#    - Not internet-exposed: binds to 127.0.0.1 only, no nginx, no TLS,
#      no firewall config.
#    - Not the "detach disk, move to new machine" pattern from the Ubuntu
#      VM script — that concept doesn't map to physical Mac hardware.
#      (If you truly need that, run the Ubuntu script on an Ubuntu VM —
#      including one running locally in UTM/Parallels/VMware Fusion on
#      this same Mac, or in Azure.)
#    - Not a substitute for real production hosting — see the Ubuntu VM
#      or AKS scripts for anything your team depends on.
#
#  What it IS: a Backstage instance that stays up on your Mac, backed by
#  real Postgres, that you (or a few teammates on your LAN, if you choose
#  to change the bind address — see notes below) can hit without re-running
#  `yarn dev` every session.
#
#  Usage:
#    export GITHUB_TOKEN="ghp_xxx"
#    # optional: export BACKSTAGE_CREATE_APP_VERSION="1.51.0"
#    chmod +x 03-mac-persistent-local-setup.sh
#    ./03-mac-persistent-local-setup.sh
# ============================================================================

set -euo pipefail

log()  { echo -e "\033[1;36m[mac-setup]\033[0m $1"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $1"; }
err()  { echo -e "\033[1;31m[error]\033[0m $1"; }

: "${GITHUB_TOKEN:?export GITHUB_TOKEN=ghp_xxx}"

APP_DIR="${HOME}/backstage-app"
PG_DB="backstage"
PG_USER="$(whoami)"
NODE_MAJOR=20
BACKSTAGE_CREATE_APP_VERSION="${BACKSTAGE_CREATE_APP_VERSION:-}"
PLIST_LABEL="io.backstage.local"
PLIST_PATH="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"

# ----------------------------------------------------------------------------
# 1. Prerequisites
# ----------------------------------------------------------------------------
command -v brew >/dev/null 2>&1 || { err "Homebrew required: https://brew.sh"; exit 1; }

if ! command -v node >/dev/null 2>&1 || [ "$(node -v | sed 's/v//' | cut -d. -f1)" -lt "$NODE_MAJOR" ]; then
  log "Installing Node ${NODE_MAJOR}..."
  brew install node@${NODE_MAJOR}
  brew link --overwrite --force node@${NODE_MAJOR}
fi
corepack enable

if ! brew list postgresql@16 >/dev/null 2>&1; then
  log "Installing PostgreSQL 16 via Homebrew..."
  brew install postgresql@16
fi
brew services start postgresql@16
sleep 3

createdb "$PG_DB" 2>/dev/null || log "Database '${PG_DB}' already exists."

# ----------------------------------------------------------------------------
# 2. Pin and scaffold
# ----------------------------------------------------------------------------
if [ -z "$BACKSTAGE_CREATE_APP_VERSION" ]; then
  if [ -f "${APP_DIR}.version" ]; then
    BACKSTAGE_CREATE_APP_VERSION=$(cat "${APP_DIR}.version")
  else
    log "Resolving current stable @backstage/create-app version from npm..."
    BACKSTAGE_CREATE_APP_VERSION=$(npm view @backstage/create-app version)
  fi
fi
echo "$BACKSTAGE_CREATE_APP_VERSION" > "${APP_DIR}.version"
log "Pinned @backstage/create-app version: ${BACKSTAGE_CREATE_APP_VERSION}"

if [ ! -d "$APP_DIR" ]; then
  log "Scaffolding Backstage app into ${APP_DIR}..."
  echo "$(basename "$APP_DIR")" | npx --yes "@backstage/create-app@${BACKSTAGE_CREATE_APP_VERSION}" --path "$APP_DIR"
else
  log "App already exists at ${APP_DIR} — skipping scaffold."
fi

cd "$APP_DIR"

BACKEND_SECRET_FILE="${APP_DIR}/.backend_secret"
if [ ! -f "$BACKEND_SECRET_FILE" ]; then
  openssl rand -hex 32 > "$BACKEND_SECRET_FILE"
  chmod 600 "$BACKEND_SECRET_FILE"
fi
BACKEND_SECRET=$(cat "$BACKEND_SECRET_FILE")

# ----------------------------------------------------------------------------
# 3. Config — localhost only, Postgres, guest auth (fine: not exposed)
# ----------------------------------------------------------------------------
cat > "${APP_DIR}/app-config.local-persistent.yaml" <<EOF
backend:
  listen:
    host: 127.0.0.1
    port: 7007
  auth:
    keys:
      - secret: \${BACKEND_SECRET}
  database:
    client: pg
    connection:
      host: 127.0.0.1
      port: 5432
      user: ${PG_USER}
      database: ${PG_DB}

integrations:
  github:
    - host: github.com
      token: \${GITHUB_TOKEN}
EOF

# ----------------------------------------------------------------------------
# 4. Build (production build, but bound to localhost — not exposed)
# ----------------------------------------------------------------------------
log "Installing dependencies and building..."
yarn install --immutable
yarn tsc
yarn --cwd packages/app build
yarn build:backend --config app-config.yaml --config app-config.local-persistent.yaml

# ----------------------------------------------------------------------------
# 5. launchd agent — starts on login, restarts if it crashes
# ----------------------------------------------------------------------------
log "Writing launchd agent at ${PLIST_PATH}..."
mkdir -p "${HOME}/Library/LaunchAgents"
mkdir -p "${HOME}/Library/Logs/backstage"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(command -v node)</string>
    <string>packages/backend</string>
    <string>--config</string><string>app-config.yaml</string>
    <string>--config</string><string>app-config.local-persistent.yaml</string>
  </array>
  <key>WorkingDirectory</key><string>${APP_DIR}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>NODE_ENV</key><string>production</string>
    <key>GITHUB_TOKEN</key><string>${GITHUB_TOKEN}</string>
    <key>BACKEND_SECRET</key><string>${BACKEND_SECRET}</string>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${HOME}/Library/Logs/backstage/out.log</string>
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/backstage/err.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo ""
log "Done. Backstage is running under launchd at http://localhost:7007"
echo "  Version pinned : ${BACKSTAGE_CREATE_APP_VERSION}"
echo "  Logs           : tail -f ${HOME}/Library/Logs/backstage/out.log"
echo "  Stop           : launchctl unload ${PLIST_PATH}"
echo "  Start          : launchctl load ${PLIST_PATH}"
echo "  Uninstall      : launchctl unload ${PLIST_PATH} && rm ${PLIST_PATH}"
echo ""
warn "This is bound to 127.0.0.1 only — it is not reachable from other machines and has no TLS."
warn "Do not port-forward this or expose it beyond your own Mac without redoing this as a real VM deployment."

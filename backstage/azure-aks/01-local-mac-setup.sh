#!/usr/bin/env bash
#
# ============================================================================
#  Backstage.io — LOCAL MAC DEMO SETUP
# ============================================================================
#  Purpose : Stand up a working Backstage instance on your Mac in one go,
#            with GitHub integration and TechDocs enabled, so you can demo
#            the Software Catalog + Docs experience to your team.
#
#  Usage   : chmod +x 01-local-mac-setup.sh
#            ./01-local-mac-setup.sh
#
#  What it does:
#    1. Checks/installs prerequisites (Homebrew, Node LTS, Yarn, Git, Docker)
#    2. Scaffolds a new Backstage app (non-interactively)
#    3. Wires up a local Postgres (via Docker) as the catalog database
#    4. Configures GitHub integration (needs a GitHub PAT — see prompt below)
#    5. Starts the app at http://localhost:3000 (frontend) / :7007 (backend)
#
#  Safe to re-run: it skips steps that are already done.
# ============================================================================

set -euo pipefail

APP_DIR_NAME="${1:-backstage-demo}"
NODE_MAJOR_REQUIRED=20   # Backstage requires an Active LTS Node release (20 or 22 as of 2026)
POSTGRES_CONTAINER_NAME="backstage-postgres"
POSTGRES_PASSWORD="backstage"
POSTGRES_PORT=5432

log()  { echo -e "\033[1;36m[setup]\033[0m $1"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $1"; }
err()  { echo -e "\033[1;31m[error]\033[0m $1"; }

# ----------------------------------------------------------------------------
# 1. Prerequisites
# ----------------------------------------------------------------------------
log "Checking prerequisites..."

if ! command -v brew >/dev/null 2>&1; then
  log "Homebrew not found — installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if ! command -v node >/dev/null 2>&1; then
  log "Node.js not found — installing Node ${NODE_MAJOR_REQUIRED} via Homebrew..."
  brew install node@${NODE_MAJOR_REQUIRED}
  brew link --overwrite --force node@${NODE_MAJOR_REQUIRED}
else
  NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
  log "Node.js found: $(node -v)"
  if [ "$NODE_VERSION" -lt "$NODE_MAJOR_REQUIRED" ]; then
    warn "Node ${NODE_VERSION} is older than recommended (${NODE_MAJOR_REQUIRED}+). Consider: brew install node@${NODE_MAJOR_REQUIRED}"
  fi
fi

if ! command -v yarn >/dev/null 2>&1; then
  log "Yarn not found — installing..."
  npm install --global yarn
else
  log "Yarn found: $(yarn -v)"
fi

if ! command -v git >/dev/null 2>&1; then
  log "Git not found — installing..."
  brew install git
fi

if ! command -v docker >/dev/null 2>&1; then
  warn "Docker not found. Install Docker Desktop for Mac: https://www.docker.com/products/docker-desktop/"
  warn "We'll use it to run a local Postgres. You can also skip Docker and use SQLite for a quick demo (less realistic)."
fi

# Python is occasionally needed by native deps during install
if ! command -v python3 >/dev/null 2>&1; then
  brew install python3
fi

# ----------------------------------------------------------------------------
# 2. GitHub token (needed for GitHub catalog discovery + auth demo)
# ----------------------------------------------------------------------------
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo ""
  echo "A GitHub Personal Access Token is needed so Backstage can read your repos"
  echo "(catalog-info.yaml discovery, TechDocs source, auth)."
  echo "Create one at: https://github.com/settings/tokens (classic, scopes: repo, read:org, read:user)"
  read -r -p "Paste your GitHub token (or press Enter to skip and add later): " GITHUB_TOKEN_INPUT
  export GITHUB_TOKEN="${GITHUB_TOKEN_INPUT:-}"
fi

# ----------------------------------------------------------------------------
# 3. Scaffold the Backstage app (non-interactive)
# ----------------------------------------------------------------------------
if [ -d "$APP_DIR_NAME" ]; then
  log "Directory '$APP_DIR_NAME' already exists — skipping scaffold step."
else
  log "Scaffolding new Backstage app in ./${APP_DIR_NAME} ..."
  # The create-app CLI prompts for an app name; we pipe it in.
  echo "$APP_DIR_NAME" | npx --yes @backstage/create-app@latest --path "$APP_DIR_NAME"
fi

cd "$APP_DIR_NAME"

# ----------------------------------------------------------------------------
# 4. Local Postgres via Docker (recommended over SQLite even for demos)
# ----------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1; then
  if [ "$(docker ps -aq -f name=${POSTGRES_CONTAINER_NAME})" ]; then
    log "Postgres container '${POSTGRES_CONTAINER_NAME}' already exists — starting it."
    docker start "${POSTGRES_CONTAINER_NAME}" >/dev/null
  else
    log "Starting Postgres container for the Backstage catalog DB..."
    docker run -d --name "${POSTGRES_CONTAINER_NAME}" \
      -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
      -p ${POSTGRES_PORT}:5432 \
      postgres:16
    log "Waiting for Postgres to be ready..."
    sleep 6
  fi
  USE_POSTGRES=true
else
  warn "Docker unavailable — falling back to SQLite (fine for a quick demo, not representative of prod)."
  USE_POSTGRES=false
fi

# ----------------------------------------------------------------------------
# 5. Write app-config.local.yaml with GitHub + DB config
#    (app-config.local.yaml is git-ignored by default — safe for secrets)
# ----------------------------------------------------------------------------
log "Writing app-config.local.yaml ..."

if [ "$USE_POSTGRES" = true ]; then
  cat > app-config.local.yaml <<EOF
backend:
  database:
    client: pg
    connection:
      host: 127.0.0.1
      port: ${POSTGRES_PORT}
      user: postgres
      password: ${POSTGRES_PASSWORD}

integrations:
  github:
    - host: github.com
      token: \${GITHUB_TOKEN}

auth:
  providers:
    github:
      development:
        clientId: \${AUTH_GITHUB_CLIENT_ID}
        clientSecret: \${AUTH_GITHUB_CLIENT_SECRET}
EOF
else
  cat > app-config.local.yaml <<EOF
integrations:
  github:
    - host: github.com
      token: \${GITHUB_TOKEN}
EOF
fi

# ----------------------------------------------------------------------------
# 6. Add a sample catalog entity so the demo isn't an empty catalog
# ----------------------------------------------------------------------------
if [ ! -f "catalog-info.yaml" ]; then
  cat > catalog-info.yaml <<'EOF'
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: backstage-demo
  description: Demo component registered to show off the Software Catalog
  annotations:
    backstage.io/techdocs-ref: dir:.
spec:
  type: service
  lifecycle: experimental
  owner: guests
EOF
fi

# ----------------------------------------------------------------------------
# 7. Install dependencies
# ----------------------------------------------------------------------------
log "Installing dependencies (this can take a few minutes)..."
yarn install

# ----------------------------------------------------------------------------
# 8. Launch
# ----------------------------------------------------------------------------
echo ""
log "Setup complete."
log "Starting Backstage — frontend on http://localhost:3000, backend on http://localhost:7007"
log "Press Ctrl+C to stop."
echo ""

GITHUB_TOKEN="${GITHUB_TOKEN:-}" yarn start

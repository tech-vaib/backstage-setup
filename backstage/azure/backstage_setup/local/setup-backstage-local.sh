#!/usr/bin/env bash
set -Eeuo pipefail

# Backstage local POC bootstrap for macOS.
# Creates a standalone Backstage app, local PostgreSQL via Docker, sample catalog entities,
# TechDocs, and a run/stop helper. It intentionally uses Guest auth for a frictionless demo.
# For production/AKS use the Azure script in ../azure/.

APP_NAME="${BACKSTAGE_APP_NAME:-backstage-demo}"
WORK_DIR="${BACKSTAGE_WORK_DIR:-$PWD}"
APP_DIR="$WORK_DIR/$APP_NAME"
PG_CONTAINER="${BACKSTAGE_PG_CONTAINER:-backstage-postgres}"
PG_DB="${BACKSTAGE_PG_DB:-backstage_plugin_catalog}"
PG_USER="${BACKSTAGE_PG_USER:-backstage}"
PG_PASSWORD="${BACKSTAGE_PG_PASSWORD:-backstage-local-change-me}"
PG_PORT="${BACKSTAGE_PG_PORT:-5432}"

log(){ printf '\n\033[1;36m[Backstage]\033[0m %s\n' "$*"; }
die(){ printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
trap 'die "Failed at line $LINENO. See the command above for details."' ERR

command -v brew >/dev/null 2>&1 || die "Homebrew is required. Install it from https://brew.sh/ and rerun."
brew list --formula node >/dev/null 2>&1 || brew install node
brew list --formula git >/dev/null 2>&1 || brew install git
brew list --formula coreutils >/dev/null 2>&1 || brew install coreutils
command -v docker >/dev/null 2>&1 || die "Docker Desktop is required. Start Docker Desktop and rerun."
docker info >/dev/null 2>&1 || die "Docker is not running. Start Docker Desktop and rerun."

node -v
npm -v
corepack enable
corepack prepare yarn@4.4.1 --activate
yarn --version

if [ ! -d "$APP_DIR" ]; then
  log "Creating Backstage app: $APP_DIR"
  mkdir -p "$WORK_DIR"
  cd "$WORK_DIR"
  printf '%s\n' "$APP_NAME" | npx @backstage/create-app@latest
else
  log "Using existing Backstage app: $APP_DIR"
fi

cd "$APP_DIR"

log "Installing PostgreSQL driver"
yarn --cwd packages/backend add pg

log "Starting local PostgreSQL"
if docker ps -a --format '{{.Names}}' | grep -qx "$PG_CONTAINER"; then
  docker start "$PG_CONTAINER" >/dev/null 2>&1 || true
else
  docker run -d --name "$PG_CONTAINER" \
    --restart unless-stopped \
    -p "${PG_PORT}:5432" \
    -e POSTGRES_USER="$PG_USER" \
    -e POSTGRES_PASSWORD="$PG_PASSWORD" \
    -e POSTGRES_DB="$PG_DB" \
    postgres:18-trixie >/dev/null
fi

until docker exec "$PG_CONTAINER" pg_isready -U "$PG_USER" -d "$PG_DB" >/dev/null 2>&1; do
  sleep 2
done

cat > app-config.local.yaml <<EOF
app:
  baseUrl: http://localhost:3000

backend:
  baseUrl: http://localhost:7007
  listen:
    host: 0.0.0.0
    port: 7007
  cors:
    origin: http://localhost:3000
  database:
    client: pg
    connection:
      host: 127.0.0.1
      port: ${PG_PORT}
      user: ${PG_USER}
      password: ${PG_PASSWORD}
      database: ${PG_DB}

auth:
  environment: development
  providers:
    guest: {}

catalog:
  locations:
    - type: file
      target: ./examples/demo-catalog.yaml
    - type: file
      target: ./examples/demo-team.yaml

techdocs:
  builder: local
  generator:
    runIn: docker
  publisher:
    type: local
EOF

mkdir -p examples/demo-docs/docs
cat > examples/demo-catalog.yaml <<'EOF'
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: demo-orders-api
  description: Demo service representing an AKS-hosted application.
  annotations:
    github.com/project-slug: example/demo-orders-api
    backstage.io/techdocs-ref: dir:./demo-docs
spec:
  type: service
  lifecycle: experimental
  owner: platform-team
  system: demo-platform
---
apiVersion: backstage.io/v1alpha1
kind: System
metadata:
  name: demo-platform
  description: Demo application platform
spec:
  owner: platform-team
---
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: orders-api
  description: Demo REST API
spec:
  type: openapi
  lifecycle: experimental
  owner: platform-team
  definition: |
    openapi: 3.0.0
    info:
      title: Orders API
      version: 1.0.0
    paths:
      /orders:
        get:
          responses:
            '200':
              description: OK
EOF

cat > examples/demo-team.yaml <<'EOF'
apiVersion: backstage.io/v1alpha1
kind: Group
metadata:
  name: platform-team
  description: Demo platform engineering team
spec:
  type: team
  profile:
    displayName: Platform Engineering
  children: []
EOF

cat > examples/demo-docs/mkdocs.yml <<'EOF'
site_name: Demo Orders API
site_description: Example TechDocs site for the Backstage proof of concept
plugins:
  - techdocs-core
nav:
  - Overview: index.md
  - Operations: operations.md
EOF

cat > examples/demo-docs/docs/index.md <<'EOF'
# Demo Orders API

This is a sample TechDocs site.

## Purpose

This demonstrates the "docs as code" workflow that can later be attached to GitHub repositories.

## Production mapping

- Source: GitHub
- Runtime: AKS
- API gateway: Azure API Management
- Edge: Azure Application Gateway
- Database: Azure Cosmos DB for MongoDB
- Platform database: Azure Database for PostgreSQL
- Documentation storage: Azure Blob Storage
EOF

cat > examples/demo-docs/docs/operations.md <<'EOF'
# Operations

## Health

Backstage exposes its backend on port `7007`.

## Production checklist

1. Entra ID authentication
2. PostgreSQL with backups and HA
3. Azure Workload Identity
4. ACR image scanning
5. Application Gateway / APIM ingress
6. Azure Monitor / OpenTelemetry
7. GitHub integration
8. TechDocs in Azure Blob Storage
EOF

# Avoid committing local credentials.
cat > .gitignore.backstage-local <<'EOF'
app-config.local.yaml
EOF
grep -qxF 'app-config.local.yaml' .gitignore 2>/dev/null || echo 'app-config.local.yaml' >> .gitignore

log "Validating Backstage configuration"
yarn backstage-cli config:check --strict --config app-config.yaml --config app-config.local.yaml

cat > run-backstage.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
docker start "${BACKSTAGE_PG_CONTAINER:-backstage-postgres}" >/dev/null 2>&1 || true
exec yarn start
EOF
chmod +x run-backstage.sh

cat > stop-backstage.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
docker stop "${BACKSTAGE_PG_CONTAINER:-backstage-postgres}" >/dev/null 2>&1 || true
echo "Backstage PostgreSQL container stopped. Backstage dev process can be stopped with Ctrl-C."
EOF
chmod +x stop-backstage.sh

log "LOCAL POC READY"
echo "App:      $APP_DIR"
echo "Backstage: http://localhost:3000"
echo "Backend:   http://localhost:7007"
echo "Database:  PostgreSQL on localhost:${PG_PORT}"
echo
echo "Run:"
echo "  cd '$APP_DIR' && ./run-backstage.sh"
echo
echo "Then open http://localhost:3000"
echo "This POC uses Guest auth intentionally. Do NOT expose it outside your laptop."

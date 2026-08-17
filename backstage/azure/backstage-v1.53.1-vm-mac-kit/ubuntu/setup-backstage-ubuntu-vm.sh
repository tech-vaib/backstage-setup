#!/usr/bin/env bash
set -Eeuo pipefail

# Backstage production-style single-VM installer.
# Pinned stable release: v1.53.1
# Persistent Azure Managed Disk recommendation: /mnt/backstage-data
# Usage:
# sudo DATA_ROOT=/mnt/backstage-data BACKSTAGE_HOST=backstage.example.com ./setup-backstage-ubuntu-vm.sh

BACKSTAGE_VERSION="${BACKSTAGE_VERSION:-1.53.1}"
DATA_ROOT="${DATA_ROOT:-/mnt/backstage-data}"
APP_DIR="${DATA_ROOT}/app"
PGDATA_DIR="${DATA_ROOT}/postgres"
BACKUP_DIR="${DATA_ROOT}/backups"
BACKSTAGE_HOST="${BACKSTAGE_HOST:-localhost}"
BACKSTAGE_PORT="${BACKSTAGE_PORT:-7007}"
ENABLE_TLS="${ENABLE_TLS:-false}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
AUTH_MODE="${AUTH_MODE:-guest}" # guest|microsoft
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-}"
AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET:-}"
AZURE_TENANT_ID="${AZURE_TENANT_ID:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

[[ $EUID -eq 0 ]] || { echo "Run with sudo/root"; exit 1; }
[[ "$AUTH_MODE" == guest || "$AUTH_MODE" == microsoft ]] || { echo "AUTH_MODE must be guest or microsoft"; exit 1; }
[[ "$AUTH_MODE" != microsoft || ( -n "$AZURE_CLIENT_ID" && -n "$AZURE_CLIENT_SECRET" && -n "$AZURE_TENANT_ID" ) ]] || { echo "Microsoft auth requires AZURE_CLIENT_ID/AZURE_CLIENT_SECRET/AZURE_TENANT_ID"; exit 1; }
[[ "$ENABLE_TLS" != true || "$BACKSTAGE_HOST" != localhost ]] || { echo "TLS requires a real DNS hostname"; exit 1; }

apt-get update
apt-get install -y ca-certificates curl gnupg git jq openssl rsync nginx postgresql-client
install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; fi
chmod a+r /etc/apt/keyrings/docker.gpg
ARCH=$(dpkg --print-architecture); CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu %s stable\n' "$ARCH" "$CODENAME" >/etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

mkdir -p "$APP_DIR" "$PGDATA_DIR" "$BACKUP_DIR"
chmod 700 "$DATA_ROOT" "$PGDATA_DIR" "$BACKUP_DIR"
AVAIL_GB=$(df -Pk "$DATA_ROOT" | awk 'NR==2{print int($4/1024/1024)}')
(( AVAIL_GB >= 20 )) || { echo "Need at least 20GB free on DATA_ROOT; found ${AVAIL_GB}GB"; exit 1; }

if ! command -v node >/dev/null 2>&1 || [[ $(node -v) != v24.* ]]; then curl -fsSL https://deb.nodesource.com/setup_24.x | bash -; apt-get install -y nodejs; fi
corepack enable
corepack prepare yarn@4.4.1 --activate

if [[ ! -f "$APP_DIR/backstage.json" ]]; then
  TMP=$(mktemp -d); cd "$TMP"
  npx @backstage/create-app@latest --skip-install "$APP_DIR"
  rm -rf "$TMP"
  cd "$APP_DIR"
  yarn install
  yarn backstage-cli versions:bump --release "$BACKSTAGE_VERSION"
  yarn install
else
  cd "$APP_DIR"
fi

ENV_FILE="$DATA_ROOT/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  PG_PASSWORD=$(openssl rand -hex 32)
  BACKEND_SECRET=$(openssl rand -hex 32)
  cat >"$ENV_FILE" <<EOT
BACKSTAGE_VERSION=$BACKSTAGE_VERSION
POSTGRES_USER=backstage
POSTGRES_PASSWORD=$PG_PASSWORD
POSTGRES_DB=backstage
BACKEND_SECRET=$BACKEND_SECRET
AZURE_CLIENT_ID=$AZURE_CLIENT_ID
AZURE_CLIENT_SECRET=$AZURE_CLIENT_SECRET
AZURE_TENANT_ID=$AZURE_TENANT_ID
GITHUB_TOKEN=$GITHUB_TOKEN
EOT
  chmod 600 "$ENV_FILE"
fi
set -a; source "$ENV_FILE"; set +a

SCHEME=http
[[ "$ENABLE_TLS" == true ]] && SCHEME=https
cat >"$APP_DIR/app-config.production.yaml" <<EOT
app:
  baseUrl: ${SCHEME}://${BACKSTAGE_HOST}
organization:
  name: Platform Engineering
backend:
  baseUrl: ${SCHEME}://${BACKSTAGE_HOST}
  listen:
    host: 0.0.0.0
    port: ${BACKSTAGE_PORT}
  cors:
    origin: ${SCHEME}://${BACKSTAGE_HOST}
    credentials: true
  database:
    client: pg
    connection:
      host: postgres
      port: 5432
      user: \${POSTGRES_USER}
      password: \${POSTGRES_PASSWORD}
      database: \${POSTGRES_DB}
auth:
  environment: production
EOT
if [[ "$AUTH_MODE" == guest ]]; then cat >>"$APP_DIR/app-config.production.yaml" <<'EOT'
  providers:
    guest: {}
EOT
else
  cat >>"$APP_DIR/app-config.production.yaml" <<'EOT'
  providers:
    microsoft:
      production:
        clientId: ${AZURE_CLIENT_ID}
        clientSecret: ${AZURE_CLIENT_SECRET}
        tenantId: ${AZURE_TENANT_ID}
        signIn:
          resolvers:
            - resolver: emailMatchingUserEntityProfileEmail
EOT
  yarn --cwd packages/backend add @backstage/plugin-auth-backend-module-microsoft-provider
  grep -q 'plugin-auth-backend-module-microsoft-provider' packages/backend/src/index.ts || printf '\nbackend.add(import("@backstage/plugin-auth-backend-module-microsoft-provider"));\n' >> packages/backend/src/index.ts
fi
if [[ -n "$GITHUB_TOKEN" ]]; then cat >>"$APP_DIR/app-config.production.yaml" <<'EOT'
integrations:
  github:
    - host: github.com
      token: ${GITHUB_TOKEN}
EOT
fi

mkdir -p "$APP_DIR/catalog"
cat >"$APP_DIR/catalog/platform-demo.yaml" <<'EOT'
apiVersion: backstage.io/v1alpha1
kind: Group
metadata:
  name: platform-engineering
spec:
  type: team
  profile:
    displayName: Platform Engineering
  children: []
---
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: platform-demo-service
  description: Demo Backstage service
spec:
  type: service
  lifecycle: production
  owner: group:platform-engineering
EOT
if ! grep -q 'catalog/platform-demo.yaml' "$APP_DIR/app-config.yaml"; then cat >>"$APP_DIR/app-config.yaml" <<'EOT'

catalog:
  locations:
    - type: file
      target: ./catalog/platform-demo.yaml
EOT
fi

cat >"$APP_DIR/Dockerfile.production" <<'EOT'
FROM node:24-bookworm-slim AS build
WORKDIR /app
RUN corepack enable && corepack prepare yarn@4.4.1 --activate
COPY . .
RUN yarn install --immutable
RUN yarn tsc
RUN yarn build:backend
FROM node:24-bookworm-slim
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /app/package.json /app/yarn.lock /app/.yarnrc.yml ./
COPY --from=build /app/packages/backend/dist ./packages/backend/dist
COPY --from=build /app/packages/backend/package.json ./packages/backend/package.json
COPY --from=build /app/app-config.yaml ./app-config.yaml
COPY --from=build /app/app-config.production.yaml ./app-config.production.yaml
COPY --from=build /app/catalog ./catalog
COPY --from=build /app/node_modules ./node_modules
EXPOSE 7007
USER node
CMD ["node","packages/backend","--config","app-config.yaml","--config","app-config.production.yaml"]
EOT

cat >"$DATA_ROOT/compose.yaml" <<EOT
services:
  postgres:
    image: postgres:18-trixie
    container_name: backstage-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
    volumes:
      - ${PGDATA_DIR}:/var/lib/postgresql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10
  backstage:
    image: backstage-custom:${BACKSTAGE_VERSION}
    container_name: backstage
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      NODE_ENV: production
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
      BACKEND_SECRET: \${BACKEND_SECRET}
      AZURE_CLIENT_ID: \${AZURE_CLIENT_ID}
      AZURE_CLIENT_SECRET: \${AZURE_CLIENT_SECRET}
      AZURE_TENANT_ID: \${AZURE_TENANT_ID}
      GITHUB_TOKEN: \${GITHUB_TOKEN}
    ports:
      - "127.0.0.1:${BACKSTAGE_PORT}:7007"
EOT
chmod 600 "$DATA_ROOT/compose.yaml"

docker build --pull -f "$APP_DIR/Dockerfile.production" -t "backstage-custom:${BACKSTAGE_VERSION}" "$APP_DIR"
docker compose --env-file "$ENV_FILE" -f "$DATA_ROOT/compose.yaml" up -d

cat >/etc/nginx/sites-available/backstage <<EOT
server {
  listen 80;
  server_name ${BACKSTAGE_HOST};
  location / {
    proxy_pass http://127.0.0.1:${BACKSTAGE_PORT};
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 120s;
  }
}
EOT
ln -sf /etc/nginx/sites-available/backstage /etc/nginx/sites-enabled/backstage
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

cat >/etc/systemd/system/backstage.service <<EOT
[Unit]
Description=Backstage Developer Portal
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${DATA_ROOT}
ExecStart=/usr/bin/docker compose --env-file ${ENV_FILE} -f ${DATA_ROOT}/compose.yaml up -d
ExecStop=/usr/bin/docker compose --env-file ${ENV_FILE} -f ${DATA_ROOT}/compose.yaml down
TimeoutStartSec=0
[Install]
WantedBy=multi-user.target
EOT
systemctl daemon-reload
systemctl enable backstage

cat >"$DATA_ROOT/backup-postgres.sh" <<'EOT'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"; source "$ROOT/.env"; mkdir -p "$ROOT/backups"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"; OUT="$ROOT/backups/backstage_${STAMP}.sql.gz"
docker exec backstage-postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" | gzip >"$OUT"; chmod 600 "$OUT"; echo "$OUT"
find "$ROOT/backups" -type f -name 'backstage_*.sql.gz' -mtime +14 -delete
EOT
chmod +x "$DATA_ROOT/backup-postgres.sh"

cat >"$DATA_ROOT/restore-postgres.sh" <<'EOT'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"; source "$ROOT/.env"; FILE="${1:?Usage: $0 backup.sql.gz}"
read -r -p 'Type RESTORE to continue: ' A; [[ "$A" == RESTORE ]]
docker compose --env-file "$ROOT/.env" -f "$ROOT/compose.yaml" stop backstage
gunzip -c "$FILE" | docker exec -i backstage-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
docker compose --env-file "$ROOT/.env" -f "$ROOT/compose.yaml" start backstage
EOT
chmod +x "$DATA_ROOT/restore-postgres.sh"

cat >"$DATA_ROOT/upgrade-backstage.sh" <<'EOT'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"; TARGET="${1:?Usage: $0 <release>}"; APP="$ROOT/app"
"$ROOT/backup-postgres.sh"; cd "$APP"; yarn backstage-cli versions:bump --release "$TARGET"; yarn install
sed -i "s/^BACKSTAGE_VERSION=.*/BACKSTAGE_VERSION=$TARGET/" "$ROOT/.env"
sed -i "s#image: backstage-custom:.*#image: backstage-custom:$TARGET#" "$ROOT/compose.yaml"
docker build --pull -f Dockerfile.production -t "backstage-custom:$TARGET" .
docker compose --env-file "$ROOT/.env" -f "$ROOT/compose.yaml" up -d
EOT
chmod +x "$DATA_ROOT/upgrade-backstage.sh"

cat >"$DATA_ROOT/MIGRATE-TO-NEW-VM.md" <<'EOT'
# Move Backstage to another VM
1. `sudo systemctl stop backstage`
2. `sudo /mnt/backstage-data/backup-postgres.sh`
3. Detach the Azure Managed Disk containing DATA_ROOT.
4. Attach it to the replacement Ubuntu VM and mount at the same path.
5. Run the installer with the same DATA_ROOT/BACKSTAGE_HOST.
6. Verify the existing app, `.env`, compose file and PostgreSQL data.
7. `sudo systemctl start backstage`
8. Test the endpoint and then repoint DNS/Application Gateway.

A detachable disk is not a backup. Keep independent backups in Azure Storage/Backup.
EOT

if [[ "$ENABLE_TLS" == true ]]; then
  apt-get install -y certbot python3-certbot-nginx
  [[ -n "$CERTBOT_EMAIL" ]] || { echo "CERTBOT_EMAIL required"; exit 1; }
  certbot --nginx --non-interactive --agree-tos -m "$CERTBOT_EMAIL" -d "$BACKSTAGE_HOST" --redirect
fi

echo "Backstage $BACKSTAGE_VERSION installed. URL: ${SCHEME}://${BACKSTAGE_HOST}"
echo "Persistent data: $DATA_ROOT"
echo "Postgres data: $PGDATA_DIR"
echo "Backup: $DATA_ROOT/backup-postgres.sh"
[[ "$AUTH_MODE" == guest ]] && echo "WARNING: Guest auth is for controlled POC/testing only; use Entra before enterprise exposure."

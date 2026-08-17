#!/usr/bin/env bash
set -Eeuo pipefail
# macOS local/demo deployment, pinned to Backstage v1.53.1.
BACKSTAGE_VERSION="${BACKSTAGE_VERSION:-1.53.1}"
ROOT="${ROOT:-$HOME/backstage-platform}"; APP="$ROOT/app"; PG="$ROOT/postgres"; PORT="${PORT:-7007}"
command -v brew >/dev/null || { echo 'Install Homebrew first'; exit 1; }
command -v docker >/dev/null || { echo 'Install Docker Desktop first'; exit 1; }
docker info >/dev/null || { echo 'Start Docker Desktop first'; exit 1; }
mkdir -p "$APP" "$PG" "$ROOT/backups"; chmod 700 "$ROOT" "$PG"
if ! command -v node >/dev/null 2>&1 || [[ $(node -v) != v24.* ]]; then brew install node@24; export PATH="$(brew --prefix node@24)/bin:$PATH"; fi
corepack enable; corepack prepare yarn@4.4.1 --activate
if [[ ! -f "$APP/backstage.json" ]]; then
  T=$(mktemp -d); cd "$T"; npx @backstage/create-app@latest --skip-install "$APP"; rm -rf "$T"; cd "$APP"; yarn install; yarn backstage-cli versions:bump --release "$BACKSTAGE_VERSION"; yarn install
else cd "$APP"; fi
if [[ ! -f "$ROOT/.env" ]]; then P=$(openssl rand -hex 32); printf 'BACKSTAGE_VERSION=%s\nPOSTGRES_USER=backstage\nPOSTGRES_PASSWORD=%s\nPOSTGRES_DB=backstage\n' "$BACKSTAGE_VERSION" "$P" >"$ROOT/.env"; chmod 600 "$ROOT/.env"; fi
cat >"$APP/app-config.production.yaml" <<EOT
app:
  baseUrl: http://localhost:${PORT}
organization:
  name: Platform Engineering
backend:
  baseUrl: http://localhost:${PORT}
  listen: { host: 0.0.0.0, port: ${PORT} }
  database:
    client: pg
    connection:
      host: postgres
      port: 5432
      user: \${POSTGRES_USER}
      password: \${POSTGRES_PASSWORD}
      database: \${POSTGRES_DB}
auth:
  environment: development
  providers: { guest: {} }
EOT
cat >"$APP/Dockerfile.production" <<'EOT'
FROM node:24-bookworm-slim AS build
WORKDIR /app
RUN corepack enable && corepack prepare yarn@4.4.1 --activate
COPY . .
RUN yarn install --immutable && yarn tsc && yarn build:backend
FROM node:24-bookworm-slim
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /app/package.json /app/yarn.lock /app/.yarnrc.yml ./
COPY --from=build /app/packages/backend/dist ./packages/backend/dist
COPY --from=build /app/packages/backend/package.json ./packages/backend/package.json
COPY --from=build /app/app-config.yaml ./app-config.yaml
COPY --from=build /app/app-config.production.yaml ./app-config.production.yaml
COPY --from=build /app/node_modules ./node_modules
EXPOSE 7007
USER node
CMD ["node","packages/backend","--config","app-config.yaml","--config","app-config.production.yaml"]
EOT
cat >"$ROOT/compose.yaml" <<EOT
services:
  postgres:
    image: postgres:18-trixie
    restart: unless-stopped
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
    volumes: ["${PG}:/var/lib/postgresql"]
    healthcheck: {test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"], interval: 10s, timeout: 5s, retries: 10}
  backstage:
    image: backstage-custom:${BACKSTAGE_VERSION}
    restart: unless-stopped
    depends_on: {postgres: {condition: service_healthy}}
    environment: {NODE_ENV: production, POSTGRES_USER: \${POSTGRES_USER}, POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}, POSTGRES_DB: \${POSTGRES_DB}}
    ports: ["127.0.0.1:${PORT}:7007"]
EOT
docker build --pull -f "$APP/Dockerfile.production" -t "backstage-custom:${BACKSTAGE_VERSION}" "$APP"
docker compose --env-file "$ROOT/.env" -f "$ROOT/compose.yaml" up -d
cat >"$ROOT/backup-postgres.sh" <<'EOT'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"; source "$ROOT/.env"; STAMP=$(date -u +%Y%m%dT%H%M%SZ)
ID=$(docker ps --filter name=postgres --format '{{.ID}}' | head -1); docker exec "$ID" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" | gzip >"$ROOT/backups/backstage_${STAMP}.sql.gz"
echo "$ROOT/backups/backstage_${STAMP}.sql.gz"
EOT
chmod +x "$ROOT/backup-postgres.sh"
echo "Backstage $BACKSTAGE_VERSION: http://localhost:${PORT}"; echo "Persistent root: $ROOT"

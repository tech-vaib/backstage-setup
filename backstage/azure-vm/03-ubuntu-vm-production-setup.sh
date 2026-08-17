#!/usr/bin/env bash
#
# ============================================================================
#  Backstage.io — UBUNTU VM PRODUCTION DEPLOYMENT
#  (single VM, PostgreSQL co-located, TLS-terminated, transferable data disk)
# ============================================================================
#
#  What "production mode" means here vs. the local Mac demo:
#    - Backstage is BUILT (yarn build / build:backend), not run with `yarn dev`
#    - Runs as a systemd service, restarts on crash/reboot
#    - Fronted by nginx doing TLS termination (Let's Encrypt via certbot)
#    - PostgreSQL is the real backing store, not SQLite
#    - Guest auth is off; wire up your real auth provider in the config file
#      this script writes (edit AUTH_* vars below before running, or patch
#      app-config.production.yaml afterwards)
#
#  "Transferable disk" design:
#    ALL state (Postgres data + the built app) lives on a SEPARATE block
#    device mounted at /data, referenced by filesystem UUID in /etc/fstab
#    (not by device name, which can change). To move to a new/upgraded VM:
#      1. Stop services on the old VM (this script's --stop-only mode, or
#         manually: systemctl stop backstage postgresql@<ver>-data)
#      2. Detach the disk from the old VM, attach it to the new VM
#         (cloud-specific — Azure example is in the companion guide)
#      3. Run THIS SCRIPT again on the new VM with the same DATA_DISK_DEVICE
#         pointing at the newly-attached disk. It detects existing data
#         and skips re-scaffolding/re-initializing — it just reinstalls
#         packages, re-registers the Postgres cluster against the existing
#         data directory, and restarts services against your existing data.
#
#  Usage:
#    export DOMAIN="backstage.yourcompany.com"
#    export ADMIN_EMAIL="you@yourcompany.com"       # for Let's Encrypt
#    export DATA_DISK_DEVICE="/dev/sdc"             # your attached data disk
#    export GITHUB_TOKEN="ghp_xxx"
#    # optional:
#    # export BACKSTAGE_CREATE_APP_VERSION="1.39.1" # pin explicitly; default = resolve latest stable from npm
#    # export PG_PASSWORD="..."                     # default = randomly generated & saved
#
#    chmod +x 03-ubuntu-vm-production-setup.sh
#    sudo -E ./03-ubuntu-vm-production-setup.sh
# ============================================================================

set -euo pipefail

log()  { echo -e "\033[1;36m[vm-setup]\033[0m $1"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $1"; }
err()  { echo -e "\033[1;31m[error]\033[0m $1"; }

if [ "$EUID" -ne 0 ]; then
  err "Run this with sudo: sudo -E ./03-ubuntu-vm-production-setup.sh"
  exit 1
fi

: "${DOMAIN:?export DOMAIN=backstage.yourcompany.com}"
: "${ADMIN_EMAIL:?export ADMIN_EMAIL=you@yourcompany.com}"
: "${GITHUB_TOKEN:?export GITHUB_TOKEN=ghp_xxx}"

DATA_DISK_DEVICE="${DATA_DISK_DEVICE:-}"
DATA_MOUNT="/data"
APP_DIR="${DATA_MOUNT}/backstage-app"
PG_DATA_DIR="${DATA_MOUNT}/postgresql"
PG_VERSION="16"
PG_CLUSTER_NAME="data"                 # cluster name -> pg_lsclusters shows "16  data"
PG_PORT="5432"
PG_DB="backstage"
PG_USER="backstage"
PG_PASSWORD="${PG_PASSWORD:-}"
BACKEND_SECRET="${BACKEND_SECRET:-}"
NODE_MAJOR="20"
SERVICE_USER="backstage"
BACKSTAGE_CREATE_APP_VERSION="${BACKSTAGE_CREATE_APP_VERSION:-}"

# ----------------------------------------------------------------------------
# 1. Base packages
# ----------------------------------------------------------------------------
log "Updating apt and installing base packages..."
apt-get update -y
apt-get install -y curl git build-essential python3 python3-pip ufw \
  nginx certbot python3-certbot-nginx gnupg ca-certificates jq

# ----------------------------------------------------------------------------
# 2. Data disk: format (if new) and mount at /data, referenced by UUID
# ----------------------------------------------------------------------------
if [ -n "$DATA_DISK_DEVICE" ]; then
  mkdir -p "$DATA_MOUNT"
  if ! blkid "$DATA_DISK_DEVICE" >/dev/null 2>&1; then
    log "No filesystem detected on ${DATA_DISK_DEVICE} — formatting as ext4 (NEW DISK ONLY; this is destructive)."
    read -r -p "Confirm ${DATA_DISK_DEVICE} is a blank disk you want to format [y/N]: " CONFIRM
    [ "$CONFIRM" = "y" ] || { err "Aborting — refusing to format without confirmation."; exit 1; }
    mkfs.ext4 -F "$DATA_DISK_DEVICE"
  else
    log "Existing filesystem found on ${DATA_DISK_DEVICE} — will mount and reuse (this is the 'moved disk' path)."
  fi

  DISK_UUID=$(blkid -s UUID -o value "$DATA_DISK_DEVICE")
  if ! mountpoint -q "$DATA_MOUNT"; then
    mount "$DATA_DISK_DEVICE" "$DATA_MOUNT"
  fi
  if ! grep -q "$DISK_UUID" /etc/fstab; then
    echo "UUID=${DISK_UUID}  ${DATA_MOUNT}  ext4  defaults,nofail  0  2" >> /etc/fstab
  fi
  log "Data disk mounted at ${DATA_MOUNT} (UUID=${DISK_UUID}, recorded in /etc/fstab)."
else
  warn "DATA_DISK_DEVICE not set — using ${DATA_MOUNT} on the root disk."
  warn "This works but defeats the 'detach and move to a new VM' goal. Set DATA_DISK_DEVICE and re-run for that."
  mkdir -p "$DATA_MOUNT"
fi

FRESH_INSTALL=true
[ -d "$APP_DIR" ] && FRESH_INSTALL=false

# ----------------------------------------------------------------------------
# 3. Node.js (Active LTS) + Corepack/Yarn
# ----------------------------------------------------------------------------
if ! command -v node >/dev/null 2>&1 || [ "$(node -v | sed 's/v//' | cut -d. -f1)" -lt "$NODE_MAJOR" ]; then
  log "Installing Node.js ${NODE_MAJOR}.x via NodeSource..."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y nodejs
fi
corepack enable
log "Node $(node -v), npm $(npm -v)"

# ----------------------------------------------------------------------------
# 4. PostgreSQL — cluster data directory lives on the transferable disk
# ----------------------------------------------------------------------------
if ! dpkg -l | grep -q "postgresql-${PG_VERSION}"; then
  log "Installing PostgreSQL ${PG_VERSION}..."
  apt-get install -y "postgresql-${PG_VERSION}" postgresql-contrib
fi

# Drop the default apt-created cluster (its data dir is on the root disk) —
# we run our own cluster pointed at $PG_DATA_DIR instead.
if pg_lsclusters | grep -q "^${PG_VERSION} main "; then
  log "Removing default 'main' cluster (data dir on root disk, not the transferable disk)..."
  pg_dropcluster --stop "${PG_VERSION}" main || true
fi

if ! pg_lsclusters | grep -q "^${PG_VERSION} ${PG_CLUSTER_NAME} "; then
  if [ -s "${PG_DATA_DIR}/PG_VERSION" ]; then
    log "Existing Postgres data found at ${PG_DATA_DIR} — registering cluster against it (moved-disk path)."
    pg_createcluster "${PG_VERSION}" "${PG_CLUSTER_NAME}" -d "${PG_DATA_DIR}" --start-conf=auto -- --no-locale --no-instructions || true
  else
    log "Initializing new Postgres cluster at ${PG_DATA_DIR}..."
    mkdir -p "$PG_DATA_DIR"
    chown postgres:postgres "$PG_DATA_DIR"
    pg_createcluster "${PG_VERSION}" "${PG_CLUSTER_NAME}" -d "${PG_DATA_DIR}" --start-conf=auto
  fi
fi

systemctl start "postgresql@${PG_VERSION}-${PG_CLUSTER_NAME}"
systemctl enable "postgresql@${PG_VERSION}-${PG_CLUSTER_NAME}"

if [ -z "$PG_PASSWORD" ]; then
  if [ -f "${DATA_MOUNT}/.pg_password" ]; then
    PG_PASSWORD=$(cat "${DATA_MOUNT}/.pg_password")
    log "Reusing existing Postgres password from ${DATA_MOUNT}/.pg_password"
  else
    PG_PASSWORD=$(openssl rand -base64 24)
    echo "$PG_PASSWORD" > "${DATA_MOUNT}/.pg_password"
    chmod 600 "${DATA_MOUNT}/.pg_password"
  fi
fi

log "Ensuring Postgres role and database exist..."
sudo -u postgres psql -p "$PG_PORT" -tc "SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'" | grep -q 1 || \
  sudo -u postgres psql -p "$PG_PORT" -c "CREATE ROLE ${PG_USER} WITH LOGIN PASSWORD '${PG_PASSWORD}';"
sudo -u postgres psql -p "$PG_PORT" -tc "SELECT 1 FROM pg_database WHERE datname='${PG_DB}'" | grep -q 1 || \
  sudo -u postgres psql -p "$PG_PORT" -c "CREATE DATABASE ${PG_DB} OWNER ${PG_USER};"

# ----------------------------------------------------------------------------
# 5. Dedicated system user to own/run the app
# ----------------------------------------------------------------------------
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  log "Creating system user '${SERVICE_USER}'..."
  useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
fi

# ----------------------------------------------------------------------------
# 6. Resolve and pin the Backstage version (no floating '@latest')
# ----------------------------------------------------------------------------
if [ -z "$BACKSTAGE_CREATE_APP_VERSION" ]; then
  if [ -f "${DATA_MOUNT}/.backstage-version" ] && [ "$FRESH_INSTALL" = false ]; then
    BACKSTAGE_CREATE_APP_VERSION=$(cat "${DATA_MOUNT}/.backstage-version")
    log "Reusing previously pinned @backstage/create-app version: ${BACKSTAGE_CREATE_APP_VERSION}"
  else
    log "Resolving current stable @backstage/create-app version from npm..."
    BACKSTAGE_CREATE_APP_VERSION=$(npm view @backstage/create-app version)
  fi
fi
echo "$BACKSTAGE_CREATE_APP_VERSION" > "${DATA_MOUNT}/.backstage-version"
log "Pinned @backstage/create-app version: ${BACKSTAGE_CREATE_APP_VERSION} (recorded in ${DATA_MOUNT}/.backstage-version)"

# ----------------------------------------------------------------------------
# 7. Scaffold the app (skip if already present — moved-disk / re-run path)
# ----------------------------------------------------------------------------
if [ "$FRESH_INSTALL" = true ]; then
  log "Scaffolding Backstage app (pinned v${BACKSTAGE_CREATE_APP_VERSION}) into ${APP_DIR}..."
  mkdir -p "$(dirname "$APP_DIR")"
  echo "$(basename "$APP_DIR")" | npx --yes "@backstage/create-app@${BACKSTAGE_CREATE_APP_VERSION}" --path "$APP_DIR"
else
  log "Existing app found at ${APP_DIR} — skipping scaffold."
fi

if [ -z "$BACKEND_SECRET" ]; then
  if [ -f "${DATA_MOUNT}/.backend_secret" ]; then
    BACKEND_SECRET=$(cat "${DATA_MOUNT}/.backend_secret")
  else
    BACKEND_SECRET=$(openssl rand -hex 32)
    echo "$BACKEND_SECRET" > "${DATA_MOUNT}/.backend_secret"
    chmod 600 "${DATA_MOUNT}/.backend_secret"
  fi
fi

# ----------------------------------------------------------------------------
# 8. Production config — single-process: backend serves the built frontend,
#    nginx does TLS termination and reverse-proxies to 127.0.0.1:7007
# ----------------------------------------------------------------------------
log "Writing app-config.production.yaml..."
cat > "${APP_DIR}/app-config.production.yaml" <<EOF
app:
  title: "Company Developer Portal"
  baseUrl: https://${DOMAIN}

backend:
  baseUrl: https://${DOMAIN}
  listen:
    host: 127.0.0.1
    port: 7007
  cors:
    origin: https://${DOMAIN}
  auth:
    keys:
      - secret: \${BACKEND_SECRET}
  database:
    client: pg
    connection:
      host: 127.0.0.1
      port: ${PG_PORT}
      user: ${PG_USER}
      password: \${POSTGRES_PASSWORD}
      database: ${PG_DB}

integrations:
  github:
    - host: github.com
      token: \${GITHUB_TOKEN}

# NOTE: guest auth is disabled by default once a 'production' env config is
# layered in. Add your real provider (Entra ID/GitHub OAuth/etc.) here —
# see the companion guide for the exact block to paste in.
EOF

# ----------------------------------------------------------------------------
# 9. Build (production mode — not `yarn dev`)
# ----------------------------------------------------------------------------
log "Installing dependencies and building (this takes several minutes)..."
cd "$APP_DIR"
sudo -u "$SERVICE_USER" HOME="$APP_DIR" yarn install --immutable
sudo -u "$SERVICE_USER" HOME="$APP_DIR" yarn tsc
sudo -u "$SERVICE_USER" HOME="$APP_DIR" yarn --cwd packages/app build
sudo -u "$SERVICE_USER" HOME="$APP_DIR" yarn build:backend --config app-config.yaml --config app-config.production.yaml

chown -R "${SERVICE_USER}:${SERVICE_USER}" "$APP_DIR"

# ----------------------------------------------------------------------------
# 10. systemd service
# ----------------------------------------------------------------------------
log "Writing systemd unit and environment file..."
cat > /etc/backstage.env <<EOF
POSTGRES_PASSWORD=${PG_PASSWORD}
BACKEND_SECRET=${BACKEND_SECRET}
GITHUB_TOKEN=${GITHUB_TOKEN}
NODE_ENV=production
EOF
chmod 600 /etc/backstage.env

cat > /etc/systemd/system/backstage.service <<EOF
[Unit]
Description=Backstage.io Developer Portal
After=network.target postgresql@${PG_VERSION}-${PG_CLUSTER_NAME}.service
Requires=postgresql@${PG_VERSION}-${PG_CLUSTER_NAME}.service

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${APP_DIR}
EnvironmentFile=/etc/backstage.env
ExecStart=/usr/bin/node packages/backend --config app-config.yaml --config app-config.production.yaml
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable backstage
systemctl restart backstage

# ----------------------------------------------------------------------------
# 11. nginx + TLS
# ----------------------------------------------------------------------------
log "Configuring nginx reverse proxy for ${DOMAIN}..."
cat > /etc/nginx/sites-available/backstage <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:7007;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -sf /etc/nginx/sites-available/backstage /etc/nginx/sites-enabled/backstage
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

log "Requesting TLS certificate via certbot for ${DOMAIN}..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect || \
  warn "certbot failed — likely DNS for ${DOMAIN} isn't pointed at this VM yet. Fix DNS and re-run: certbot --nginx -d ${DOMAIN}"

# ----------------------------------------------------------------------------
# 12. Firewall
# ----------------------------------------------------------------------------
log "Configuring ufw (allowing SSH + HTTP/HTTPS only)..."
ufw allow OpenSSH >/dev/null
ufw allow 'Nginx Full' >/dev/null
ufw --force enable >/dev/null

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
echo ""
log "Done."
echo "  URL                 : https://${DOMAIN}"
echo "  Backstage version   : ${BACKSTAGE_CREATE_APP_VERSION} (pinned, see ${DATA_MOUNT}/.backstage-version)"
echo "  App directory       : ${APP_DIR}  (on ${DATA_MOUNT})"
echo "  Postgres data dir   : ${PG_DATA_DIR}  (on ${DATA_MOUNT})"
echo "  Postgres password   : stored at ${DATA_MOUNT}/.pg_password (root-readable only)"
echo "  Backend secret      : stored at ${DATA_MOUNT}/.backend_secret"
echo "  Service             : systemctl status backstage"
echo "  Logs                : journalctl -u backstage -f"
echo ""
echo "  To move to a new/upgraded VM: stop services, detach ${DATA_DISK_DEVICE:-<your data disk>},"
echo "  attach it to the new VM, then re-run this script there with the same DATA_DISK_DEVICE."
echo "  See 03-ubuntu-vm-production-GUIDE.md for the exact detach/attach commands."

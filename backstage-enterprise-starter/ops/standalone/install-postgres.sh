#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${POSTGRES_DB:-backstage}"
DB_USER="${POSTGRES_USER:-backstage}"
DB_PASSWORD="${POSTGRES_PASSWORD:-}"

if [[ -z "$DB_PASSWORD" ]]; then
  echo "POSTGRES_PASSWORD is required."
  echo "Example:"
  echo "POSTGRES_PASSWORD='StrongPassword' ./ops/standalone/install-postgres.sh"
  exit 1
fi

sudo apt-get update
sudo apt-get install -y postgresql postgresql-contrib

sudo systemctl enable postgresql
sudo systemctl start postgresql

if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
  sudo -u postgres psql -c "ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';"
else
  sudo -u postgres psql -c "CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}';"
fi

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
fi

echo "PostgreSQL is ready:"
echo "  host=127.0.0.1"
echo "  port=5432"
echo "  database=${DB_NAME}"
echo "  user=${DB_USER}"

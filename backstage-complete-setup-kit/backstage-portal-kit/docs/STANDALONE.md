# Standalone Node.js Mode

This option runs Backstage directly as a Node.js process and keeps PostgreSQL separate.

## PostgreSQL

```bash
docker compose -f docker-compose.standalone-db.yml up -d
```

## Build

```bash
yarn install --immutable
yarn tsc
yarn build:backend
```

## systemd

Create `/etc/systemd/system/backstage.service`:

```ini
[Unit]
Description=Backstage Developer Portal
After=network.target

[Service]
Type=simple
User=backstage
Group=backstage
WorkingDirectory=/opt/backstage
Environment=NODE_ENV=production
EnvironmentFile=/etc/backstage/backstage.env
ExecStart=/usr/bin/node /opt/backstage/packages/backend \
  --config /opt/backstage/app-config.yaml \
  --config /opt/backstage/app-config.production.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Create:

```bash
sudo mkdir -p /etc/backstage
sudo chmod 750 /etc/backstage
sudo nano /etc/backstage/backstage.env
sudo chmod 640 /etc/backstage/backstage.env
```

Then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now backstage
sudo systemctl status backstage
journalctl -u backstage -f
```

Backstage should listen only on localhost if Nginx is the reverse proxy.

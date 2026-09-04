# Docker Deployment

## Preferred mode

Use Docker Compose:

```text
Nginx
  |
  +--> Backstage container
          |
          +--> PostgreSQL container
```

Build:

```bash
yarn install --immutable
yarn tsc
yarn build:backend

docker build \
  -f packages/backend/Dockerfile \
  -t backstage:latest \
  .
```

The generated `packages/backend/Dockerfile` from create-app is preferred because it matches the generated application.

Start:

```bash
docker compose up -d
```

Logs:

```bash
docker compose logs -f backstage
```

Status:

```bash
docker compose ps
```

Restart:

```bash
docker compose restart backstage
```

## Standalone mode

Backstage can run directly under Node.js:

```bash
yarn install --immutable
yarn tsc
yarn build:backend
NODE_ENV=production \
POSTGRES_HOST=127.0.0.1 \
POSTGRES_PORT=5432 \
POSTGRES_USER=backstage \
POSTGRES_PASSWORD='...' \
POSTGRES_DB=backstage \
GITHUB_TOKEN='...' \
yarn start-backend --config app-config.yaml --config app-config.production.yaml
```

Use systemd to keep it running. See `docs/STANDALONE.md`.

## TechDocs caveat

The default TechDocs generator can use Docker. If Backstage itself is in Docker, this can become Docker-in-Docker. For the Docker deployment, either:

- use local MkDocs inside the Backstage image, or
- move TechDocs generation to CI and publish to cloud storage.

For production, the second approach is preferred.

# Local Mac Setup

## 1. Prerequisites

Install Homebrew, Git, Node.js 22 LTS, Yarn/Corepack and Docker Desktop.

```bash
brew install node@22 git
brew install yarn
```

Verify:

```bash
node --version
yarn --version
docker --version
docker compose version
```

## 2. Create Backstage

Use the current stable release you have validated. This kit was prepared against the Backstage 1.54.6 baseline.

```bash
npx @backstage/create-app@1.54.6
```

Choose:

```text
backstage-portal
```

Then:

```bash
cd backstage-portal
yarn install
```

## 3. Copy configuration

Copy the configuration/catalog/scripts/docs from this kit into the generated application. Do not overwrite generated Backstage source files blindly.

## 4. Start PostgreSQL

```bash
cp .env.example .env
chmod 600 .env
```

Edit `.env` and set a strong local password and GitHub token.

```bash
docker compose -f docker-compose.standalone-db.yml up -d
```

For the local app, set:

```text
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
```

## 5. Start Backstage

```bash
yarn start
```

Open:

```text
http://localhost:3000
```

## 6. Validate

```bash
curl http://localhost:7007
```

Check:

```bash
yarn tsc
yarn lint
yarn test
```

## No authentication

This setup intentionally leaves Backstage authentication unconfigured. The default guest experience is for development only; do not expose it to an untrusted network.

## Local change workflow

1. Edit catalog YAML.
2. Run Backstage.
3. Register/reload the catalog location if required.
4. Verify Component/API relationships.
5. Test Swagger/OpenAPI rendering.
6. Commit the change.
7. Open a GitHub PR.
8. CI validates it.
9. Merge to the deployment branch.

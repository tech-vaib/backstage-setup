# Backstage.io — Local Demo Setup Guide (macOS)

This guide accompanies `01-local-mac-setup.sh`. It stands up a working
Backstage instance on your Mac so you can demo the Software Catalog,
TechDocs, and GitHub integration to your team before deciding on the
Azure/AKS rollout.

## What you'll have at the end

- Backstage running locally: frontend `http://localhost:3000`, backend `http://localhost:7007`
- A Postgres-backed catalog (via Docker) — closer to production than SQLite
- GitHub integration wired up (repo discovery, TechDocs source, auth)
- One sample `Component` registered in the catalog

## 1. Prerequisites

| Tool | Why | Install |
|---|---|---|
| Homebrew | package manager | script installs if missing |
| Node.js 20+ (Active LTS) | Backstage runtime | script installs if missing |
| Yarn | Backstage's package manager | script installs if missing |
| Git | source control | script installs if missing |
| Docker Desktop | local Postgres container | **install manually**: https://www.docker.com/products/docker-desktop/ |
| GitHub Personal Access Token | catalog discovery, TechDocs, auth | create at https://github.com/settings/tokens (scopes: `repo`, `read:org`, `read:user`) |

> Install Docker Desktop *before* running the script if you want the
> Postgres-backed setup (recommended). Without Docker the script falls
> back to SQLite, which works for a five-minute demo but isn't
> representative of how you'll run this in Azure.

## 2. Run the script

```bash
chmod +x 01-local-mac-setup.sh
./01-local-mac-setup.sh
```

You'll be prompted once for your GitHub token (or export `GITHUB_TOKEN`
beforehand to skip the prompt). The script is idempotent — re-running it
skips steps already completed (existing app folder, existing Postgres
container, etc.).

Total first-run time: ~5–10 minutes, mostly `yarn install`.

## 3. What the script actually does

1. Installs/verifies Node, Yarn, Git, Python3 via Homebrew
2. Scaffolds a new app with `npx @backstage/create-app@latest`, piping in
   the folder name so it's non-interactive
3. Starts a `postgres:16` Docker container as the catalog database
4. Writes `app-config.local.yaml` (git-ignored by default — safe place
   for the GitHub token and DB connection) with:
   - `backend.database` pointed at the local Postgres container
   - `integrations.github` with your token
5. Drops in a sample `catalog-info.yaml` so the catalog isn't empty
6. Runs `yarn install` then `yarn start`

## 4. After it's running

- Open `http://localhost:3000` → you should see the Backstage home page
  with one component, `backstage-demo`, in the catalog.
- **Register a real repo**: in the UI, click *Create → Register Existing
  Component*, paste the URL of a `catalog-info.yaml` in one of your GitHub
  repos (or add one — template below).
- **Try TechDocs**: add a `docs/` folder with an `index.md` and an
  `mkdocs.yml` to a repo, add the `backstage.io/techdocs-ref` annotation,
  and it'll render inside Backstage.

Minimal `catalog-info.yaml` to drop into any repo you want to demo with:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: my-service
  description: One-line description of what this does
  annotations:
    github.com/project-slug: your-org/your-repo
    backstage.io/techdocs-ref: dir:.
spec:
  type: service
  lifecycle: production
  owner: team-your-team
```

## 5. Stopping / resetting

```bash
# Stop the app: Ctrl+C in the terminal running yarn start

# Stop Postgres (data persists in the container)
docker stop backstage-postgres

# Full reset (wipe catalog data)
docker rm -f backstage-postgres
rm -rf backstage-demo
```

## 6. Known limitations of this local setup (be upfront with the team)

- **Auth** is left at GitHub OAuth "development" mode — fine for demo,
  needs real OAuth app registration for anything shared.
- **No Kubernetes plugin, no APIM/App Gateway integration, no Confluence
  plugin** yet — this is intentionally the minimal "does the core
  product do what we want" demo. Those come in the Azure/AKS phase.
- **Cosmos DB for MongoDB is not used here** — Backstage's catalog
  database only supports PostgreSQL (or SQLite for local dev). See the
  Azure guide for how this affects your architecture.

## 7. Suggested next steps for the team

1. Walk through this demo together (30 min)
2. Agree on: which plugins matter (Kubernetes, TechDocs, Cost, Confluence
   reader), which auth provider (Entra ID likely, given Azure), which
   teams/services to onboard first
3. Move to the Azure/AKS setup (`02-azure-aks-setup.sh` +
   `02-azure-aks-setup-GUIDE.md`) to stand up a shared, persistent instance

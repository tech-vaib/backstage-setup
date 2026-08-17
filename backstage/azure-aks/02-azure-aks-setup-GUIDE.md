# Backstage.io on Azure/AKS — Setup, Integration & Maintenance Guide

Companion to `02-azure-aks-setup.sh`, `03-k8s-manifests.yaml`, and
`04-app-config.production.yaml`. This is the "take it to prod" phase after
the local Mac demo has team buy-in.

## 0. Architecture at a glance

```
GitHub (source of catalog-info.yaml, TechDocs, code)
     │
     ▼
AKS namespace "backstage"
  ├─ Deployment (2 replicas, Backstage backend + frontend bundle)
  ├─ Service (ClusterIP)
  └─ Ingress ──► Application Gateway (AGIC) ──► APIM (optional front door)
     │
     ▼
Azure Database for PostgreSQL Flexible Server  (Backstage catalog DB)

Confluence  ──(community plugin, read-only)──► Backstage search/docs
Cosmos DB (Mongo API) ──(custom entity-provider plugin, read-only)──► Catalog
```

**Key architectural decision to align on with your team up front:**
Backstage's catalog store only supports PostgreSQL/SQLite — not MongoDB.
Your existing Cosmos Mongo DB is *not* replaced by anything here; it
continues to serve its current apps. Backstage gets its own small,
dedicated Postgres instance. If Cosmos-held data (e.g., an internal
service registry) should appear in the Backstage catalog, that's done via
a custom **entity provider plugin** that reads Cosmos and emits catalog
entities on a schedule — not by pointing Backstage's core DB at Cosmos.

## 1. Prerequisites

- `az` CLI logged in with Contributor on the target subscription/resource groups
- `kubectl` and `docker` installed locally (or run this from a build agent)
- An existing AKS cluster you can `az aks get-credentials` into
- A GitHub PAT or, better, a GitHub App for org-wide catalog discovery
- A Microsoft Entra ID app registration for SSO (redirect URI:
  `https://<your-backstage-host>/api/auth/microsoft/handler/frame`)
- Confluence API token (Atlassian account settings) if wiring up Confluence
- Decide your ingress hostname (e.g. `backstage.internal.yourcompany.com`)
  and who issues the TLS cert (cert-manager + Let's Encrypt, or an
  internal CA/App Gateway-managed cert)

## 2. Required environment variables before running the script

```bash
export AZ_SUBSCRIPTION_ID="..."
export RESOURCE_GROUP="rg-backstage"
export LOCATION="eastus"
export ACR_NAME="acrbackstageshared"       # globally unique
export AKS_CLUSTER="my-existing-aks"
export AKS_RESOURCE_GROUP="rg-aks"
export PG_SERVER_NAME="psql-backstage"     # globally unique
export PG_ADMIN_USER="backstageadmin"
export GITHUB_TOKEN="ghp_xxx"
export AAD_CLIENT_ID="..."
export AAD_CLIENT_SECRET="..."
export AAD_TENANT_ID="..."
```

## 3. Run it

From the root of your Backstage app repo (the folder with `packages/backend`):

```bash
chmod +x 02-azure-aks-setup.sh
./02-azure-aks-setup.sh
```

This single script:
1. Creates the resource group, ACR (if missing), and attaches ACR to your AKS cluster
2. Provisions **Azure Database for PostgreSQL Flexible Server** for the catalog DB
3. Writes a standard multi-stage Backstage `Dockerfile` if you don't already have one
4. Builds and pushes the backend image to ACR
5. Connects `kubectl` to your AKS cluster and creates the `backstage` namespace
6. Creates a `backstage-secrets` K8s Secret from your env vars
7. Applies `03-k8s-manifests.yaml` (Deployment, Service, Ingress) with the freshly built image
8. Waits for rollout and prints a summary

It's safe to re-run — resources are created idempotently, and re-running
after a code change simply builds a new image tag and rolls it out.

## 4. Application Gateway + APIM front door

The script's Ingress is annotated for **AGIC** (`azure/application-gateway`).
Two things aren't scripted because they're org-specific:

**a) Enable AGIC on the AKS cluster** (one-time, if not already enabled):
```bash
az aks enable-addons -g "$AKS_RESOURCE_GROUP" -n "$AKS_CLUSTER" \
  --addons ingress-appgw \
  --appgw-id /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/applicationGateways/<appgw-name>
```

**b) Front the App Gateway with APIM** — treat Backstage as one more
backend behind APIM, same pattern as your other AKS-hosted apps:
```bash
az apim api create \
  --resource-group <apim-rg> \
  --service-name <apim-name> \
  --api-id backstage \
  --path backstage \
  --display-name "Developer Portal" \
  --service-url "https://<app-gateway-public-ip-or-fqdn>"
```
Then apply whatever auth/rate-limit policies your other internal tools use.
If Backstage should be reachable directly (not just via APIM), keep the
Ingress hostname on an internal DNS zone and skip the APIM hop for browser
traffic — APIM is typically for API-to-API calls, browser SSO traffic to
the Backstage UI usually goes straight through App Gateway.

## 5. Confluence integration

Backstage has no first-party Confluence plugin. Add a community one:
```bash
yarn --cwd packages/backend add @k-phoen/backstage-plugin-confluence
```
Configure it via the `confluence:` block already included in
`04-app-config.production.yaml`. This makes Confluence pages searchable
from Backstage's global search — it doesn't migrate content, just indexes
and links to it. Good starting point: point it at your Engineering and
Platform spaces first, expand space list once the team's happy with results.

## 6. Kubernetes visibility plugin

The `kubernetes:` block in `04-app-config.production.yaml` lets each
component's Backstage page show live pod/deployment status from AKS.
Grant the pod's identity (workload identity or the AKS-assigned managed
identity) a read-only ClusterRole:
```bash
kubectl create clusterrolebinding backstage-viewer \
  --clusterrole=view \
  --serviceaccount=backstage:default
```
Use a scoped Role instead of `view` cluster-wide if you want to restrict
this to specific namespaces per team.

## 7. APIM-managed APIs inside the Backstage API catalog

Optional but high-value: surface your APIM APIs as `kind: API` entities so
engineers discover them the same place they discover services. Starter
approach (not fully scripted — naming/ownership mapping is org-specific):
```bash
az apim api list --resource-group <rg> --service-name <apim-name> -o json > apim-apis.json
```
Write a small script/cron job that transforms each entry into:
```yaml
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: <slug-from-apim>
  description: <apim description>
spec:
  type: openapi
  lifecycle: production
  owner: <team>
  definition:
    $text: <link to APIM's exported OpenAPI spec>
```
and push it via the catalog import API (`POST /api/catalog/locations`) or
commit it to a `catalog-apim/` repo that's registered as a github-discovery
location.

## 8. GitHub-wide catalog discovery

`04-app-config.production.yaml` uses `github-discovery` to auto-pick-up
every `catalog-info.yaml` across the org — no manual registration per repo.
Roll this out by asking each team to drop a `catalog-info.yaml` at their
repo root (template in the local setup guide). Track adoption with a
simple checklist or a dashboard query against the catalog API.

## 9. Ongoing maintenance

| Task | How |
|---|---|
| Deploy new Backstage version / plugin changes | Re-run `02-azure-aks-setup.sh` from the repo root (it rebuilds & re-applies) |
| Rotate GitHub token / AAD secret | Update the source env var, re-run the secret-creation step (step 6 in the script), then `kubectl rollout restart deployment/backstage -n backstage` |
| Scale out | `kubectl -n backstage scale deployment/backstage --replicas=<n>`, or add an HPA |
| DB backups | Azure Postgres Flexible Server has automated backups by default (7–35 day retention, configurable) — verify retention matches your policy |
| TechDocs storage | Current config uses `local` storage, which does **not** survive pod restarts or work across replicas correctly. Before wider rollout, provision an Azure Storage Account and switch `techdocs.publisher.type` to `azureBlobStorage` |
| Monitoring | Ship logs to your existing Azure Monitor / Log Analytics workspace via the AKS diagnostic settings you likely already have; add a liveness-based alert on the Deployment |
| Onboarding new teams | Share the `catalog-info.yaml` template + a short "how to register your service" doc (5 min read) |

## 10. Known gaps to flag to the team now

- **Cosmos Mongo is not Backstage's DB** — see architecture note above.
- **TechDocs on local storage** is a placeholder — move to Azure Blob before
  this is used by more than a couple of pilot teams.
- **APIM wiring is templated, not templated-and-tested** — your APIM
  policies (auth, rate limiting, product grouping) are specific enough that
  this needs a short pairing session with whoever owns APIM today.
- **Network**: the script's Postgres server is created with broad public
  access for speed. Before anything beyond a pilot, switch to VNet
  integration so Postgres is only reachable from the AKS subnet.

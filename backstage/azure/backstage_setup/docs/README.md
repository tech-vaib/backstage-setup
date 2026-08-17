# Backstage POC + Azure/AKS deployment kit

This kit contains two independent "one-go" bootstrap scripts:

- `local/setup-backstage-local.sh` — macOS local demo with Docker PostgreSQL, sample catalog and TechDocs.
- `azure/setup-backstage-azure-aks.sh` — Azure/AKS baseline that builds Backstage, pushes it to ACR, creates Azure PostgreSQL + Blob Storage, configures AKS Workload Identity, and deploys a ClusterIP + Ingress.

## Why PostgreSQL when the application already uses Cosmos DB for MongoDB?

Backstage's own persistence layer is PostgreSQL for production. Your existing Cosmos DB for MongoDB should remain the database for your business applications; it is not a drop-in replacement for Backstage's platform database. Backstage supports Azure PostgreSQL with Entra authentication as well, so a later hardening step can remove the database password entirely.

## 1. Local demo

### Prerequisites

- macOS
- Homebrew
- Docker Desktop running
- At least ~6 GB RAM and ~20 GB free disk is a sensible starting point for Backstage
- Internet access

Run:

```bash
cd backstage-setup/local
./setup-backstage-local.sh
```

The script:

1. Installs/activates Node tooling.
2. Creates a new Backstage app using `@backstage/create-app@latest`.
3. Installs the PostgreSQL driver.
4. Starts PostgreSQL 18 in Docker.
5. Configures Backstage to use PostgreSQL.
6. Creates a sample Component, API, System and Group.
7. Creates sample TechDocs.
8. Runs a strict configuration check.
9. Creates `run-backstage.sh` and `stop-backstage.sh`.

Then:

```bash
cd backstage-demo
./run-backstage.sh
```

Open:

- http://localhost:3000 — UI
- http://localhost:7007 — backend

The local script intentionally uses Guest auth because the purpose is a fast demo. Do not expose this instance outside the laptop.

## 2. Azure / AKS

### What the Azure script creates

Within the supplied resource group:

- Azure Container Registry
- Azure Database for PostgreSQL Flexible Server (unless `EXISTING_POSTGRES_HOST` is supplied)
- Azure Storage Account + TechDocs container
- User-assigned managed identity
- AKS OIDC federation for the Backstage service account
- Storage Blob Data Owner role for the identity
- Backstage namespace
- Backstage Deployment with 2 replicas
- ClusterIP Service
- Ingress for your existing Application Gateway/Ingress setup
- Backstage Docker image pushed to ACR

### What it deliberately does not guess

Enterprise networking and security are organization-specific. The script therefore does not blindly modify your Application Gateway, APIM API definitions, DNS, TLS certificates, private DNS zones, firewall policy, WAF policy, or GitHub organization permissions.

Those are documented in `AZURE-TEAM-RUNBOOK.md`.

### Required variables

Example:

```bash
export AZ_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
export AZ_RESOURCE_GROUP="rg-platform-dev"
export AKS_CLUSTER_NAME="aks-platform-dev"
export AZ_LOCATION="westus2"
export BACKSTAGE_HOSTNAME="backstage.example.com"
export GITHUB_ORG="my-company"
export INGRESS_CLASS="azure/application-gateway"

# Optional: let Azure CLI create/update the Entra App Registration.
export CONFIGURE_ENTRA="true"
export ENTRA_APP_NAME="Backstage"
```

Optional:

```bash
export APP_NAME="backstage"
export NAMESPACE="backstage"
export ACR_NAME="mycompanybackstageacr"
export STORAGE_NAME="mycompanybackstagetechdocs"
export TECHDOCS_CONTAINER="techdocs"
export EXISTING_POSTGRES_HOST="myserver.postgres.database.azure.com"
export PG_ADMIN="backstageadmin"
export PG_PASSWORD="a-strong-password"
export GITHUB_TOKEN="..."
export ENTRA_CLIENT_ID="..."
export ENTRA_CLIENT_SECRET="..."
```

Run:

```bash
./setup-backstage-azure-aks.sh
```

### Important

If you use an existing PostgreSQL server, you must supply a valid `PG_PASSWORD` for the database user used by Backstage and ensure network access from AKS.

The script's newly created PostgreSQL server uses public access as a POC convenience. For production, replace that with private networking/private DNS and preferably Microsoft Entra authentication. Do not consider the public-access configuration the final enterprise architecture.

## 3. Recommended enterprise architecture

```text
Developer
   |
   | HTTPS
   v
Azure Application Gateway / WAF
   |
   v
Azure API Management (if APIM is your enterprise front door)
   |
   v
AKS Ingress
   |
   v
Backstage Service (ClusterIP)
   |
   +--> Azure PostgreSQL Flexible Server
   |
   +--> Azure Blob Storage (TechDocs)
   |
   +--> GitHub / GitHub App
   |
   +--> Microsoft Graph / Entra ID
   |
   +--> AKS API (Kubernetes plugin)
   |
   +--> Azure APIs / APIM / Application Gateway links
   |
   +--> Confluence search/plugin
```

You can put APIM before Application Gateway or use Application Gateway as the primary web edge depending on your organization's standard. Avoid creating a second ingress architecture just for Backstage.

## 4. Mapping your current platform into Backstage

| Existing platform | Backstage representation |
|---|---|
| GitHub repository | Component + `github.com/project-slug` |
| AKS workload | Component + Kubernetes plugin |
| Azure APIM API | API entity + APIM link/plugin |
| Application Gateway | Resource/link + optional Azure plugin |
| Cosmos DB MongoDB | Resource entity + database dashboard/link |
| Confluence pages | Search plugin and/or Confluence-to-Markdown workflow |
| CI/CD GitHub Actions | Component CI/CD links or GitHub Actions plugin |
| Azure Monitor / App Insights | Component links or monitoring plugin |
| Terraform | Resource/IaC links; later scaffolder templates |
| Team/owners | Group/User entities, preferably sourced from Entra/Graph |
| Runbooks | TechDocs |
| OpenAPI | API entities |

## 5. Documentation strategy

Use a two-tier model:

### Tier A — service-owned documentation

Keep engineering documentation next to the service code:

```text
service-repo/
  catalog-info.yaml
  mkdocs.yml
  docs/
    index.md
    architecture.md
    operations.md
    troubleshooting.md
    api.md
```

Backstage TechDocs then becomes the standard entry point.

### Tier B — enterprise/long-form Confluence

Keep organization-wide material in Confluence:

- platform standards
- architecture governance
- security standards
- enterprise policies
- cross-team decision records

Use Backstage Search/Confluence integration for discovery, and migrate service-specific operational material to TechDocs over time.

Backstage also provides a Confluence-to-Markdown scaffolder backend module that can be used to progressively convert selected Confluence pages into TechDocs.

## 6. GitHub strategy

For the first POC, a GitHub PAT is acceptable.

For production, prefer a GitHub App:

- Contents: Read
- Metadata: Read
- Commit statuses: Read
- Members: Read if importing organization users/groups
- Additional write permissions only when using Scaffolder to create repositories/PRs

Keep GitHub credentials out of `app-config*.yaml`.

## 7. Entra ID

The Azure script prepares the Backstage configuration for Microsoft authentication, but the Entra App Registration is intentionally an explicit enterprise step.

Create an App Registration with:

Redirect URI:

```text
https://backstage.example.com/api/auth/microsoft/handler/frame
```

Required delegated Microsoft Graph permissions for the normal Microsoft provider include:

- email
- offline_access
- openid
- profile
- User.Read

Grant admin consent if required by your tenant.

Then populate the Kubernetes secret:

```bash
kubectl -n backstage create secret generic backstage-runtime \
  --from-literal=AZURE_CLIENT_ID="..." \
  --from-literal=AZURE_CLIENT_SECRET="..." \
  --from-literal=AZURE_TENANT_ID="..." \
  --dry-run=client -o yaml | kubectl apply -f -
```

Restart the deployment after changing the secret:

```bash
kubectl -n backstage rollout restart deployment/backstage
```

For sign-in to resolve to a Backstage User, import User entities and ensure their `spec.profile.email` matches the authenticated Microsoft email when using the configured resolver.

## 8. TechDocs production flow

Recommended:

```text
GitHub PR
   |
   v
GitHub Actions
   |
   +-- validate catalog-info.yaml
   +-- build MkDocs/TechDocs
   +-- publish static site
             |
             v
      Azure Blob Storage
             |
             v
        Backstage TechDocs
```

Backstage recommends external CI/CD generation and an external publisher for production.

The Azure deployment is configured with:

```yaml
techdocs:
  builder: external
  publisher:
    type: azureBlobStorage
```

## 9. APIM / Application Gateway

The script creates the Kubernetes Ingress, but your team should connect it to the existing enterprise edge.

Recommended sequence:

1. Create DNS record for `backstage.example.com`.
2. Add/verify TLS certificate.
3. Configure Application Gateway listener and routing to the AKS ingress.
4. If APIM is the enterprise front door, expose a dedicated Backstage API/web route and forward to the Application Gateway/backend according to your APIM topology.
5. Do not apply generic API policies such as strict JSON-only content types to all Backstage paths; Backstage is a web application with OAuth callbacks, static assets, catalog APIs and TechDocs.
6. Validate WebSocket/streaming requirements if any selected plugin requires them.
7. Apply WAF exclusions only when required and documented.

## 10. Kubernetes plugin

Once Backstage is running, install/configure the Kubernetes plugin and give Backstage the minimum read permissions required.

For AKS, prefer Microsoft Entra authentication and Workload Identity rather than a long-lived Kubernetes bearer token.

Start with read-only access. Add write capabilities only after a separate security review.

## 11. Cosmos DB for MongoDB

Do not try to make Cosmos DB the Backstage database.

Instead, model each application Cosmos DB instance/container as a Backstage `Resource` and link it to:

- Azure Portal
- Azure Monitor
- application component
- runbook
- data classification documentation

This provides discoverability without coupling Backstage's persistence layer to your application database.

## 12. Suggested rollout

### Phase 1 — POC

- Catalog
- GitHub
- TechDocs
- Guest auth locally
- Entra auth in AKS
- One AKS demo service
- One API
- One Confluence/search integration

### Phase 2 — platform integration

- Entra users/groups
- GitHub organization discovery
- Kubernetes plugin
- APIM/API catalog
- Azure resources
- Azure Monitor/Application Insights
- Confluence search
- CI/CD status

### Phase 3 — Golden Paths

Create templates for:

- AKS microservice
- API service
- worker/background service
- Cosmos DB-backed service
- APIM API
- standard TechDocs
- GitHub Actions CI/CD
- Terraform/IaC

### Phase 4 — Governance

Add scorecards/quality gates for:

- owner
- lifecycle
- documentation
- security scan
- test coverage
- SLO
- on-call
- production readiness
- API specification
- dependency/version policy

## 13. Backstage operational model

Treat the Backstage repository as a real platform product:

- source controlled in GitHub
- PR review required
- CI runs lint/test/config validation
- container built by GitHub Actions
- image pushed to ACR
- deployment via GitOps or your standard CD system
- PostgreSQL backed up and monitored
- Blob Storage protected with RBAC
- secrets stored in Key Vault/secret manager
- Azure Monitor/OpenTelemetry enabled
- dependency upgrades scheduled
- plugin inventory reviewed
- plugin upgrades tested before production

## 14. Useful official references

- Backstage create app: https://backstage.io/docs/getting-started/
- Kubernetes deployment: https://backstage.io/docs/deployment/k8s/
- Production deployment: https://backstage.io/docs/golden-path/deployment/
- Authentication: https://backstage.io/docs/auth/
- Microsoft authentication: https://backstage.io/docs/auth/microsoft/provider/
- GitHub integration: https://backstage.io/docs/integrations/github/
- GitHub Apps: https://backstage.io/docs/integrations/github/github-apps/
- TechDocs: https://backstage.io/docs/features/techdocs/
- Azure Blob TechDocs: https://backstage.io/docs/features/techdocs/using-cloud-storage/
- Plugins: https://backstage.io/plugins/

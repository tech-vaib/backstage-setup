# Azure / AKS Team Runbook

## 1. Ownership

Suggested ownership:

- Backstage application/repository: Platform Engineering
- Azure resources: Cloud/Infrastructure
- Entra App Registration: Identity team
- GitHub App: Developer Platform / GitHub administrators
- Confluence integration: Developer Experience
- APIM/Application Gateway: API/Network platform team
- PostgreSQL: Cloud DBA/platform
- TechDocs: service-owning teams
- Catalog metadata: service owners

## 2. Day-1 verification

```bash
kubectl -n backstage get deploy,svc,ingress,sa
kubectl -n backstage get pods -o wide
kubectl -n backstage rollout status deployment/backstage
kubectl -n backstage logs deployment/backstage --tail=200
```

Verify:

- Backstage pods are Ready.
- Service is ClusterIP.
- Ingress has the expected address/hostname.
- TLS terminates correctly.
- `/api/catalog/entities` returns successfully through the enterprise URL.
- Microsoft OAuth callback reaches `/api/auth/microsoft/handler/frame`.
- GitHub integration can read an example repository.
- TechDocs renders a sample site.
- PostgreSQL connections are healthy.

## 3. Application Gateway

The exact annotations depend on whether you use:

- AGIC
- Application Gateway for Containers
- another ingress controller

Set `INGRESS_CLASS` to your actual controller.

Examples:

```bash
export INGRESS_CLASS="azure/application-gateway"
```

or the value used by your cluster.

Do not copy an ingress class from another environment without checking:

```bash
kubectl get ingressclass
```

## 4. APIM

Create a dedicated API/web route for Backstage rather than assuming it behaves like a normal REST API.

At minimum validate:

- GET/HEAD static assets
- `/api/*`
- OAuth callback
- TechDocs
- catalog endpoints
- long-running backend calls
- correct `X-Forwarded-*` headers
- TLS termination and original scheme
- CORS
- cookie handling

Keep APIM policies minimal initially. Add rate limits, JWT validation and other policies only after understanding which paths are user-browser OAuth flows versus server-to-server APIs.

## 5. Entra ID

App Registration:

```text
Name: Backstage
Platform: Web

Redirect:
https://BACKSTAGE_HOSTNAME/api/auth/microsoft/handler/frame
```

Delegated permissions normally include:

- email
- offline_access
- openid
- profile
- User.Read

Confirm outbound connectivity from AKS to:

```text
login.microsoftonline.com
graph.microsoft.com
```

Backstage's Microsoft provider needs these endpoints for authentication/profile retrieval.

## 6. User and Group catalog

For an enterprise implementation, avoid manually maintaining hundreds of users.

Use Microsoft Graph organization ingestion to synchronize:

- Users
- Groups/Teams

Then use the authenticated user's email or Microsoft user ID to resolve the Backstage identity.

Define an organizational convention such as:

```text
platform-team
orders-team
payments-team
data-team
```

## 7. GitHub

Preferred production model:

```text
Backstage
   |
   v
GitHub App
   |
   +-- repository metadata
   +-- source/catalog files
   +-- pull requests
   +-- workflows/status
```

Avoid broad PAT scopes.

For read-only catalog discovery, start with the minimum read permissions.

## 8. TechDocs

Every service should eventually have:

```text
catalog-info.yaml
mkdocs.yml
docs/index.md
docs/architecture.md
docs/operations.md
docs/troubleshooting.md
```

Example annotation:

```yaml
metadata:
  annotations:
    backstage.io/techdocs-ref: dir:.
```

Recommended production builder:

```yaml
techdocs:
  builder: external
```

The CI workflow generates and publishes the static site to Azure Blob Storage.

## 9. Confluence

Use Confluence for enterprise/cross-service documentation.

Use TechDocs for service-owned engineering documentation.

For migration, select high-value pages first:

1. service runbook
2. architecture
3. deployment
4. troubleshooting
5. API documentation

Backstage has a community Confluence search plugin and an official scaffolder backend module for Confluence-to-Markdown conversion. Evaluate plugin maintenance/security before adopting community plugins.

## 10. Azure resources as Backstage Resources

Example:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Resource
metadata:
  name: orders-cosmosdb
  description: Orders application Cosmos DB for MongoDB
  links:
    - url: https://portal.azure.com/
      title: Azure Portal
spec:
  type: database
  owner: orders-team
  dependencyOf:
    - component:default/orders-api
```

For APIM:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Resource
metadata:
  name: orders-apim
spec:
  type: api-gateway
  owner: platform-team
```

For Application Gateway:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Resource
metadata:
  name: platform-app-gateway
spec:
  type: gateway
  owner: platform-team
```

## 11. Security baseline

Before production:

- Use Entra ID; remove Guest auth.
- Use HTTPS only.
- Put PostgreSQL on private networking.
- Prefer Entra authentication for PostgreSQL where practical.
- Use Workload Identity for Azure APIs.
- Store remaining secrets in Key Vault.
- Use a GitHub App.
- Enable ACR security scanning according to your organization's standard.
- Restrict Backstage Kubernetes permissions to read-only initially.
- Apply least privilege to Confluence/Graph/GitHub.
- Enable Azure Monitor/OpenTelemetry.
- Define log retention.
- Define database backup/restore and DR.
- Review all third-party plugins.

## 12. Upgrade process

Pin and test Backstage upgrades.

Recommended flow:

```text
Backstage upgrade PR
       |
       +--> yarn install
       +--> config check
       +--> lint/test
       +--> Docker build
       +--> security scan
       +--> deploy to non-prod
       +--> smoke tests
       +--> production
```

Do not update arbitrary plugin versions independently if they create incompatible Backstage package versions.

## 13. Smoke test checklist

- [ ] Login with Entra
- [ ] User resolves to correct Backstage identity
- [ ] Catalog loads
- [ ] GitHub repository opens
- [ ] TechDocs opens
- [ ] API entity opens
- [ ] Kubernetes workload shows expected state
- [ ] APIM link opens
- [ ] Application Gateway link opens
- [ ] Cosmos DB link opens
- [ ] Search finds Confluence content
- [ ] Backend logs contain no authentication/configuration errors
- [ ] PostgreSQL is reachable
- [ ] Blob Storage TechDocs reads correctly
- [ ] Pod restart recovers cleanly
- [ ] One replica can be unavailable without portal outage

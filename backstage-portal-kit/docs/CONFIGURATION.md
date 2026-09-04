# Configuration and Change Management

## Rule

Configuration that describes services belongs in GitHub and is changed through pull requests.

Secrets do not belong in GitHub.

## What belongs in Git

```text
catalog/
app-config.yaml
app-config.production.yaml
Dockerfile
docker-compose.yml
scripts/
.github/workflows/
docs/
```

## What does not belong in Git

```text
.env
GitHub PAT
GitHub App private key
Confluence token
PostgreSQL password
TLS private key
```

## Adding a new service

Create:

```text
catalog/components/new-service.yaml
```

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: new-service
  description: New service
  annotations:
    github.com/project-slug: myorg/new-service
  links:
    - url: https://company.atlassian.net/wiki/spaces/PLAT/pages/123
      title: Confluence
      icon: docs
spec:
  type: service
  lifecycle: production
  owner: platform-team
  providesApis:
    - new-service-api-dev
    - new-service-api-qa
    - new-service-api-stage
    - new-service-api-prod
```

Then create the corresponding API files.

## Adding a new API environment

Copy:

```text
catalog/apis/order-api-prod.yaml
```

to:

```text
catalog/apis/order-api-perf.yaml
```

and change:

- metadata.name
- metadata.title
- spec.lifecycle
- spec.definition.$text

## Changing GitHub integration

Change `app-config.yaml` only for non-secret configuration.

Change secrets in the deployment environment/secret store.

## Changing Confluence

Prefer links in catalog metadata for simple access. Use a dedicated plugin only if you need search/rendering/ingestion.

## Configuration validation

Run:

```bash
yarn backstage-cli config:check \
  --lax \
  --strict \
  --config app-config.yaml \
  --config app-config.production.yaml
```

# Post Installation Runbook

## Add a new GitHub service

1. Add `catalog-info.yaml` to the service repository.
2. Add `openapi.yaml` if possible.
3. Add the GitHub project slug annotation.
4. Add `providesApis`.
5. Add Confluence link.
6. Merge the service repository PR.
7. If using explicit central catalog locations, add the component/API YAML here.
8. Verify the entity in Backstage.

## Add Swagger endpoints

For each environment create an API YAML:

```text
catalog/apis/
  order-dev.yaml
  order-qa.yaml
  order-stage.yaml
  order-prod.yaml
```

Example:

```yaml
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: order-api-qa
  title: Order API - QA
spec:
  type: openapi
  lifecycle: qa
  owner: platform-team
  definition:
    $text: https://qa-api.example.com/order/v3/api-docs
```

If the endpoint is private/authenticated, put the OpenAPI file in the private GitHub repo instead.

## Add Confluence

For a simple page:

```yaml
metadata:
  links:
    - url: https://company.atlassian.net/wiki/spaces/TEAM/pages/123
      title: Confluence
      icon: docs
```

For embedded/searchable Confluence content, install and configure the appropriate current Backstage Confluence plugin.

## Add another environment

Copy the API descriptor:

```bash
cp catalog/apis/order-prod.yaml catalog/apis/order-perf.yaml
```

Change:

- name
- title
- lifecycle
- OpenAPI URL

## Deploy a change

```text
Developer
  |
  v
GitHub PR
  |
  v
CI
  |
  +-- lint
  +-- typecheck
  +-- tests
  +-- config check
  +-- Docker build
  |
  v
Merge main
  |
  v
Deploy workflow
  |
  v
Azure VM
```

## Rollback

Keep the previous image tag.

```bash
export BACKSTAGE_IMAGE=backstage:<known-good-sha>
docker compose up -d
```

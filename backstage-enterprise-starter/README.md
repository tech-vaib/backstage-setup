# Backstage Enterprise Starter — Stable Channel

This repository is a configuration/operations overlay for a Backstage application created from the **stable `@backstage/create-app` channel**.

It is designed for this environment:

- Mac development
- Azure Ubuntu VM
- Docker deployment
- Optional standalone (non-Docker) deployment
- PostgreSQL either local/on the VM or external
- Multiple private GitHub repositories
- Multiple environments: DEV, QA, PROD
- Multiple Swagger/OpenAPI endpoints in every environment
- Existing Confluence pages exposed as links

> IMPORTANT: This package is intentionally **not** a replacement for the generated Backstage application. Start with the official Backstage app created by `npx @backstage/create-app` and copy/merge the files in this package into that application. This avoids overwriting version-specific generated files.

## 0. Stable Backstage version

Use the stable channel, not `next` or `nightly`.

Create a new app only if needed:

```bash
npx @backstage/create-app@latest
```

The npm `latest` tag is the stable create-app channel; `next` and `nightly` are separate pre-release channels.

If you already created the app successfully, **do not recreate it**. Keep your existing generated `package.json` and `yarn.lock`.

Check your current app:

```bash
yarn backstage-cli info
```

Keep the generated dependency versions together. Do not manually mix arbitrary `@backstage/*` versions.

---

# 1. Target repository structure

After applying this package to your generated Backstage application:

```text
company-backstage/
|
+-- app-config.yaml
+-- app-config.production.yaml
+-- app-config.local.yaml              # LOCAL ONLY; never commit
+-- catalog-info.yaml
+-- package.json
+-- yarn.lock
|
+-- catalog/
|   |
|   +-- apis/
|   |   +-- customer-service/
|   |   |   +-- dev/
|   |   |   |   +-- customer-v1.yaml
|   |   |   |   +-- customer-v2.yaml
|   |   |   +-- qa/
|   |   |   |   +-- customer-v1.yaml
|   |   |   |   +-- customer-v2.yaml
|   |   |   +-- prod/
|   |   |       +-- customer-v1.yaml
|   |   |       +-- customer-v2.yaml
|   |   |
|   |   +-- orders-service/
|   |       +-- dev/
|   |       +-- qa/
|   |       +-- prod/
|   |
|   +-- components/
|       +-- examples/
|           +-- customer-service.yaml
|
+-- docs/
|   +-- architecture.md
|
+-- ops/
|   +-- config/
|   |   +-- backstage.env.example
|   |   +-- postgres.env.example
|   |
|   +-- docker/
|   |   +-- build.sh
|   |   +-- deploy.sh
|   |   +-- docker-compose.yml
|   |   +-- logs.sh
|   |   +-- start.sh
|   |   +-- stop.sh
|   |   +-- restart.sh
|   |
|   +-- standalone/
|       +-- install-postgres.sh
|       +-- start.sh
|       +-- stop.sh
|       +-- restart.sh
|       +-- status.sh
|
+-- scripts/
    +-- validate-catalog.sh
```

Do NOT commit:

```text
node_modules/
dist/
dist-types/
coverage/
ops/config/*.env
app-config.local.yaml
*.pem
*.key
```

---

# 2. Very important: how multiple Swagger endpoints work

You said you have:

```text
DEV:
  API 1 Swagger
  API 2 Swagger
  API 3 Swagger
  ...

QA:
  API 1 Swagger
  API 2 Swagger
  API 3 Swagger
  ...

PROD:
  API 1 Swagger
  API 2 Swagger
  API 3 Swagger
  ...
```

**Each Swagger/OpenAPI endpoint gets its own Backstage `kind: API` YAML file.**

Recommended exact path:

```text
catalog/apis/<service>/<environment>/<api-version>.yaml
```

Example:

```text
catalog/apis/customer-service/dev/customer-v1.yaml
catalog/apis/customer-service/dev/customer-v2.yaml

catalog/apis/customer-service/qa/customer-v1.yaml
catalog/apis/customer-service/qa/customer-v2.yaml

catalog/apis/customer-service/prod/customer-v1.yaml
catalog/apis/customer-service/prod/customer-v2.yaml
```

If another service has 4 APIs:

```text
catalog/apis/orders-service/dev/orders-v1.yaml
catalog/apis/orders-service/dev/shipping-v1.yaml
catalog/apis/orders-service/dev/payment-v1.yaml
catalog/apis/orders-service/dev/invoice-v1.yaml
```

There is no practical reason to put all Swagger URLs in one huge YAML file. One API entity per API is cleaner and lets Backstage display each API separately.

Backstage's API catalog supports OpenAPI 2 and 3 through the API Docs plugin. See:
https://backstage.io/api/stable/modules/_backstage_plugin_api_docs.html

---

# 3. Example Swagger API entity

File:

```text
catalog/apis/customer-service/dev/customer-v1.yaml
```

Example:

```yaml
apiVersion: backstage.io/v1alpha1
kind: API

metadata:
  name: customer-service-dev-v1
  title: Customer Service API v1 - DEV
  description: Customer Service API version 1 - Development
  tags:
    - customer
    - dev

spec:
  type: openapi
  lifecycle: development
  owner: group:platform-team

  definition:
    $text: https://dev-api.example.company.com/customer/v1/swagger.json
```

QA:

```text
catalog/apis/customer-service/qa/customer-v1.yaml
```

```yaml
apiVersion: backstage.io/v1alpha1
kind: API

metadata:
  name: customer-service-qa-v1
  title: Customer Service API v1 - QA
  description: Customer Service API version 1 - QA
  tags:
    - customer
    - qa

spec:
  type: openapi
  lifecycle: staging
  owner: group:platform-team

  definition:
    $text: https://qa-api.example.company.com/customer/v1/swagger.json
```

PROD:

```text
catalog/apis/customer-service/prod/customer-v1.yaml
```

```yaml
apiVersion: backstage.io/v1alpha1
kind: API

metadata:
  name: customer-service-prod-v1
  title: Customer Service API v1 - PROD
  description: Customer Service API version 1 - Production
  tags:
    - customer
    - prod

spec:
  type: openapi
  lifecycle: production
  owner: group:platform-team

  definition:
    $text: https://api.example.company.com/customer/v1/swagger.json
```

Replace the URLs with your actual Swagger/OpenAPI URLs.

---

# 4. Private Swagger endpoints

If your Swagger URL is private, for example:

```text
https://dev-internal.company.net/customer/swagger.json
```

the Azure VM must be able to reach it.

Backstage fetches remote `$text` definitions from the backend. For non-standard hosts you must allow the host in the Backstage backend reading configuration.

Example:

```yaml
backend:
  reading:
    allow:
      - host: dev-internal.company.net
      - host: qa-internal.company.net
      - host: prod-internal.company.net
```

If your Swagger endpoints require authentication, do not put credentials directly into the API YAML. We should configure the appropriate corporate proxy/authentication pattern instead.

---

# 5. Multiple private GitHub repositories

Your application repositories remain separate.

Example:

```text
GitHub organization: company-platform

Repositories:

customer-service
orders-service
payment-service
inventory-service
notification-service
...
```

The preferred pattern is:

```text
customer-service/
+-- catalog-info.yaml
+-- src/
+-- ...

orders-service/
+-- catalog-info.yaml
+-- src/
+-- ...

payment-service/
+-- catalog-info.yaml
+-- src/
+-- ...
```

You do NOT copy the application source repositories into the Backstage repository.

Instead, each application repository contains a small `catalog-info.yaml` describing itself.

Backstage can discover these repositories through GitHub discovery.

Backstage's catalog documentation states that metadata YAML files are normally stored in source control and repositories may contain one or multiple metadata files.

---

# 6. Example catalog-info.yaml for EVERY application repository

Put this file in the ROOT of each application repository:

```text
customer-service/catalog-info.yaml
orders-service/catalog-info.yaml
payment-service/catalog-info.yaml
...
```

Example:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component

metadata:
  name: customer-service
  title: Customer Service
  description: Customer service application

  annotations:
    github.com/project-slug: YOUR_GITHUB_ORG/customer-service

  links:
    - url: https://confluence.example.company/display/PLAT/customer-service
      title: Confluence Documentation
      icon: docs

spec:
  type: service
  lifecycle: production
  owner: group:platform-team
  system: customer-platform
```

For `orders-service`:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component

metadata:
  name: orders-service
  title: Orders Service
  description: Orders service application

  annotations:
    github.com/project-slug: YOUR_GITHUB_ORG/orders-service

  links:
    - url: https://confluence.example.company/display/PLAT/orders-service
      title: Confluence Documentation
      icon: docs

spec:
  type: service
  lifecycle: production
  owner: group:platform-team
  system: customer-platform
```

Repeat this small file in every private repository you want Backstage to catalog.

---

# 7. How the GitHub repositories appear in Backstage

The flow is:

```text
GitHub
|
+-- customer-service
|     +-- catalog-info.yaml
|
+-- orders-service
|     +-- catalog-info.yaml
|
+-- payment-service
|     +-- catalog-info.yaml
|
+-- inventory-service
      +-- catalog-info.yaml
              |
              v
        GitHub Discovery
              |
              v
          Backstage
              |
              +-- Components
              +-- APIs
              +-- Links
```

You do not need a separate copy of each repository inside Backstage.

---

# 8. GitHub integration configuration

Root file:

```text
app-config.yaml
```

For GitHub.com:

```yaml
integrations:
  github:
    - host: github.com
      token: ${GITHUB_TOKEN}
```

For GitHub Enterprise Server:

```yaml
integrations:
  github:
    - host: ghe.example.company
      apiBaseUrl: https://ghe.example.company/api/v3
      rawBaseUrl: https://ghe.example.company/raw
      token: ${GHE_TOKEN}
```

Use environment variables for tokens.

Backstage supports both GitHub.com and GitHub Enterprise.

---

# 9. Discovering multiple GitHub organizations/repositories

If all repositories are in one or more organizations, use the GitHub catalog discovery provider rather than maintaining a giant list of URLs.

Install the provider from the Backstage root:

```bash
yarn --cwd packages/backend add @backstage/plugin-catalog-backend-module-github
```

Then add to:

```text
packages/backend/src/index.ts
```

```ts
backend.add(import('@backstage/plugin-catalog-backend-module-github'));
```

Then configure:

```yaml
catalog:
  providers:
    github:
      company:
        organization: YOUR_GITHUB_ORG
        catalogPath: /catalog-info.yaml
        filters:
          branch: main
        schedule:
          frequency: { minutes: 30 }
          timeout: { minutes: 3 }
```

If you have multiple organizations, create multiple provider IDs.

Example:

```yaml
catalog:
  providers:
    github:
      company-platform:
        organization: company-platform
        catalogPath: /catalog-info.yaml
        schedule:
          frequency: { minutes: 30 }
          timeout: { minutes: 3 }

      company-apps:
        organization: company-apps
        catalogPath: /catalog-info.yaml
        schedule:
          frequency: { minutes: 30 }
          timeout: { minutes: 3 }
```

If your GitHub environment is Enterprise Server, use the appropriate Enterprise GitHub URL/integration configuration.

---

# 10. Important distinction: GitHub repos vs API YAML files

These are two different things.

## Application repositories

These live OUTSIDE the Backstage repository:

```text
GitHub:
  customer-service
  orders-service
  payment-service
  inventory-service
```

Each gets:

```text
catalog-info.yaml
```

## API catalog definitions

These can live INSIDE the Backstage repository:

```text
company-backstage/
  catalog/
    apis/
      customer-service/
        dev/
        qa/
        prod/
```

So:

```text
GitHub application repos
        |
        | catalog-info.yaml
        v
   Backstage Catalog
        ^
        |
        | API entity YAML files
        |
Backstage repository
```

This separation is intentional.

---

# 11. Confluence

You said you want to use links. Good — that is the simplest and safest approach.

Put the Confluence URL in the component's `metadata.links`.

Example:

```yaml
metadata:
  links:
    - url: https://company.atlassian.net/wiki/spaces/PLAT/pages/123456
      title: Architecture
      icon: docs

    - url: https://company.atlassian.net/wiki/spaces/PLAT/pages/123457
      title: Deployment Guide
      icon: docs

    - url: https://company.atlassian.net/wiki/spaces/PLAT/pages/123458
      title: Runbook
      icon: docs
```

You can add multiple Confluence pages.

For every service:

```text
Component
|
+-- GitHub
+-- Confluence - Architecture
+-- Confluence - Deployment
+-- Confluence - Runbook
+-- APIs
```

No Confluence plugin is required for this link-based approach.

---

# 12. PostgreSQL configuration

Use environment variables so the same Backstage code works with either local or external PostgreSQL.

Example:

```yaml
backend:
  database:
    client: pg
    connection:
      host: ${POSTGRES_HOST}
      port: ${POSTGRES_PORT}
      user: ${POSTGRES_USER}
      password: ${POSTGRES_PASSWORD}
      database: ${POSTGRES_DB}
```

Install PostgreSQL driver if it is not already present:

```bash
yarn --cwd packages/backend add pg
```

## Local PostgreSQL

```text
POSTGRES_HOST=127.0.0.1
POSTGRES_PORT=5432
POSTGRES_DB=backstage
POSTGRES_USER=backstage
POSTGRES_PASSWORD=CHANGE_ME
```

## External PostgreSQL

```text
POSTGRES_HOST=your-postgres-host.company.net
POSTGRES_PORT=5432
POSTGRES_DB=backstage
POSTGRES_USER=backstage
POSTGRES_PASSWORD=CHANGE_ME
```

Do not commit the real `.env`.

---

# 13. Docker deployment

Build:

```bash
./ops/docker/build.sh
```

Deploy:

```bash
./ops/docker/deploy.sh
```

Start:

```bash
./ops/docker/start.sh
```

Stop:

```bash
./ops/docker/stop.sh
```

Restart:

```bash
./ops/docker/restart.sh
```

Logs:

```bash
./ops/docker/logs.sh
```

The generated Backstage project contains:

```text
packages/backend/Dockerfile
```

The current Backstage Docker documentation recommends building the application and packaging it into this image.

---

# 14. Standalone Azure VM deployment

This option does NOT use Docker.

Install PostgreSQL on the VM:

```bash
POSTGRES_PASSWORD='YOUR_PASSWORD' ./ops/standalone/install-postgres.sh
```

Then configure:

```text
ops/config/postgres.env
```

Start:

```bash
./ops/standalone/start.sh
```

Stop:

```bash
./ops/standalone/stop.sh
```

Restart:

```bash
./ops/standalone/restart.sh
```

Status:

```bash
./ops/standalone/status.sh
```

For a real production service, use systemd rather than keeping `yarn start` attached to an SSH session. The included scripts are intended for the initial standalone setup and testing.

---

# 15. Azure VM recommended layout

```text
Azure Ubuntu VM
|
+-- /opt/backstage/company-backstage
|
+-- Backstage
|     +-- Docker mode OR standalone mode
|
+-- PostgreSQL
|     +-- local VM
|       OR
|     +-- external PostgreSQL
|
+-- Nginx / corporate reverse proxy
|
+-- HTTPS
```

Do not expose PostgreSQL directly to the Internet.

For Docker mode, normally expose only the required Backstage/reverse-proxy port.

---

# 16. First-time setup on Azure

```bash
sudo apt update
sudo apt install -y git curl build-essential python3 docker.io
```

Install Node using NVM and use the Node version required by your generated Backstage project's `package.json`/documentation.

Clone:

```bash
git clone YOUR_BACKSTAGE_REPOSITORY
cd company-backstage
```

Install:

```bash
yarn install --immutable
```

Check:

```bash
yarn backstage-cli info
```

---

# 17. Configuration files and what to change

## `app-config.yaml`

Change:

- GitHub integration
- PostgreSQL
- backend reading allow-list for private Swagger hosts
- catalog providers

Do NOT put secrets here.

## `app-config.production.yaml`

Change:

- production backend URL
- production frontend URL
- production-specific settings

Do NOT put secrets here.

## `app-config.local.yaml`

Create this file yourself if needed.

Use it only for local development overrides.

Add to `.gitignore`.

## `packages/backend/src/index.ts`

Change this only when installing additional backend modules such as:

```text
@backstage/plugin-catalog-backend-module-github
```

## Each application repository

Add:

```text
catalog-info.yaml
```

to the repository root.

## Backstage repository

API definitions go here:

```text
catalog/apis/
```

---

# 18. Adding a new API

Suppose you add:

```text
Shipping API
DEV:
  https://dev.company.net/shipping/swagger.json

QA:
  https://qa.company.net/shipping/swagger.json

PROD:
  https://prod.company.net/shipping/swagger.json
```

Create:

```text
catalog/apis/shipping-service/dev/shipping-v1.yaml
catalog/apis/shipping-service/qa/shipping-v1.yaml
catalog/apis/shipping-service/prod/shipping-v1.yaml
```

Put one API entity in each file.

Then add/register those catalog files according to your chosen ingestion method.

---

# 19. Recommended ownership model

Use:

```yaml
spec:
  owner: group:platform-team
```

or the actual owning team.

For example:

```text
group:customer-team
group:orders-team
group:payments-team
```

Do not use arbitrary owner strings if you later want Backstage to resolve the owning group.

---

# 20. Recommended naming

Use stable, lowercase names.

Good:

```text
customer-service-dev-v1
customer-service-qa-v1
customer-service-prod-v1
```

Avoid:

```text
CustomerAPI_DEV
Customer API QA
customer_api_prod
```

This matters because Backstage entity names become identifiers.

---

# 21. What you should NOT do

Do not:

```text
❌ copy all GitHub repositories into the Backstage repo
❌ put GitHub tokens in Git
❌ put PostgreSQL passwords in Git
❌ put private API credentials in Swagger YAML
❌ commit node_modules
❌ commit dist-types
❌ create one gigantic APIs.yaml containing every API
❌ manually register hundreds of GitHub repositories if discovery can be used
```

---

# 22. Initial Git commit

After merging this package:

```bash
git status
```

Confirm that you do NOT see:

```text
node_modules/
dist-types/
app-config.local.yaml
ops/config/*.env
```

Then:

```bash
git add .
git commit -m "Add Backstage enterprise configuration and deployment"
git push
```

---

# 23. Suggested implementation order

Do this in this exact order:

### Phase 1

```text
Mac
 |
 +-- Backstage stable
 +-- PostgreSQL
 +-- Run locally
```

### Phase 2

```text
GitHub
 |
 +-- Configure private GitHub integration
 +-- Add catalog-info.yaml to ONE application repo
 +-- Verify it appears in Backstage
```

Do not add all repositories initially.

Test one first.

### Phase 3

```text
GitHub Discovery
 |
 +-- Organization 1
 +-- Organization 2
 +-- Multiple repositories
```

### Phase 4

```text
APIs
 |
 +-- customer DEV
 +-- customer QA
 +-- customer PROD
```

Test one service with all three environments.

Then add the remaining APIs.

### Phase 5

```text
Confluence links
 |
 +-- Architecture
 +-- Deployment
 +-- Runbook
```

### Phase 6

```text
Azure VM
 |
 +-- Docker
 +-- PostgreSQL
 +-- Backstage
```

### Phase 7

```text
HTTPS
 |
 +-- DNS
 +-- Nginx / corporate ingress
 +-- TLS
```

---

# 24. Final target

Your final Backstage catalog should look conceptually like:

```text
Backstage
|
+-- Components
|   |
|   +-- Customer Service
|   |     |
|   |     +-- GitHub
|   |     +-- Confluence
|   |     +-- APIs
|   |           +-- Customer DEV v1
|   |           +-- Customer DEV v2
|   |           +-- Customer QA v1
|   |           +-- Customer QA v2
|   |           +-- Customer PROD v1
|   |           +-- Customer PROD v2
|   |
|   +-- Orders Service
|   |     +-- GitHub
|   |     +-- Confluence
|   |     +-- APIs
|   |
|   +-- Payment Service
|         +-- GitHub
|         +-- Confluence
|         +-- APIs
|
+-- APIs
|   +-- DEV
|   +-- QA
|   +-- PROD
|
+-- Documentation
|   +-- TechDocs
|   +-- Confluence links
|
+-- Kubernetes
    +-- AKS
```

---

# 25. Official references

Backstage catalog configuration:  
https://backstage.io/docs/features/software-catalog/configuration/

GitHub integration:  
https://backstage.io/docs/integrations/github/

GitHub discovery:  
https://backstage.io/docs/integrations/github/discovery/

API entity format:  
https://backstage.io/docs/features/software-catalog/descriptor-format/

API Docs / OpenAPI:  
https://backstage.io/api/stable/modules/_backstage_plugin_api_docs.html

Docker deployment:  
https://backstage.io/docs/golden-path/deployment/docker/

Deployment:  
https://backstage.io/docs/deployment/

TechDocs:  
https://backstage.io/docs/features/techdocs/getting-started/

---

# 26. Important note about your existing generated application

Because you already successfully created and ran Backstage, **do not replace your generated `packages/`, `examples/`, `package.json`, `yarn.lock`, etc. with files from this package**.

This download contains the enterprise configuration, examples, scripts and documentation that you merge into your existing generated Backstage application.

This is deliberate: Backstage's generated files change between stable releases, while your organization-specific catalog/deployment configuration should remain under your control.

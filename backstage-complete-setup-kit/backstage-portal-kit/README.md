# Backstage Portal Deployment Kit

This repository is a production-oriented starter kit for a Backstage developer portal.

## Scope

- Backstage 1.54.6 baseline (verify the release before creating a new instance)
- Local Mac development
- Azure Ubuntu VM deployment
- Docker + PostgreSQL deployment
- Standalone Node.js option
- GitHub private-repository integration
- Confluence integration
- Multiple environments, each with multiple OpenAPI/Swagger endpoints
- GitHub Actions CI/CD
- Nginx reverse proxy
- No Backstage user authentication configured initially

> Authentication is intentionally omitted per the requested design. Do not expose the portal publicly without adding authentication and authorization.

## Repository layout

```text
backstage-portal/
├── .github/workflows/
│   ├── ci.yml
│   └── deploy-azure-vm.yml
├── catalog/
│   ├── apis/
│   ├── components/
│   └── groups/
├── docs/
│   ├── ARCHITECTURE.md
│   ├── CONFIGURATION.md
│   ├── GITHUB.md
│   ├── CONFLUENCE.md
│   ├── SWAGGER.md
│   ├── LOCAL-MAC.md
│   ├── AZURE-VM.md
│   ├── DOCKER.md
│   ├── STANDALONE.md
│   └── OPERATIONS.md
├── scripts/
│   ├── setup-mac.sh
│   ├── start-local.sh
│   ├── build-image.sh
│   ├── deploy-vm.sh
│   └── setup-azure-vm.sh
├── app-config.yaml
├── app-config.local.yaml.example
├── app-config.production.yaml.example
├── docker-compose.yml
├── docker-compose.standalone-db.yml
├── Dockerfile
└── .env.example
```

## Important

The files under this kit are templates. A newly scaffolded Backstage application supplies the actual `packages/`, generated frontend/backend code, package manifests and lockfile. Copy/merge the configuration and deployment files into that application rather than trying to run this repository as-is.

## Recommended production path

1. Create a Backstage app using the pinned release.
2. Apply the files in this kit.
3. Develop and test on Mac.
4. Commit the complete Backstage application to GitHub.
5. GitHub Actions runs lint/typecheck/tests/config validation/build.
6. GitHub Actions builds the Docker image.
7. GitHub Actions transfers the deployment artifact/image to the Azure VM.
8. VM deploys Backstage + PostgreSQL with Docker Compose.
9. Nginx terminates HTTPS and proxies to Backstage.
10. Later, move PostgreSQL to Azure Database for PostgreSQL and secrets to Azure Key Vault.

See `docs/LOCAL-MAC.md`, `docs/AZURE-VM.md`, and `docs/OPERATIONS.md`.

# GitHub Actions Deployment

## Required repository secrets

Create these Actions secrets:

```text
AZURE_VM_HOST
AZURE_VM_USER
AZURE_VM_SSH_PRIVATE_KEY
```

Do not put secrets into YAML.

## VM prerequisites

The VM needs:

```text
Docker
Docker Compose plugin
/opt/backstage/docker-compose.yml
/opt/backstage/app-config.yaml
/opt/backstage/app-config.production.yaml
/opt/backstage/.env
```

The `.env` file remains on the VM and is not overwritten by GitHub Actions.

Example:

```text
POSTGRES_USER=backstage
POSTGRES_PASSWORD=<strong-secret>
POSTGRES_DB=backstage
GITHUB_TOKEN=<secret>
APP_BASE_URL=https://backstage.example.com
BACKEND_BASE_URL=https://backstage.example.com
```

## Deployment model

```text
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
merge main
  |
  v
Build image
  |
  v
GitHub artifact
  |
  v
SSH to Azure VM
  |
  v
docker load
  |
  v
docker compose up -d
```

## More scalable alternative

Instead of copying a large Docker image over SSH on every deployment:

```text
GitHub Actions
     |
     v
Azure Container Registry
     |
     v
Azure VM docker pull
```

This is the recommended evolution for a production setup. Use an Azure managed identity or service principal/OIDC-based GitHub Actions authentication instead of long-lived registry passwords.

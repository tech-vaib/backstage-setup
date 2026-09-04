# GitHub Private Repository Integration

## Backend integration

At minimum:

```yaml
integrations:
  github:
    - host: github.com
      token: ${GITHUB_TOKEN}
```

Do not put the token in Git.

## Recommended production authentication to GitHub

For an organization with many private repositories, a GitHub App is generally preferable to a personal access token because it provides clearer authorization and avoids tying the integration to a person's account.

Create the App and store its private key/credentials in a secret manager. Backstage supports GitHub Apps for backend authentication.

## Repository catalog descriptor

Each service repository should contain:

```text
catalog-info.yaml
openapi.yaml
README.md
```

Example:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: order-service
  annotations:
    github.com/project-slug: mycompany/order-service
spec:
  type: service
  lifecycle: production
  owner: platform-team
  providesApis:
    - order-api
```

## GitHub discovery

Once the initial portal works, use GitHub organization discovery so repositories containing `catalog-info.yaml` can be discovered automatically. This reduces manual catalog registration.

## Change process

A repository owner changes `catalog-info.yaml` and/or API definitions in their repository.

```text
Developer PR
   |
GitHub checks
   |
Merge
   |
Backstage catalog discovery/reload
```

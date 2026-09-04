# Architecture

## Target

```text
Developer
   |
 HTTPS
   |
Nginx on Azure VM
   |
   +---- Backstage container / Node process
   |          |
   |          +---- PostgreSQL
   |          |
   |          +---- GitHub private repositories
   |          |
   |          +---- Confluence
   |          |
   |          +---- OpenAPI/Swagger endpoints
   |
 Azure VM
```

## Data model

```text
GitHub repository
      |
      v
  Component
      |
      +---- providesApis ----> API
                                  |
                                  +---- OpenAPI definition
                                  |
                                  +---- DEV endpoint
                                  +---- QA endpoint
                                  +---- STAGE endpoint
                                  +---- PROD endpoint
```

Backstage catalog entities are YAML descriptors. Keep the catalog descriptors in GitHub so changes are reviewed through pull requests.

## Environment modeling

There are two good patterns:

1. One API entity with an OpenAPI definition stored in GitHub. Use this when all environments expose essentially the same contract.
2. One API entity per environment. Use this when each environment has different schemas, endpoints, authentication, or availability.

For multiple Swagger URLs per environment, prefer separate API entities when each endpoint is a distinct API. Example:

```text
order-api-dev
order-api-qa
order-api-stage
order-api-prod

payment-api-dev
payment-api-qa
payment-api-stage
payment-api-prod
```

This keeps ownership and lifecycle clear.

If you need a single logical API with multiple environment URLs, store the OpenAPI documents in GitHub and keep the runtime base URLs as metadata/annotations or custom fields rather than pretending multiple documents are one OpenAPI document.

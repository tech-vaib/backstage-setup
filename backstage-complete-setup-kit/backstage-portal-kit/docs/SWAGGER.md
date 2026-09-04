# Swagger/OpenAPI and Multiple Environments

## Preferred model

Keep the OpenAPI definition in the service repository:

```text
order-service/
├── catalog-info.yaml
└── openapi.yaml
```

Backstage API entity:

```yaml
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: order-api
spec:
  type: openapi
  lifecycle: production
  owner: platform-team
  definition:
    $text: https://raw.githubusercontent.com/mycompany/order-service/main/openapi.yaml
```

## If you already have runtime Swagger endpoints

Example:

```text
DEV:
https://dev-api.company.com/order/v3/api-docs

QA:
https://qa-api.company.com/order/v3/api-docs

STAGE:
https://stage-api.company.com/order/v3/api-docs

PROD:
https://api.company.com/order/v3/api-docs
```

If each environment has multiple APIs, model them separately.

Example files:

```text
catalog/apis/
├── order-dev.yaml
├── order-qa.yaml
├── order-stage.yaml
├── order-prod.yaml
├── payment-dev.yaml
├── payment-qa.yaml
├── payment-stage.yaml
└── payment-prod.yaml
```

Example:

```yaml
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: order-api-dev
  title: Order API - DEV
spec:
  type: openapi
  lifecycle: development
  owner: platform-team
  definition:
    $text: https://dev-api.company.com/order/v3/api-docs
```

Repeat for QA/STAGE/PROD.

## If endpoints require authentication

Backstage must be able to retrieve the OpenAPI document. If the endpoint requires a token that Backstage does not have, prefer storing the OpenAPI specification in the private GitHub repository.

Avoid embedding runtime API credentials in catalog YAML.

## Environment naming

Use stable names:

```text
<logical-api>-dev
<logical-api>-qa
<logical-api>-stage
<logical-api>-prod
```

This makes search and ownership easier.

## Multiple Swagger endpoints in one environment

If DEV has:

```text
order
payment
customer
inventory
```

create:

```text
order-api-dev
payment-api-dev
customer-api-dev
inventory-api-dev
```

rather than trying to place four unrelated OpenAPI documents into one API entity.

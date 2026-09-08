# API Catalog

Create one YAML file for every Swagger/OpenAPI endpoint.

Recommended path:

```text
catalog/apis/<service>/<environment>/<api-version>.yaml
```

Examples:

```text
catalog/apis/customer-service/dev/customer-v1.yaml
catalog/apis/customer-service/dev/customer-v2.yaml
catalog/apis/customer-service/qa/customer-v1.yaml
catalog/apis/customer-service/prod/customer-v1.yaml
```

Replace the `$text` URL in each file with the real Swagger/OpenAPI JSON/YAML URL.

If a service has 10 APIs in DEV, create 10 files under:

```text
catalog/apis/<service>/dev/
```

Do the same for QA and PROD.

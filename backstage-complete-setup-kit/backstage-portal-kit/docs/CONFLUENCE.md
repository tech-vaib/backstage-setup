# Confluence Integration

Backstage does not treat Confluence as the same thing as the GitHub Software Catalog.

Use two concepts:

1. Catalog metadata and ownership live in Backstage/GitHub.
2. Confluence pages are linked or indexed through the appropriate Backstage Confluence plugin/integration.

## Recommended model

For every service:

```yaml
metadata:
  annotations:
    backstage.io/techdocs-ref: dir:.
    # Add the Confluence annotation supported by the exact plugin/version
    # you install.
```

If you only need a Confluence link, the simplest and most stable approach is to add a standard Backstage `links` entry:

```yaml
metadata:
  links:
    - url: https://YOUR_COMPANY.atlassian.net/wiki/spaces/PLAT/pages/123456
      title: Service Confluence
      icon: docs
```

## Authentication

Private Confluence pages normally require credentials. Do not store those credentials in catalog YAML.

Use environment variables or the plugin's supported secret configuration.

## Important

Confluence plugin package names and configuration can vary with the Backstage release and whether you use Atlassian Cloud/Data Center. Before installing, verify the exact plugin's current documentation and compatibility with your Backstage version.

If you want full Confluence page search/rendering inside Backstage rather than links, install the appropriate current plugin and then add its configuration under `app-config.yaml`.

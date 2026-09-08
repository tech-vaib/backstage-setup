# Backstage Enterprise Architecture

```text
                     +----------------------+
                     |      GitHub           |
                     | private repositories  |
                     +----------+-----------+
                                |
                       catalog-info.yaml
                                |
                                v
                       +----------------+
                       |   Backstage    |
                       |    Catalog     |
                       +--------+-------+
                                |
             +------------------+------------------+
             |                  |                  |
             v                  v                  v
          GitHub            Swagger/OpenAPI     Confluence
          repo links        DEV/QA/PROD         page links
             |                  |                  |
             +------------------+------------------+
                                |
                         PostgreSQL
                                |
                +---------------+---------------+
                |                               |
          Docker deployment               Standalone
                |                               |
             Azure VM                       Azure VM
```

The Backstage repository stores API catalog definitions and deployment configuration.

Application repositories remain independent and contain their own `catalog-info.yaml`.

# Operations

## Docker

```bash
docker compose ps
docker compose logs -f backstage
docker compose logs -f postgres
docker compose restart backstage
docker compose restart postgres
```

## Health

From the VM:

```bash
curl http://127.0.0.1:7007
```

Through Nginx:

```bash
curl -I https://backstage.example.com
```

## Database backup

```bash
mkdir -p /opt/backstage/backups

docker exec backstage-postgres \
  pg_dump -U backstage backstage \
  > /opt/backstage/backups/backstage-$(date +%Y%m%d-%H%M%S).sql
```

Do not rely on local backups alone for production.

## Upgrade

1. Create a branch.
2. Upgrade Backstage dependencies.
3. Run `yarn install`.
4. Run lint/typecheck/tests.
5. Run config check.
6. Build Docker image.
7. Test locally.
8. Deploy to VM.
9. Monitor logs.
10. Keep rollback image/artifact available.

## Rollback

With image-based deployment:

```bash
export BACKSTAGE_IMAGE=backstage:<known-good-tag>
docker compose up -d
```

Never use only `latest` for controlled production deployments. Prefer immutable image tags such as:

```text
backstage:git-<commit-sha>
```

## Monitoring

At minimum monitor:

- container restarts
- CPU
- memory
- disk
- PostgreSQL availability
- HTTP 5xx
- request latency
- GitHub API rate-limit errors
- catalog processing errors
- TechDocs failures

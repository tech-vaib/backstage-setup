# Backstage v1.53.1 VM + Mac kit

This kit pins Backstage to **v1.53.1**, the stable release used for this deployment. The Backstage project has a monthly main/stable release line and a weekly `next` line.

## Ubuntu VM architecture

- Ubuntu VM OS disk: Docker, Nginx, OS packages
- Azure Managed Data Disk mounted at `/mnt/backstage-data`
- Backstage source/config: `/mnt/backstage-data/app`
- PostgreSQL: `/mnt/backstage-data/postgres`
- Backups: `/mnt/backstage-data/backups`
- Secrets: `/mnt/backstage-data/.env`

Run:

`sudo DATA_ROOT=/mnt/backstage-data BACKSTAGE_HOST=backstage.example.com ./setup-backstage-ubuntu-vm.sh`

HTTPS:

`sudo DATA_ROOT=/mnt/backstage-data BACKSTAGE_HOST=backstage.example.com ENABLE_TLS=true CERTBOT_EMAIL=platform@example.com ./setup-backstage-ubuntu-vm.sh`

Microsoft Entra:

`sudo DATA_ROOT=/mnt/backstage-data BACKSTAGE_HOST=backstage.example.com AUTH_MODE=microsoft AZURE_CLIENT_ID='...' AZURE_CLIENT_SECRET='...' AZURE_TENANT_ID='...' ./setup-backstage-ubuntu-vm.sh`

Guest auth is only for a controlled POC. Before enterprise exposure, configure Entra or another real IdP.

## Moving the VM

The managed data disk is detachable and contains the application/configuration and PostgreSQL data. Stop the service, take a database backup, detach the disk, attach it to a replacement VM, mount it at the same path, reinstall the OS dependencies, and start Backstage. DNS/Application Gateway can then be repointed.

A detachable disk is **not a backup**. Keep independent database backups and preferably Azure Backup/snapshots according to your RPO/RTO.

## macOS

Docker Desktop + Homebrew are required. Run `./setup-backstage-mac.sh` and open `http://localhost:7007`. The same pinned Backstage release and PostgreSQL pattern are used, but the Mac script is intended for local/team demo rather than HA production.

## Production recommendation

For a true enterprise production deployment, your existing AKS environment remains preferable: Backstage stateless replicas + Azure Database for PostgreSQL Flexible Server + Entra ID + Application Gateway/WAF + external TechDocs storage + monitoring. The VM option is a good single-node pilot or controlled internal deployment.

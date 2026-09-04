# Azure VM Deployment

## Recommended VM

For a small internal portal, start with an Ubuntu 24.04 LTS VM such as Standard_D2s_v5 or Standard_D4s_v5 depending on expected catalog/TechDocs workload.

Recommended initial layout:

```text
Azure VM
  OS disk
  optional data disk
  Docker
  Nginx
  Backstage
  PostgreSQL
```

For production, prefer Azure Database for PostgreSQL Flexible Server rather than placing PostgreSQL on the same VM.

## Create VM

Example:

```bash
az login

az group create \
  --name rg-backstage \
  --location westus2

az vm create \
  --resource-group rg-backstage \
  --name backstage-vm \
  --image Ubuntu2404 \
  --size Standard_D4s_v5 \
  --admin-username backstageadmin \
  --generate-ssh-keys
```

Allow SSH:

```bash
az vm open-port \
  --resource-group rg-backstage \
  --name backstage-vm \
  --port 22
```

Do not expose port 7007 publicly in the final configuration.

## VM software

Run:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git nginx jq unzip

curl -fsSL https://get.docker.com | sh
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

Log out/in.

Install Node.js 22 only if using standalone mode on the VM.

## Deployment directory

```bash
sudo mkdir -p /opt/backstage
sudo chown -R $USER:$USER /opt/backstage
cd /opt/backstage
```

The GitHub Actions deployment can copy the release artifact here.

## Firewall

Final public inbound access should normally be:

- 22: restricted to administration source IPs or managed access path
- 80: optional for ACME redirect/challenge
- 443: Backstage
- 5432: never public
- 7007: never public

## Nginx

Use the template in `docker/nginx/backstage.conf`.

```bash
sudo cp docker/nginx/backstage.conf /etc/nginx/sites-available/backstage
sudo ln -s /etc/nginx/sites-available/backstage /etc/nginx/sites-enabled/backstage
sudo nginx -t
sudo systemctl reload nginx
```

## TLS

Use your corporate certificate process or ACME/Certbot. Do not put private keys in GitHub.

## Production secret handling

Prefer Azure Key Vault, managed identity, or another secret injection mechanism. For a basic VM POC, a root-readable `.env` file can be used.

Never commit:

- GitHub PAT/private key
- GitHub App private key
- PostgreSQL password
- Confluence API token
- TLS private key

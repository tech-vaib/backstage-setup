# Backstage.io — Ubuntu VM Production Deployment Guide

Companion to `03-ubuntu-vm-production-setup.sh`. Read section 6 first if
you came here asking "does the same script work on Mac?" — short answer: no,
and here's why plus what to use instead.

## 1. What this script builds

One Ubuntu VM running:
- **Backstage backend** (built, not dev mode) as a systemd service on `127.0.0.1:7007`, serving the built frontend itself
- **PostgreSQL 16**, its own dedicated cluster, data directory on a separate disk
- **nginx** terminating TLS (via certbot/Let's Encrypt) and reverse-proxying to the backend
- **ufw** allowing only SSH + HTTP/HTTPS

Everything stateful — the built app, Postgres data, generated secrets —
lives under `/data`, which is its own block device mounted by filesystem
UUID (not device name, which can change between VMs).

## 2. Before you run it

```bash
export DOMAIN="backstage.yourcompany.com"     # must resolve (DNS A record) to this VM's public IP for certbot to work
export ADMIN_EMAIL="you@yourcompany.com"
export DATA_DISK_DEVICE="/dev/sdc"            # your attached/second disk — see note below
export GITHUB_TOKEN="ghp_xxx"

chmod +x 03-ubuntu-vm-production-setup.sh
sudo -E ./03-ubuntu-vm-production-setup.sh
```

**On `DATA_DISK_DEVICE`**: attach a second disk to the VM before running
(in Azure: an additional Managed Disk; on bare Ubuntu/other clouds: any
second block device). Find its name with `lsblk`. If you don't set this
variable, the script still works but puts everything on the root disk —
which defeats the "detach and move to a new VM" goal, so set it.

If the disk is brand new, the script formats it (asks for confirmation
first). If it already has a Backstage/Postgres data directory on it (e.g.
you're re-running this on a new VM after moving the disk), the script
detects that and skips re-initialization — see section 4.

## 3. Wiring up real authentication

The script leaves auth unconfigured on purpose — provider choice is
yours to make deliberately, not something to auto-generate. Guest auth is
not usable once you're on a `production` config layer, so add a real
provider before sharing the URL. Append to
`${APP_DIR}/app-config.production.yaml`, e.g. for GitHub OAuth:

```yaml
auth:
  environment: production
  providers:
    github:
      production:
        clientId: ${AUTH_GITHUB_CLIENT_ID}
        clientSecret: ${AUTH_GITHUB_CLIENT_SECRET}
```

Add the matching values to `/etc/backstage.env`, then:
```bash
sudo systemctl restart backstage
```

## 4. Moving to a new or upgraded VM (the whole point of the separate disk)

**On the old VM:**
```bash
sudo systemctl stop backstage
sudo systemctl stop postgresql@16-data
sudo umount /data
```
Then detach the disk from the old VM (cloud console/CLI action).

**Azure example** (if this VM lives in Azure — adjust names):
```bash
# find the managed disk name attached as /dev/sdc
az vm show -g <rg> -n <old-vm-name> --query "storageProfile.dataDisks" -o table

# detach from old VM
az vm disk detach -g <rg> --vm-name <old-vm-name> --name <disk-name>

# attach to new VM
az vm disk attach -g <rg> --vm-name <new-vm-name> --name <disk-name>
```
(For a bare/other-cloud VM, the equivalent is whatever your provider's
"detach volume / attach volume" action is — the disk itself doesn't care,
it's a standard ext4 filesystem with a stable UUID.)

**On the new VM:**
```bash
export DOMAIN="backstage.yourcompany.com"
export ADMIN_EMAIL="you@yourcompany.com"
export DATA_DISK_DEVICE="/dev/sdc"     # whatever device name the new VM assigns it — may differ from the old VM, that's fine, UUID mount doesn't care
export GITHUB_TOKEN="ghp_xxx"
sudo -E ./03-ubuntu-vm-production-setup.sh
```
The script sees existing data at `/data` and:
- skips formatting (filesystem already exists)
- registers the existing Postgres data directory as a cluster instead of `initdb`-ing a new one
- skips re-scaffolding the app (already present)
- reuses the previously pinned Backstage version, Postgres password, and backend secret (all read back from files under `/data`)
- reinstalls system packages (Node, Postgres, nginx) fresh on the new VM, since those aren't disk state
- re-requests a TLS cert for `$DOMAIN` (harmless if DNS still points at the old VM's IP — update DNS to the new VM's IP first)

This is also your OS-upgrade path: spin up a fresh Ubuntu 26.04 VM, attach
the same disk, run the script — no manual Postgres dump/restore needed.

## 5. Pinned Backstage version

The script resolves `npm view @backstage/create-app version` once, on
first run, and writes it to `/data/.backstage-version` — so a re-run (or a
disk move to a new VM) reuses the exact same version rather than silently
picking up whatever's newest that day. To upgrade deliberately:
```bash
export BACKSTAGE_CREATE_APP_VERSION="1.52.0"   # pick the version you want
rm /data/.backstage-version
sudo -E ./03-ubuntu-vm-production-setup.sh
```
Check current stable releases (skip anything tagged `-next.x`, those are
pre-releases) at https://github.com/backstage/backstage/releases

## 6. "Does the same script work on Mac?"

**No — not as-is, and it shouldn't run unmodified even with edits.** The
Ubuntu script depends on things that are Linux-specific:
- `apt-get`, `systemd` (`systemctl`), `ufw` — none of these exist on macOS
- Device paths like `/dev/sdc` and `mkfs.ext4`/`mount`/`/etc/fstab` — macOS
  uses different disk utilities (`diskutil`) and doesn't have the same
  "detach a cloud disk and reattach to another VM" concept, since a Mac is
  physical hardware, not a cloud VM you can swap disks between on demand

**More importantly: don't run this pattern on a Mac for production.**
macOS isn't meant to be an always-on, publicly-reachable server — no
proper systemd-equivalent process supervision with the same guarantees,
no standard way to auto-recover after a reboot the way a cloud VM/AKS
pod does, and Apple's own EULA restricts running macOS as a server outside
Apple hardware licensing terms in various contexts.

**What a Mac IS good for** (and what your `01-local-mac-setup.sh` already
gives you): a local demo/dev instance for your own testing, using `yarn
dev` or `yarn start`, Docker Postgres, and guest auth — not something you
expose to the internet or hand to a team as "production."

If you want a Mac-based **persistent local instance** (not internet-exposed,
just always-running on your own machine so you don't have to `yarn dev`
every time), that's a reasonable middle ground — see
`03-mac-persistent-local-setup.sh`, which uses `launchd` (macOS's
process-supervisor equivalent) and Homebrew Postgres instead of Docker.
It is explicitly NOT hardened for internet exposure — no TLS, no firewall
config, listens on localhost only.

## 7. Ongoing operations

| Task | Command |
|---|---|
| View logs | `journalctl -u backstage -f` |
| Restart after config change | `sudo systemctl restart backstage` |
| Check Postgres cluster | `pg_lsclusters` |
| Manual Postgres backup | `sudo -u postgres pg_dump backstage > backup.sql` |
| Renew TLS cert | handled automatically by certbot's systemd timer; verify with `systemctl list-timers | grep certbot` |
| Rebuild after upgrading Backstage | bump `BACKSTAGE_CREATE_APP_VERSION`, re-run the script, or manually `yarn build:backend` + restart |

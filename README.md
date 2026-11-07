# nginx-base

A base nginx Docker image with a CI/CD pipeline. Push to `main` and the VM updates itself.

```
git push main ─▶ GitHub Actions ─▶ build image (nginx -t runs) ─▶ push to GHCR
                                  └▶ SSH to VM ─▶ docker compose pull/up ─▶ health check ─▶ (rollback on failure)
```

## What to edit

| Path | Purpose |
|---|---|
| `nginx/snippets/site.conf` | What the site serves. Static by default; commented reverse-proxy example. |
| `nginx/templates/` | HTTP-only and HTTPS server blocks. The container picks one at start (HTTPS once a cert exists). |
| `nginx/nginx.conf` | Global nginx settings. |
| `html/` | Static files baked into the image. |
| `docker-compose.yml` | Runtime on the VM. Add backend services here for proxy mode. |

Any change to these goes live on the VM after merging to `main`. Pull requests build the image (which validates the nginx config) but do not deploy.

## One-time setup

### 1. Prepare the VM (Ubuntu/Debian)

Generate a dedicated deploy key on your machine:

```bash
ssh-keygen -t ed25519 -f ./deploy_key -N "" -C "github-deploy"
```

Copy `scripts/vm-setup.sh` to the VM and run it with the **public** key:

```bash
sudo bash vm-setup.sh "$(cat deploy_key.pub)"
```

This installs Docker, creates a `deploy` user (docker group, no sudo), creates `/opt/nginx-base`, and opens ports 22, 80 and 443.

### 2. Add GitHub secrets

In the repo: Settings → Secrets and variables → Actions.

| Secret | Value |
|---|---|
| `VM_HOST` | VM public IP (or hostname) |
| `VM_USER` | `deploy` |
| `VM_SSH_KEY` | contents of the **private** `deploy_key` |
| `VM_KNOWN_HOSTS` | output of `ssh-keyscan -H <VM_IP>` |
| `VM_PORT` | optional, defaults to 22 |

And one repository **variable** (same page, "Variables" tab): `DOMAIN` = your subdomain, e.g. `app.example.com`.

Also create an environment named `production` (Settings → Environments). You can add required reviewers there if you want a manual approval before each deploy.

Delete the local `deploy_key` files once the secret is saved.

### 3. Push

Push to `main`. Watch the run in the Actions tab, then open `http://<VM_IP>/`.

## How rollback works

Images are tagged with the commit SHA (and `latest`). `scripts/deploy.sh` records the previous tag in `.env`, starts the new one, and waits for the container's health check (`/healthz`). If it never turns healthy, it restarts the previous tag and the workflow fails.

To roll back manually, re-run an older workflow run from the Actions tab, or on the VM:

```bash
cd /opt/nginx-base && printf 'IMAGE=ghcr.io/<owner>/<repo>\nTAG=<old-sha>\n' > .env && docker compose up -d
```

## Local testing

```bash
docker build -t nginx-base:dev .
docker run --rm -p 8080:80 nginx-base:dev
curl localhost:8080/healthz
```

## Custom subdomain + HTTPS

**1. DNS (at your domain provider)**

Add a record for the subdomain:

| Type | Name / Host | Value | TTL |
|---|---|---|---|
| `A` | the subdomain label only, e.g. `app` for `app.example.com` | the VM's public IPv4 | Auto or 300 |

Add an `AAAA` record too only if the VM has a public IPv6 address and you want it used. If you use Cloudflare, set the record to **DNS only** (grey cloud) until the certificate is issued. Check it has propagated:

```bash
dig +short app.example.com   # should print the VM IP
```

**2. Cloud firewall**

In your VM provider's console (security group / firewall rules), allow inbound TCP **80** and **443**. The `ufw` rule in `vm-setup.sh` only covers the OS firewall.

**3. Repo / GitHub**

Set the `DOMAIN` repository variable (see above), then push any commit to `main`. The pipeline writes `DOMAIN` into the VM's `.env`, and the site comes up on `http://app.example.com`.

**4. Get the certificate (once, on the VM)**

```bash
sudo bash /opt/nginx-base/issue-cert.sh app.example.com you@example.com
```

This installs certbot, requests a Let's Encrypt cert through the running nginx, and recreates the container. On start, `nginx/docker-entrypoint.d/15-select-config.sh` sees the cert and switches to HTTPS mode: port 80 redirects to 443. Renewal is automatic (certbot's timer) and reloads nginx via a deploy hook.

If the VM was set up before this change, also run `sudo ufw allow 443/tcp` and `sudo mkdir -p /var/www/certbot`.

Later deploys keep using HTTPS automatically. Until a cert exists, the container falls back to HTTP-only so a deploy never fails for lack of one.

## Notes

- If the repo is private, the VM pulls from GHCR using the workflow's short-lived `GITHUB_TOKEN`, so nothing long-lived is stored on the VM. After a reboot, containers restart from the already-pulled image (`restart: unless-stopped`).
- Packages are private by default on GHCR; no extra setup is needed for this flow.

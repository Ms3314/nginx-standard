# nginx-base

A base nginx Docker image with a CI/CD pipeline. Push to `main` and the VM updates itself.

```
git push main ─▶ GitHub Actions ─▶ build image (nginx -t runs) ─▶ push to GHCR
                                  └▶ SSH to VM ─▶ docker compose pull/up ─▶ health check ─▶ (rollback on failure)
```

## What to edit

| Path | Purpose |
|---|---|
| `nginx/conf.d/default.conf` | Server blocks. Static site by default; commented reverse-proxy example. |
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

This installs Docker, creates a `deploy` user (docker group, no sudo), creates `/opt/nginx-base`, and opens ports 22 and 80.

### 2. Add GitHub secrets

In the repo: Settings → Secrets and variables → Actions.

| Secret | Value |
|---|---|
| `VM_HOST` | VM public IP (or hostname) |
| `VM_USER` | `deploy` |
| `VM_SSH_KEY` | contents of the **private** `deploy_key` |
| `VM_KNOWN_HOSTS` | output of `ssh-keyscan -H <VM_IP>` |
| `VM_PORT` | optional, defaults to 22 |

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

## Adding HTTPS later

You need a domain with an A record pointing at the VM. Then: obtain certs with certbot, mount them into the container in `docker-compose.yml`, expose `443:443`, and add a `listen 443 ssl;` server block plus a port-80 redirect in `default.conf`. Placeholders for these are already marked in the files.

## Notes

- If the repo is private, the VM pulls from GHCR using the workflow's short-lived `GITHUB_TOKEN`, so nothing long-lived is stored on the VM. After a reboot, containers restart from the already-pulled image (`restart: unless-stopped`).
- Packages are private by default on GHCR; no extra setup is needed for this flow.

#!/usr/bin/env bash
# One-time, run ON THE VM as root, AFTER DNS points at the VM and a deploy has run:
#   sudo bash /opt/nginx-base/issue-cert.sh app.example.com you@example.com
# Gets a Let's Encrypt cert, sets up auto-renewal, and switches nginx to HTTPS.
set -euo pipefail

DOMAIN="${1:?usage: issue-cert.sh <domain> <email>}"
EMAIL="${2:?usage: issue-cert.sh <domain> <email>}"

if ! command -v certbot >/dev/null; then
  apt-get update -y && apt-get install -y certbot
fi
mkdir -p /var/www/certbot

# --deploy-hook is saved in the renewal config, so renewals reload nginx too.
certbot certonly --webroot -w /var/www/certbot \
  -d "$DOMAIN" -m "$EMAIL" --agree-tos --no-eff-email --non-interactive \
  --deploy-hook "docker exec nginx nginx -s reload"

# Recreate the container so the entrypoint detects the cert and enables HTTPS.
cd /opt/nginx-base
docker compose up -d --force-recreate

echo "HTTPS enabled: https://$DOMAIN"

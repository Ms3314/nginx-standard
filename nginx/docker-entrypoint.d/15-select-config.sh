#!/bin/sh
# Runs on every container start, before the stock envsubst step (20-*).
# Picks the HTTPS config if a Let's Encrypt cert exists for $DOMAIN,
# otherwise falls back to HTTP-only so the first deploy never crashes.
set -e

SRC=/etc/nginx/templates-available
DST=/etc/nginx/templates
DOMAIN="${DOMAIN:-_}"

mkdir -p "$DST"
rm -f "$DST"/*.template /etc/nginx/conf.d/*.conf

if [ "$DOMAIN" != "_" ] \
   && [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] \
   && [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
    echo "15-select-config: certificate found for $DOMAIN -> HTTPS mode"
    cp "$SRC/https.conf.template" "$DST/"
else
    echo "15-select-config: no certificate for '$DOMAIN' -> HTTP-only mode"
    cp "$SRC/http-only.conf.template" "$DST/"
fi

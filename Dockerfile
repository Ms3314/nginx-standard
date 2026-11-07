# Base nginx image. Everything that changes lives in ./nginx and ./html,
# so a commit to either of those produces a new image and a new deploy.
FROM nginx:1.27-alpine

RUN rm -f /etc/nginx/conf.d/default.conf

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/snippets/ /etc/nginx/snippets/
COPY nginx/templates/ /etc/nginx/templates-available/
COPY nginx/docker-entrypoint.d/ /docker-entrypoint.d/
COPY html/ /usr/share/nginx/html/

# Fail the build if either config (HTTP-only or HTTPS) is invalid.
# A throwaway self-signed cert lets the HTTPS config validate; it is removed after.
RUN apk add --no-cache openssl \
 && mkdir -p /etc/letsencrypt/live/example.test \
 && openssl req -x509 -nodes -newkey rsa:2048 -days 1 -subj "/CN=example.test" \
      -keyout /etc/letsencrypt/live/example.test/privkey.pem \
      -out /etc/letsencrypt/live/example.test/fullchain.pem 2>/dev/null \
 && for t in http-only https; do \
      DOMAIN=example.test envsubst '${DOMAIN}' \
        < /etc/nginx/templates-available/$t.conf.template > /etc/nginx/conf.d/test.conf \
      && nginx -t || exit 1; \
    done \
 && rm -rf /etc/letsencrypt /etc/nginx/conf.d/test.conf \
 && apk del openssl

EXPOSE 80 443

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1/healthz || exit 1

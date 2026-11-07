# Base nginx image. Everything that changes lives in ./nginx and ./html,
# so a commit to either of those produces a new image and a new deploy.
FROM nginx:1.27-alpine

# Remove the stock config so only our files apply
RUN rm -f /etc/nginx/conf.d/default.conf

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/conf.d/ /etc/nginx/conf.d/
COPY html/ /usr/share/nginx/html/

# Fail the build early if the config is invalid
RUN nginx -t

EXPOSE 80

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1/healthz || exit 1

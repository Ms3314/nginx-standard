#!/usr/bin/env bash
# Runs ON THE VM. Usage: deploy.sh <image> <tag> [domain]
# Pulls the new image, restarts the stack, waits for it to be healthy,
# and rolls back to the previous tag if it is not.
set -euo pipefail

IMAGE="${1:?image required}"
TAG="${2:?tag required}"
DOMAIN_ARG="${3:-}"
cd "$(dirname "$0")"

PREV_TAG=""
PREV_DOMAIN=""
if [ -f .env ]; then
  PREV_TAG="$(grep '^TAG=' .env | cut -d= -f2- || true)"
  PREV_DOMAIN="$(grep '^DOMAIN=' .env | cut -d= -f2- || true)"
fi
# Use the domain passed by the pipeline, else keep what was there, else match-all
DOMAIN="${DOMAIN_ARG:-${PREV_DOMAIN:-_}}"

write_env() { printf 'IMAGE=%s\nTAG=%s\nDOMAIN=%s\n' "$IMAGE" "$1" "$DOMAIN" > .env; }

wait_healthy() {
  for _ in $(seq 1 30); do
    status="$(docker inspect -f '{{.State.Health.Status}}' nginx 2>/dev/null || echo none)"
    [ "$status" = "healthy" ] && return 0
    sleep 2
  done
  return 1
}

write_env "$TAG"
docker compose pull
docker compose up -d --remove-orphans

if wait_healthy; then
  echo "Deployed $IMAGE:$TAG"
  docker image prune -f >/dev/null
  exit 0
fi

echo "New version unhealthy." >&2
docker compose logs --tail=50 nginx >&2 || true
if [ -n "$PREV_TAG" ] && [ "$PREV_TAG" != "$TAG" ]; then
  echo "Rolling back to $PREV_TAG" >&2
  write_env "$PREV_TAG"
  docker compose up -d
fi
exit 1

#!/usr/bin/env bash
# One-time VM bootstrap (Ubuntu/Debian). Run as root or with sudo:
#   sudo bash vm-setup.sh "<ssh public key for the deploy user>"
set -euo pipefail

PUBKEY="${1:?pass the deploy public key as the first argument}"
DEPLOY_USER=deploy
APP_DIR=/opt/nginx-base

# Docker Engine + compose plugin
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

# Deploy user (docker group only, no sudo)
id "$DEPLOY_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$DEPLOY_USER"
usermod -aG docker "$DEPLOY_USER"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
echo "$PUBKEY" >> "/home/$DEPLOY_USER/.ssh/authorized_keys"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"
chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh/authorized_keys"

# App directory the pipeline copies into
install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$APP_DIR"

# Firewall (if ufw is present)
if command -v ufw >/dev/null; then
  ufw allow OpenSSH && ufw allow 80/tcp && ufw --force enable
fi

echo "Done. Add the matching private key as the VM_SSH_KEY secret in GitHub."

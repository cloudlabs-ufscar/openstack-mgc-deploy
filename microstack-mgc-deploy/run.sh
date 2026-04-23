#!/usr/bin/env bash

set -euo pipefail

SSH_USER="ubuntu"

tofu plan
tofu apply --auto-approve
IP=$(tofu output -raw vm_public_ip) && \
mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/known_hosts" && \
(ssh-keygen -R "$IP" >/dev/null 2>&1 || true) && \
ssh-keyscan -H "$IP" >> "$HOME/.ssh/known_hosts" 2>/dev/null && \
echo "Waiting for SSH to boot on $IP..." && \
while ! ssh -o ConnectTimeout=2 "${SSH_USER}@${IP}" "echo 'SSH is up!'" 2>/dev/null; do sleep 2; done && \
ssh "${SSH_USER}@${IP}" "tail -f /var/log/cloud-init-output.log"

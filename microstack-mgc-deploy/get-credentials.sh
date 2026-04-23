#!/usr/bin/env bash

set -euo pipefail

SSH_USER="ubuntu"

IP=$(tofu output -raw vm_public_ip) && \
mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/known_hosts" && \
(ssh-keygen -R "$IP" >/dev/null 2>&1 || true) && \
ssh-keyscan -H "$IP" >> "$HOME/.ssh/known_hosts" 2>/dev/null && \
ssh "${SSH_USER}@${IP}" "sudo snap get microstack config.credentials.keystone-password"

IP=$(tofu output -raw vm_public_ip) && \
mkdir -p "$HOME/.ssh" && touch "$HOME/.ssh/known_hosts" && \
(ssh-keygen -R "$IP" >/dev/null 2>&1 || true) && \
ssh-keyscan -H "$IP" >> "$HOME/.ssh/known_hosts" 2>/dev/null && \
ssh ubuntu@$IP "sudo snap get microstack config.credentials.keystone-password"

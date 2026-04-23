IP=$(tofu output -raw vm_public_ip) && \
ssh -o StrictHostKeyChecking=no ubuntu@$IP "sudo snap get microstack config.credentials.keystone-password"
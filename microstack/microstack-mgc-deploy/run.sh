tofu plan
tofu apply --auto-approve
IP=$(tofu output -raw vm_public_ip) && \
echo "Waiting for SSH to boot on $IP..." && \
while ! ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no ubuntu@$IP "echo 'SSH is up!'" 2>/dev/null; do sleep 2; done && \
ssh -o StrictHostKeyChecking=no ubuntu@$IP "tail -f /var/log/cloud-init-output.log"
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# SSH options
SSH_KEY="${SSH_KEY_PATH:-~/.ssh/id_rsa}"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "============================================"
echo " Lab Multi-Controller Deploy"
echo "============================================"
echo ""

# Check for terraform or tofu
if command -v terraform &>/dev/null; then
  TF_CMD="terraform"
elif command -v tofu &>/dev/null; then
  TF_CMD="tofu"
else
  echo "ERROR: Neither 'terraform' nor 'tofu' found."
  exit 1
fi

echo "Using: $TF_CMD"
echo ""

# Initialize if needed
if [ ! -d ".terraform" ]; then
  echo "Initializing..."
  $TF_CMD init
  echo ""
fi

echo "Planning..."
$TF_CMD plan
echo ""

read -p "Apply? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo "Applying..."
$TF_CMD apply --auto-approve
echo ""

JUMPHOST=$($TF_CMD output -raw jumphost_public_ip)
CTRL_COUNT="${TF_VAR_controller_count:-2}"

echo "============================================"
echo " Jumphost created: $JUMPHOST"
echo "============================================"
echo ""

echo "Waiting for jumphost SSH..."
for i in $(seq 1 60); do
  if ssh $SSH_OPTS -o ConnectTimeout=5 ubuntu@"$JUMPHOST" "echo ok" &>/dev/null; then
    echo "Jumphost SSH is up."
    break
  fi
  sleep 5
done

echo ""
echo "Waiting for cloud-init to finish on jumphost..."
ssh $SSH_OPTS ubuntu@"$JUMPHOST" '
  while [ ! -f /var/log/cloud-init-jumphost.log ]; do sleep 2; done
  sudo cloud-init status --wait 2>/dev/null || true
  echo "cloud-init done."
'

echo ""
echo "Triggering controller provisioning ($CTRL_COUNT controllers)..."
ssh $SSH_OPTS ubuntu@"$JUMPHOST" "
  if [ -f /opt/lab/.initial-provisioned ]; then
    echo 'Controllers already provisioned.'
  else
    /opt/lab/provision-controllers.sh $CTRL_COUNT 1
    touch /opt/lab/.initial-provisioned
  fi
  echo ''
  echo '=== Controllers ==='
  cat /opt/lab/lab-hosts.txt 2>/dev/null || echo '(none yet)'
"

echo ""
echo "Generating SSH config on jumphost..."
ssh $SSH_OPTS ubuntu@"$JUMPHOST" "lab-ssh-config"

echo ""
echo "============================================"
echo " Done. Jumphost: $JUMPHOST"
echo ""
echo " Controllers are installing MicroStack (~10 min)."
echo ""
echo " Access jumphost:"
echo "   ssh $SSH_OPTS ubuntu@$JUMPHOST"
echo ""
echo " From jumphost, access controllers (uses lab-key auto-generated on jumphost):"
echo "   ssh -F /opt/lab/ssh_config lab-controller-01"
echo ""
echo " Or from local via ProxyJump:"
echo "   ssh $SSH_OPTS -J ubuntu@$JUMPHOST ubuntu@<controller_private_ip>"
echo ""
echo " Add more: provision-controllers.sh <n> [start]"
echo "============================================"

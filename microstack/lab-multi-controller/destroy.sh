#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

SSH_KEY="${SSH_KEY_PATH:-~/.ssh/id_rsa}"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

JUMPHOST_IP=$(terraform output -raw jumphost_public_ip 2>/dev/null || tofu output -raw jumphost_public_ip 2>/dev/null || echo "")
MGC_API_KEY="${TF_VAR_mgc_api_key:-}"

if [ -n "$JUMPHOST_IP" ]; then
  echo "Destroying controllers via jumphost..."
  if ssh $SSH_OPTS -o ConnectTimeout=10 ubuntu@"$JUMPHOST_IP" "
    export TF_VAR_mgc_api_key='$MGC_API_KEY'
    for tf_dir in /opt/lab/tf-lab-controller-*; do
      if [ -d \"\$tf_dir\" ] && [ -f \"\$tf_dir/terraform.tfstate\" ]; then
        echo \"Destroying \$tf_dir...\"
        cd \"\$tf_dir\" && sudo -E terraform destroy -auto-approve -input=false -lock=false 2>&1 || true
      fi
    done
    sudo rm -f /opt/lab/lab-hosts.txt /opt/lab/.initial-provisioned /opt/lab/inventory /opt/lab/ssh_config
    echo 'Controllers destroyed.'
  " 2>/dev/null; then
    echo "Controllers cleaned up via jumphost."
    echo "Waiting for ports to release..."
    sleep 15
  else
    echo "WARNING: Could not reach jumphost to destroy controllers."
    echo "Delete controller VMs manually via MGC console, then re-run this script."
  fi
else
  echo "No jumphost found in terraform state, skipping controller cleanup."
fi

echo ""
echo "Destroying jumphost + security groups..."
if command -v terraform &>/dev/null; then
  terraform destroy
elif command -v tofu &>/dev/null; then
  tofu destroy
else
  echo "ERROR: Neither 'terraform' nor 'tofu' found."
  exit 1
fi

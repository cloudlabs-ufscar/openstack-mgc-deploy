#!/bin/bash
set -e

# Extract IPs from Terraform output
echo "Extracting IPs from Terraform output..."
IPS=$(tofu output -json cluster_ips | jq -r 'values[]' || terraform output -json cluster_ips | jq -r 'values[]')

echo "Removing stale SSH known_hosts entries for cluster IPs..."
for ip in $IPS; do
    ssh-keygen -R "$ip" > /dev/null 2>&1 || true
done

echo "Waiting for SSH to be reachable on all nodes..."
for ip in $IPS; do
    echo "Waiting for SSH on $ip..."
    # Loop until ssh command succeeds
    until ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 ubuntu@$ip true > /dev/null 2>&1; do
        sleep 5
    done
    echo "Node $ip is reachable."
done

echo "Ensuring hostnames resolve to ens3 IPs on all nodes..."
for ip in $IPS; do
    echo "Configuring /etc/hosts on $ip..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$ip "set -e; hn=\$(hostname -s); hf=\$(hostname -f); api_ip=\$(ip -4 -o addr show dev ens3 | awk '{print \$4}' | cut -d/ -f1); sudo sed -i \"/[[:space:]]\$hn\([[:space:]]\|\$\)/d\" /etc/hosts; sudo sed -i \"/[[:space:]]\$hf\([[:space:]]\|\$\)/d\" /etc/hosts; if [ \"\$hf\" = \"\$hn\" ]; then echo \"\$api_ip \$hn\" | sudo tee -a /etc/hosts > /dev/null; else echo \"\$api_ip \$hf \$hn\" | sudo tee -a /etc/hosts > /dev/null; fi"
done

REF_INVENTORY="$HOME/kolla-venv/share/kolla-ansible/ansible/inventory/multinode"
if [ -f "$REF_INVENTORY" ] && ! grep -q '^\[deployment\]$' ./multinode; then
    echo "Appending Kolla reference inventory groups to ./multinode..."
    echo >> ./multinode
    awk '/^\[deployment\]$/,0' "$REF_INVENTORY" >> ./multinode
fi

# Keep group schema from the reference inventory, but do not manage localhost as a target host.
sed -i '/^[[:space:]]*localhost[[:space:]]\+ansible_connection=local[[:space:]]*$/d' ./multinode

echo "Running Kolla bootstrap-servers..."
export ANSIBLE_HOST_KEY_CHECKING=False
kolla-genpwd
kolla-ansible bootstrap-servers -i ./multinode
kolla-ansible prechecks -i ./multinode 
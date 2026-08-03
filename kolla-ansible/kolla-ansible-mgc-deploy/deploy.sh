#!/bin/bash
set -e

# Extract IPs from Terraform output
echo "Extracting IPs from Terraform output..."
IPS=$(tofu output -json cluster_ips | jq -r 'values[]' || terraform output -json cluster_ips | jq -r 'values[]')
CONTROLLER_IP=$(tofu output -json cluster_ips | jq -r '.controller' || terraform output -json cluster_ips | jq -r '.controller')

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

echo "Ensuring hostnames resolve to ens3 IPs on all nodes and fixing apt mirrors..."
for ip in $IPS; do
    echo "Configuring /etc/hosts and apt on $ip..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$ip "set -e
    hn=\$(hostname -s)
    hf=\$(hostname -f)
    api_ip=\$(ip -4 -o addr show dev ens3 | awk '{print \$4}' | cut -d/ -f1)
    sudo sed -i \"/[[:space:]]\$hn\([[:space:]]\|\$\)/d\" /etc/hosts
    sudo sed -i \"/[[:space:]]\$hf\([[:space:]]\|\$\)/d\" /etc/hosts
    if [ \"\$hf\" = \"\$hn\" ]; then
        echo \"\$api_ip \$hn\" | sudo tee -a /etc/hosts > /dev/null
    else
        echo \"\$api_ip \$hf \$hn\" | sudo tee -a /etc/hosts > /dev/null
    fi
    
    # Fix APT hanging issues on MGC NAT timeouts
    echo 'Acquire::ForceIPv4 \"true\";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4 > /dev/null
    sudo sed -i 's|http://br-ne-1[a-z]\.clouds\.br\.archive\.ubuntu\.com/ubuntu/|http://archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
    sudo sed -i 's|http://archive\.ubuntu\.com/ubuntu/|http://br.archive.ubuntu.com/ubuntu/|g; s|http://security\.ubuntu\.com/ubuntu/|http://archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
    "
done


REF_INVENTORY="$HOME/kolla-venv/share/kolla-ansible/ansible/inventory/multinode"
if [ -f "$REF_INVENTORY" ] && ! grep -q '^\[deployment\]$' ./multinode; then
    echo "Appending Kolla reference inventory groups to ./multinode..."
    echo >> ./multinode
    awk '/^\[deployment\]$/,0' "$REF_INVENTORY" >> ./multinode
fi

# Keep group schema from the reference inventory, but do not manage localhost as a target host.
sed -i '/^[[:space:]]*localhost[[:space:]]\+ansible_connection=local[[:space:]]*$/d' ./multinode

# --- HAProxy / VIP Logic ---
echo "Fetching Controller ens3 IP to use as internal VIP..."
VIP=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$CONTROLLER_IP "ip -4 -o addr show dev ens3 | awk '{print \$4}' | cut -d/ -f1")
echo "Using Controller IP as VIP: $VIP"
# ---------------------------

echo "Running Kolla bootstrap-servers..."
export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_LOG_PATH="$(pwd)/ansible_deploy.log"

echo "Configuring /etc/kolla/globals.yml..."
sed -i 's/kolla_base_distro: "rocky"/kolla_base_distro: "ubuntu"/g' /etc/kolla/globals.yml || true
sed -i 's/#kolla_base_distro: "rocky"/kolla_base_distro: "ubuntu"/g' /etc/kolla/globals.yml || true

# Strip out any existing VIP configuration/haproxy config to avoid duplicates
sed -i '/^#\?kolla_internal_vip_address/d' /etc/kolla/globals.yml || true
sed -i '/^#\?enable_haproxy/d' /etc/kolla/globals.yml || true
# Ensure the file ends with a newline to avoid corrupted lines
echo "" >> /etc/kolla/globals.yml
echo "kolla_internal_vip_address: \"$VIP\"" >> /etc/kolla/globals.yml
echo "enable_haproxy: \"no\"" >> /etc/kolla/globals.yml
echo "enable_proxysql: \"no\"" >> /etc/kolla/globals.yml

kolla-genpwd
kolla-ansible -vvv bootstrap-servers -i ./multinode
kolla-ansible -vvv prechecks -i ./multinode 
kolla-ansible -vvv pull -i ./multinode 
kolla-ansible -vvv deploy -i ./multinode

# Fix OVS fail_mode on all nodes for MGC VPC compatibility
# Neutron OVS agent sets fail_mode=secure on all bridges, but MGC's VPC
# drops untagged return traffic when bridging rules are strict.
# Changing to standalone allows normal L2 learning to handle flat networks.
echo "Setting OVS fail_mode to standalone on all nodes..."
for ip in $IPS; do
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ip" \
        "sudo docker exec openvswitch_vswitchd ovs-vsctl set-fail-mode br-int standalone 2>/dev/null; \
         sudo docker exec openvswitch_vswitchd ovs-vsctl set-fail-mode br-tun standalone 2>/dev/null; \
         sudo docker exec openvswitch_vswitchd ovs-vsctl set-fail-mode br-ex standalone 2>/dev/null" || true
done
echo "OVS fail_mode fix applied."

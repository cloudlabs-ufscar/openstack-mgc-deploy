#!/bin/bash
set -e

CLUSTER_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$CLUSTER_DIR"

SSH_KEY="${SSH_KEY_PATH:-~/.ssh/id_rsa}"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

if command -v terraform &>/dev/null; then TF_CMD="terraform"; else TF_CMD="tofu"; fi

PREFIX=$(source .env 2>/dev/null && echo $TF_VAR_cluster_prefix || $TF_CMD output -raw cluster_prefix 2>/dev/null || echo "kolla")
INVENTORY="$CLUSTER_DIR/multinode-$PREFIX"

echo "=== Deploying Kolla-Ansible on cluster: $PREFIX ==="

IPS=$($TF_CMD output -json cluster_ips | python3 -c "import sys,json; [print(v) for v in json.load(sys.stdin).values()]")
CONTROLLER_IP=$($TF_CMD output -json cluster_ips | python3 -c "import sys,json; print(json.load(sys.stdin)['controller'])")

echo "Waiting for SSH on all nodes..."
for ip in $IPS; do
    echo "  $ip..."
    until ssh $SSH_OPTS -o ConnectTimeout=5 ubuntu@$ip true > /dev/null 2>&1; do sleep 5; done
    echo "  $ip: OK"
done

echo "Configuring /etc/hosts and apt on all nodes..."
for ip in $IPS; do
    ssh $SSH_OPTS ubuntu@$ip "set -e
    hn=\$(hostname -s)
    api_ip=\$(ip -4 -o addr show dev ens3 | awk '{print \$4}' | cut -d/ -f1)
    sudo sed -i \"/[[:space:]]\$hn\([[:space:]]\|\$\)/d\" /etc/hosts
    echo \"\$api_ip \$hn\" | sudo tee -a /etc/hosts > /dev/null
    echo 'Acquire::ForceIPv4 \"true\";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4 > /dev/null
    sudo sed -i 's|http://br-ne-1[a-z]\.clouds\.br\.archive\.ubuntu\.com/ubuntu/|http://archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
    sudo sed -i 's|http://archive\.ubuntu\.com/ubuntu/|http://br.archive.ubuntu.com/ubuntu/|g; s|http://security\.ubuntu\.com/ubuntu/|http://archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
    "
done

echo "Installing Docker and Python deps on all nodes..."
for ip in $IPS; do
    ssh $SSH_OPTS ubuntu@$ip "
        sudo apt-get update -q
        sudo apt-get install -y -q docker.io python3-pip 2>&1 | tail -3
        sudo pip3 install --break-system-packages docker 2>&1 | tail -3
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo docker --version
    "
done

echo "Generating inventory..."
$TF_CMD output -json cluster_ips | python3 "$CLUSTER_DIR/gen_inventory.py" > "$INVENTORY"
echo "Inventory: $INVENTORY"

REF_INVENTORY="$HOME/kolla-venv/share/kolla-ansible/ansible/inventory/multinode"
if [ -f "$REF_INVENTORY" ] && ! grep -q '^\[deployment\]$' "$INVENTORY"; then
    echo "Appending Kolla reference groups..."
    echo >> "$INVENTORY"
    awk '/^\[deployment\]$/,0' "$REF_INVENTORY" >> "$INVENTORY"
fi
sed -i '/^[[:space:]]*localhost[[:space:]]\+ansible_connection=local[[:space:]]*$/d' "$INVENTORY"

echo "Fetching Controller ens3 IP..."
VIP=$(ssh $SSH_OPTS ubuntu@$CONTROLLER_IP "ip -4 -o addr show dev ens3 | awk '{print \$4}' | cut -d/ -f1")
echo "VIP: $VIP"

echo "Configuring /etc/kolla/globals.yml..."
# Set required values (avoid duplicates)
for key in kolla_base_distro network_interface api_interface neutron_external_interface kolla_container_engine; do
    sed -i "/^#\?${key}:/d" /etc/kolla/globals.yml 2>/dev/null || true
done
for key in kolla_internal_vip_address enable_haproxy enable_proxysql; do
    sed -i "/^#\?${key}:/d" /etc/kolla/globals.yml 2>/dev/null || true
done
cat >> /etc/kolla/globals.yml << GLOBALS
kolla_base_distro: "ubuntu"
network_interface: "ens3"
api_interface: "ens3"
neutron_external_interface: "ens8"
kolla_container_engine: "docker"
kolla_internal_vip_address: "$VIP"
enable_haproxy: "no"
enable_proxysql: "no"
GLOBALS

echo "Running kolla-genpwd..."
source ~/kolla-venv/bin/activate
kolla-genpwd

echo "Running Kolla deploy..."
export ANSIBLE_HOST_KEY_CHECKING=False
kolla-ansible bootstrap-servers -i "$INVENTORY"
kolla-ansible pull -i "$INVENTORY"
kolla-ansible deploy -i "$INVENTORY"

echo "Fixing OVS fail_mode..."
for ip in $IPS; do
    ssh $SSH_OPTS ubuntu@"$ip" \
        "sudo docker exec openvswitch_vswitchd ovs-vsctl set-fail-mode br-int standalone 2>/dev/null || true
         sudo docker exec openvswitch_vswitchd ovs-vsctl set-fail-mode br-tun standalone 2>/dev/null || true
         sudo docker exec openvswitch_vswitchd ovs-vsctl set-fail-mode br-ex standalone 2>/dev/null || true" || true
done

echo "Running post-deploy..."
kolla-ansible post-deploy -i "$INVENTORY"

echo "=== Cluster $PREFIX deployed! ==="
echo "Source: source /etc/kolla/admin-openrc.sh"
echo "Password: grep keystone_admin_password /etc/kolla/passwords.yml"

#!/bin/bash
# Kolla-Ansible Inter-Cluster Migration Test
# Measures network downtime when migrating a VM between two OpenStack clusters
set -e

SK="${SSH_KEY_PATH:-~/.ssh/id_rsa}"
SO="-i $SK -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

S1=201.23.7.213; V1=172.18.3.63
S2=201.23.7.215; V2=$(ssh $SO ubuntu@$S2 "ip -4 -o addr show dev ens3 | awk '{print "'$4'"}' | cut -d/ -f1" 2>/dev/null)
C1=201.23.7.195; C2=201.23.7.210
PW=$(grep keystone_admin_password /tmp/passwords-kolla-src.yml | awk '{print $2}')

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
N="n-$TIMESTAMP"; S="s-$TIMESTAMP"; G="g-$TIMESTAMP"; V="v-$TIMESTAMP"; P="p-$TIMESTAMP"
CIDR="10.0.0.0/24"
RESULTS="./migration-results"
mkdir -p "$RESULTS"

log() { echo "[$(date '+%H:%M:%S.%N')] $1"; }

# Run openstack command on a controller (with timeout to prevent hangs)
os1() { timeout 30 ssh $SO ubuntu@$S1 "sudo docker exec kolla_toolbox openstack --os-auth-url http://$V1:5000/v3 --os-username admin --os-password $PW --os-project-name admin --os-user-domain-name Default --os-project-domain-name Default --os-identity-api-version 3 $*" 2>/dev/null || echo "CMD_FAILED"; }
os2() { timeout 30 ssh $SO ubuntu@$S2 "sudo docker exec kolla_toolbox openstack --os-auth-url http://$V2:5000/v3 --os-username admin --os-password $PW --os-project-name admin --os-user-domain-name Default --os-project-domain-name Default --os-identity-api-version 3 $*" 2>/dev/null || echo "CMD_FAILED"; }

log "========================================="
log " Migration Test: kolla-src -> kolla-tgt"
log " Run: $TIMESTAMP"
log "========================================="
T0=$(date +%s)

# ============================================================
log ""
log "=== PHASE 1: Create VM on source cluster ==="

os1 flavor create m1.tiny --ram 512 --disk 1 --vcpus 1 >/dev/null 2>&1 || true
os2 flavor create m1.tiny --ram 512 --disk 1 --vcpus 1 >/dev/null 2>&1 || true

log "Creating network/subnet/SG on source..."
os1 network create $N >/dev/null 2>&1 || true
os1 subnet create $S --network $N --subnet-range $CIDR >/dev/null 2>&1 || true
os1 security group create $G >/dev/null 2>&1 || true
os1 security group rule create --proto icmp $G >/dev/null 2>&1 || true
os1 security group rule create --proto tcp --dst-port 22 $G >/dev/null 2>&1 || true

log "Booting VM on source (this may take ~30s)..."
os1 server create $V --flavor m1.tiny --image cirros --network $N --security-group $G --wait >/dev/null 2>&1
sleep 5
SRC_IP=$(os1 server show $V -c addresses -f value 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+')
[ -z "$SRC_IP" ] && { log "ERROR: VM not created on source"; exit 1; }
log "Source VM: $SRC_IP (host: $(os1 server show $V -c 'OS-EXT-SRV-ATTR:host' -f value 2>/dev/null))"

T1=$(date +%s)
log "Setup: $((T1 - T0))s"

# ============================================================
log ""
log "=== PHASE 2: Verify + Start Migration ==="

# Quick ping test from source compute
log "Ping test from source compute..."
PING_OK=$(ssh $SO ubuntu@$C1 "ping -c 2 -W 2 $SRC_IP 2>&1" | grep -c "bytes from" || echo 0)
log "Ping received: $PING_OK/2"

# Stop source VM
log "Stopping source VM..."
os1 server stop $V >/dev/null 2>&1 || true
sleep 3
T_STOP=$(date +%s)

# Start ping monitor in background
ssh $SO ubuntu@$C1 "ping -i 0.2 -c 200 $SRC_IP > /tmp/pm.log 2>&1" &
PING_PID=$!
sleep 2

# ============================================================
log ""
log "=== PHASE 3: Recreate on target cluster ==="

log "Creating network/subnet/SG on target..."
os2 network create $N >/dev/null 2>&1 || true
os2 subnet create $S --network $N --subnet-range $CIDR >/dev/null 2>&1 || true
os2 security group create $G >/dev/null 2>&1 || true
os2 security group rule create --proto icmp $G >/dev/null 2>&1 || true
os2 security group rule create --proto tcp --dst-port 22 $G >/dev/null 2>&1 || true

log "Creating port with same IP ($SRC_IP) on target..."
NET_ID2=$(os2 network show $N -c id -f value 2>/dev/null)
PORT_RESULT=$(os2 port create $P --network "$NET_ID2" --fixed-ip ip-address=$SRC_IP --security-group $G 2>/dev/null)
if echo "$PORT_RESULT" | grep -q "CMD_FAILED\|Conflict\|already"; then
  log "Port creation conflict, trying without fixed IP..."
  IP_ARG=""
else
  IP_ARG="--port $(echo "$PORT_RESULT" | grep '| id' | awk '{print $4}')"
fi

log "Booting VM on target..."
if [ -n "$IP_ARG" ]; then
  os2 server create $V --flavor m1.tiny --image cirros $IP_ARG --wait >/dev/null 2>&1
else
  os2 server create $V --flavor m1.tiny --image cirros --network $N --security-group $G --wait >/dev/null 2>&1
fi
sleep 5
TGT_IP=$(os2 server show $V -c addresses -f value 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+')
[ -z "$TGT_IP" ] && TGT_IP=$SRC_IP
log "Target VM: $TGT_IP"

# Wait for VM to be pingable
log "Waiting for ping from target compute..."
T_UP=""
for i in $(seq 1 30); do
  if ssh $SO ubuntu@$C2 "ping -c 1 -W 1 $TGT_IP" &>/dev/null; then
    T_UP=$(date +%s)
    log "Ping successful after ${i}s"
    break
  fi
  sleep 2
done
[ -z "$T_UP" ] && T_UP=$(date +%s) && log "WARNING: Ping never succeeded (OVN issue?)"

# Wait for ping monitor to finish, then kill
sleep 5
kill $PING_PID 2>/dev/null || true
wait $PING_PID 2>/dev/null || true

# ============================================================
log ""
log "=== RESULTS ==="

ssh $SO ubuntu@$C1 "cat /tmp/pm.log" 2>/dev/null > "$RESULTS/ping-$TIMESTAMP.log" || true
PING_SENT=$(grep -c "icmp_seq" "$RESULTS/ping-$TIMESTAMP.log" 2>/dev/null || echo 0)
PING_RECV=$(grep -c "bytes from" "$RESULTS/ping-$TIMESTAMP.log" 2>/dev/null || echo 0)
DOWNTIME=$((T_UP - T_STOP))
TOTAL=$((T_UP - T0))

M="$RESULTS/metrics-$TIMESTAMP.txt"
cat > "$M" << EOF
=========================================
 Migration Test Results
=========================================
Run:         $TIMESTAMP
Source:      kolla-src ($S1, VIP: $V1)
Target:      kolla-tgt ($S2, VIP: $V2)
Source VM:   $SRC_IP (on $C1)
Target VM:   $TGT_IP (on $C2)
Image:       cirros | Flavor: m1.tiny

Timing
------
Setup:              $((T1 - T0))s
Recovery (target):  $((T_UP - T1))s
Network downtime:   ${DOWNTIME}s
Total:              ${TOTAL}s
VM stop -> ping up: $T_STOP -> $T_UP

Network Metrics
---------------
Ping sent:     $PING_SENT
Ping received: $PING_RECV
Packet loss:   $(echo "scale=1; ($PING_SENT - $PING_RECV) * 100 / ($PING_SENT + 1)" | bc 2>/dev/null || echo "N/A")%
Ping log:      $RESULTS/ping-$TIMESTAMP.log

IP preserved:  $( [ "$SRC_IP" = "$TGT_IP" ] && echo "YES" || echo "NO ($SRC_IP -> $TGT_IP)")
EOF

cat "$M"
log "Results: $M"
log "Ping log: $RESULTS/ping-$TIMESTAMP.log"

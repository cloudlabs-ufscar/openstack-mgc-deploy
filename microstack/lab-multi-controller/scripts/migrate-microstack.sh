#!/bin/bash
# Network Migration Test: Ctrl-01 -> Ctrl-02
# Run directly on the lab jumphost.
# Requires: both controllers up + MicroStack running + CirrOS image available.
set -e

RESULTS_DIR="/opt/lab/migration-results"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG="$RESULTS_DIR/migration-$TIMESTAMP.log"
STATE_DIR="$RESULTS_DIR/state-$TIMESTAMP"
PING_LOG="$RESULTS_DIR/ping-$TIMESTAMP.log"
METRICS="$RESULTS_DIR/metrics-$TIMESTAMP.txt"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
CTRL1="lab-controller-01"
CTRL2="lab-controller-02"

NET_NAME="migrate-net-$TIMESTAMP"
SUBNET_NAME="migrate-subnet-$TIMESTAMP"
SUBNET_CIDR="10.0.0.0/24"
FIXED_IP="10.0.0.201"
SG_NAME="migrate-sg-$TIMESTAMP"
PORT_NAME="migrate-port-$TIMESTAMP"
VM_NAME="migrate-vm-$TIMESTAMP"
FLAVOR="m1.tiny"
IMAGE="cirros"          # 13MB, boots in 2-3s, pre-installed in MicroStack. Perfect for rapid network migration tests.

CMD1="microstack.openstack"
CMD2="microstack.openstack"

mkdir -p "$RESULTS_DIR" "$STATE_DIR"

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }
ts()  { date +%s; }
ssh1() { ssh -F /opt/lab/ssh_config $SSH_OPTS "$CTRL1" "$@"; }
ssh2() { ssh -F /opt/lab/ssh_config $SSH_OPTS "$CTRL2" "$@"; }

# ============================================================
log ""
log "=== PHASE -1: Pre-flight checks ==="

log "Checking SSH to Ctrl-01..."
ssh1 "echo ok" || { log "ERROR: Cannot SSH to Ctrl-01"; exit 1; }

log "Checking SSH to Ctrl-02..."
ssh2 "echo ok" || { log "ERROR: Cannot SSH to Ctrl-02"; exit 1; }

log "Checking MicroStack on Ctrl-01..."
CTRL1_READY=$(ssh1 "$CMD1 server list -f value 2>&1" || echo "ERROR")
if echo "$CTRL1_READY" | grep -q "ERROR\|Unable\|Connect"; then
  log "ERROR: MicroStack not ready on Ctrl-01. Run: ssh -F /opt/lab/ssh_config $CTRL1 'snap services microstack'"
  exit 1
fi
log "Ctrl-01 MicroStack: OK"

log "Checking MicroStack on Ctrl-02..."
CTRL2_READY=$(ssh2 "$CMD2 server list -f value 2>&1" || echo "ERROR")
if echo "$CTRL2_READY" | grep -q "ERROR\|Unable\|Connect"; then
  log "ERROR: MicroStack not ready on Ctrl-02. Run: ssh -F /opt/lab/ssh_config $CTRL2 'snap services microstack'"
  exit 1
fi
log "Ctrl-02 MicroStack: OK"

log "Checking CirrOS image available on both controllers..."
ssh1 "$CMD1 image show $IMAGE -c name -f value 2>/dev/null" || {
  log "WARNING: CirrOS not found on Ctrl-01. MicroStack should include it by default."
  log "Trying to create... microstack.openstack image create --public --container-format bare --disk-format qcow2 --file /snap/microstack/current/images/cirros-0.5.1-x86_64-disk.img cirros 2>/dev/null"
  ssh1 "test -f /snap/microstack/current/images/cirros-*.img && echo 'CirrOS image file found'" || {
    log "ERROR: Cannot find CirrOS image. Ensure MicroStack is fully installed."
    exit 1
  }
}
ssh2 "$CMD2 image show $IMAGE -c name -f value 2>/dev/null" || {
  log "WARNING: CirrOS not found on Ctrl-02."
  ssh2 "test -f /snap/microstack/current/images/cirros-*.img" && {
    ssh2 "$CMD2 image create --public --container-format bare --disk-format qcow2 --file /snap/microstack/current/images/cirros-*.img cirros"
    log "CirrOS image created on Ctrl-02"
  } || log "WARNING: Could not auto-create CirrOS on Ctrl-02. Migration may fail at image transfer."
}

log "Pre-checks complete. Both controllers and MicroStack ready."

# ============================================================
log ""
log "=== PHASE 0: Cleanup + Setup test environment ==="
T0=$(ts)

log "Cleaning up any leftover migration resources from previous runs..."
ssh1 "
  for srv in \$($CMD1 server list -c Name -f value 2>/dev/null | grep 'migrate-vm'); do
    $CMD1 server delete \"\$srv\" 2>/dev/null || true
  done
  for img in \$($CMD1 image list -c Name -f value 2>/dev/null | grep 'migrate-vm'); do
    $CMD1 image delete \"\$img\" 2>/dev/null || true
  done
  for port in \$($CMD1 port list -c Name -f value 2>/dev/null | grep 'migrate-port'); do
    $CMD1 port delete \"\$port\" 2>/dev/null || true
  done
  for sg in \$($CMD1 security group list -c Name -f value 2>/dev/null | grep 'migrate-sg'); do
    $CMD1 security group delete \"\$sg\" 2>/dev/null || true
  done
  for subnet in \$($CMD1 subnet list -c Name -f value 2>/dev/null | grep 'migrate-subnet'); do
    $CMD1 subnet delete \"\$subnet\" 2>/dev/null || true
  done
  for net in \$($CMD1 network list -c Name -f value 2>/dev/null | grep 'migrate-net'); do
    $CMD1 network delete \"\$net\" 2>/dev/null || true
  done
  true
"
ssh2 "
  for srv in \$($CMD2 server list -c Name -f value 2>/dev/null | grep 'migrate-vm'); do
    $CMD2 server delete \"\$srv\" 2>/dev/null || true
  done
  for img in \$($CMD2 image list -c Name -f value 2>/dev/null | grep 'migrate-vm'); do
    $CMD2 image delete \"\$img\" 2>/dev/null || true
  done
  for port in \$($CMD2 port list -c Name -f value 2>/dev/null | grep 'migrate-port'); do
    $CMD2 port delete \"\$port\" 2>/dev/null || true
  done
  for sg in \$($CMD2 security group list -c Name -f value 2>/dev/null | grep 'migrate-sg'); do
    $CMD2 security group delete \"\$sg\" 2>/dev/null || true
  done
  for subnet in \$($CMD2 subnet list -c Name -f value 2>/dev/null | grep 'migrate-subnet'); do
    $CMD2 subnet delete \"\$subnet\" 2>/dev/null || true
  done
  for net in \$($CMD2 network list -c Name -f value 2>/dev/null | grep 'migrate-net'); do
    $CMD2 network delete \"\$net\" 2>/dev/null || true
  done
  true
"
log "Cleanup done."

ssh1 "
  $CMD1 network create $NET_NAME 2>/dev/null || echo 'network exists'
  $CMD1 subnet create $SUBNET_NAME --network $NET_NAME --subnet-range $SUBNET_CIDR 2>/dev/null || echo 'subnet exists'
  $CMD1 security group create $SG_NAME 2>/dev/null || echo 'sg exists'
  $CMD1 security group rule create --proto icmp $SG_NAME 2>/dev/null || true
  $CMD1 security group rule create --proto tcp --dst-port 22 $SG_NAME 2>/dev/null || true

  $CMD1 server create $VM_NAME --flavor $FLAVOR --image $IMAGE --network $NET_NAME --security-group $SG_NAME --wait 2>/dev/null
  echo \"VM created on Ctrl-01: \$($CMD1 server show $VM_NAME -c status -f value)\"
  sleep 5
  # Get the actual IP + port assigned by DHCP
  VM_IP=\$($CMD1 server show $VM_NAME -c addresses -f value | grep -oP '\\d+\\.\\d+\\.\\d+\\.\\d+')
  PORT_ID=\$($CMD1 port list --server $VM_NAME -c ID -f value)
  MAC_ADDR=\$($CMD1 port show \$PORT_ID -c mac_address -f value)
  echo \"VM_IP=\$VM_IP MAC=\$MAC_ADDR PORT=\$PORT_ID\"
  # Test connectivity
  ping -c 2 \$VM_IP && echo 'VM reachable from Ctrl-01' || echo 'WARNING: VM not reachable from Ctrl-01'
"

T1=$(ts)
log "Setup complete ($((T1 - T0))s)"

# ============================================================
log ""
log "=== PHASE 1: Capture network state from Ctrl-01 ==="

MAC_ADDR=$(ssh1 "$CMD1 port list --server $VM_NAME -c MAC\ Address -f value")
FIXED_IP=$(ssh1 "$CMD1 server show $VM_NAME -c addresses -f value | grep -oP '\d+\.\d+\.\d+\.\d+'")
log "Captured: MAC=$MAC_ADDR IP=$FIXED_IP"

# ============================================================
log ""
log "=== PHASE 2: Export instance image from Ctrl-01 ==="

ssh1 "$CMD1 server image create $VM_NAME --name ${VM_NAME}-snapshot --wait 2>/dev/null"
IMAGE_ID=$(ssh1 "$CMD1 image show ${VM_NAME}-snapshot -c id -f value")
log "Snapshot created: $IMAGE_ID"

T1=$(ts)
log "Setup complete ($((T1 - T0))s)"

# ============================================================
log ""
log "=== PHASE 2: Recreate network topology on Ctrl-02 ==="

ssh2 "
  $CMD1 network create $NET_NAME 2>/dev/null || echo 'network exists'
  $CMD1 subnet create $SUBNET_NAME --network $NET_NAME --subnet-range $SUBNET_CIDR 2>/dev/null || echo 'subnet exists'
  $CMD1 security group create $SG_NAME 2>/dev/null || echo 'sg exists'
  $CMD1 security group rule create --proto icmp $SG_NAME 2>/dev/null || true
  $CMD1 security group rule create --proto tcp --dst-port 22 $SG_NAME 2>/dev/null || true
  NET_ID=\$($CMD1 network show $NET_NAME -c id -f value)
  $CMD1 port create $PORT_NAME --network \$NET_ID --fixed-ip ip-address=$FIXED_IP --security-group $SG_NAME 2>/dev/null || echo 'port exists'
"

log "Network topology recreated on Ctrl-02"
T2=$(ts)

# ============================================================
log ""
log "=== PHASE 3: Stop source VM + start measuring downtime ==="

log "Stopping source VM on Ctrl-01..."
T_STOP=$(ts)
ssh1 "$CMD1 server stop $VM_NAME" || true
log "Source VM stopped at $(date -d @$T_STOP '+%H:%M:%S')"

log "Starting ping from Ctrl-01 to $FIXED_IP (will fail after VM stops)..."
ssh1 "ping -i 0.2 -c 150 $FIXED_IP > /tmp/ping-source.log 2>&1" &
PING_PID=$!
sleep 3  # let it fail a few times

# ============================================================
log ""
log "=== PHASE 4: Boot migrated instance on Ctrl-02 ==="
T3=$(ts)

PORT_ID2=$(ssh2 "$CMD1 port show $PORT_NAME -c id -f value")

ssh2 "
  $CMD1 server create ${VM_NAME}-migrated --flavor $FLAVOR --image $IMAGE --port $PORT_ID2 --wait 2>/dev/null
  echo \"VM status: \$($CMD1 server show ${VM_NAME}-migrated -c status -f value)\"
  # Verify connectivity
  sleep 5
  ping -c 2 $FIXED_IP && echo 'VM reachable from Ctrl-02' || echo 'WARNING: VM not reachable from Ctrl-02'
"

T_BOOT=$(ts)
log "VM booted on Ctrl-02 ($((T_BOOT - T3))s)"

# Wait for VM to be pingable from Ctrl-02
T_UP=""
log "Waiting for VM to respond to ping from Ctrl-02..."
for i in $(seq 1 30); do
  if ssh2 "ping -c 1 -W 1 $FIXED_IP" &>/dev/null; then
    T_UP=$(ts)
    log "VM reachable from Ctrl-02 after ${i}s"
    break
  fi
  sleep 2
done

if [ -z "$T_UP" ]; then
  T_UP=$(ts)
  log "WARNING: VM never responded to ping. Debug info:"
  ssh2 "
    echo '=== VM status ==='
    $CMD1 server show ${VM_NAME}-migrated -c status -c addresses -f value
    echo '=== Port details ==='
    $CMD1 port show $PORT_NAME -c status -c fixed_ips -c device_id -f value
    echo '=== Network test from controller ==='
    ip route | grep 10.0.0
    ping -c 2 $FIXED_IP 2>&1 || echo 'ping failed'
    arp -n | grep $FIXED_IP || echo 'no ARP entry'
  " | tee -a "$LOG"
fi

# Kill source ping
kill $PING_PID 2>/dev/null || true
wait $PING_PID 2>/dev/null || true

# Parse downtime from source ping log
ssh1 "cat /tmp/ping-source.log" > "$PING_LOG" 2>/dev/null || true
PING_SENT=$(grep -c 'icmp_seq' "$PING_LOG" 2>/dev/null || echo 0)
PING_RECV=$(grep -c 'bytes from' "$PING_LOG" 2>/dev/null || echo 0)
PING_LOSS=$(echo "scale=1; ($PING_SENT - $PING_RECV) * 100 / ($PING_SENT + 1)" | bc 2>/dev/null || echo "N/A")

DOWNTIME=$((T_UP - T_STOP))
log "Downtime: ${DOWNTIME}s (stop=$T_STOP, up=$T_UP)"

# ============================================================
log ""
log "=== PHASE 5: Capture final state and compute metrics ==="

ssh2 "$CMD1 port show $PORT_NAME -f json"  > "$STATE_DIR/port-ctrl2.json"
ssh2 "$CMD1 server show ${VM_NAME}-migrated -f json" > "$STATE_DIR/vm-ctrl2.json"

MAC_ADDR2=$(jq -r '.mac_address' "$STATE_DIR/port-ctrl2.json")
IP2=$(jq -r '.fixed_ips[0].ip_address' "$STATE_DIR/port-ctrl2.json")

T_TOTAL=$((T_UP - T0))
log "Migration complete (${T_TOTAL}s total)"

# ============================================================
log ""
log "=== RESULTS ==="

cat > "$METRICS" << EOF
Migration Test Results
======================
Run ID:     $TIMESTAMP
Source:     Controller-01 ($CTRL1)
Target:     Controller-02 ($CTRL2)
VM:         $VM_NAME -> ${VM_NAME}-migrated
IP:         $FIXED_IP
MAC (src):  $MAC_ADDR
MAC (tgt):  $MAC_ADDR2

Timing
------
Setup:            $((T1 - T0))s
Network recreate: $((T2 - T1))s
VM boot (tgt):    $((T_BOOT - T3))s
Network downtime: ${DOWNTIME}s
Total:            ${T_TOTAL}s

Network Metrics
---------------
Packets sent:    $PING_SENT
Packets recv:    $PING_RECV
Packet loss:     $PING_LOSS%
Ping log:        $PING_LOG

State preserved?
----------------
MAC preserved:   $([ "$MAC_ADDR" = "$MAC_ADDR2" ] && echo "YES" || echo "NO ($MAC_ADDR -> $MAC_ADDR2)")
IP preserved:    $([ "$IP2" = "$FIXED_IP" ] && echo "YES" || echo "NO ($IP2)")

State files: $STATE_DIR/
Log:         $LOG
EOF

cat "$METRICS"
log ""
log "Results saved to: $METRICS"
log "Ping log:         $PING_LOG"
log "State files:      $STATE_DIR/"
log "Migration log:    $LOG"

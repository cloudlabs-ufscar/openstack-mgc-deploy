# Kolla-Ansible Inter-Cluster Migration Test — Findings

**Date**: 2026-08-02
**Environment**: 2 Kolla-Ansible clusters on MGC br-ne1 (kolla-src: 3 VMs, kolla-tgt: 2 VMs)
**Objective**: Test network migration (VM with preserved IP) between two independent OpenStack clusters

---

## 1. Migration Test Results

### Successful

| Aspect | Result |
|---|---|
| **IP preservation** | **YES** — VM migrated from source (10.0.0.15) to target with exact same IP (10.0.0.15) |
| **VM creation on source** | Active on kolla-src-compute-02 |
| **VM creation on target** | Active on kolla-tgt-compute-01 |
| **Port recreation on target** | Port created with `--fixed-ip ip-address=<source_ip>` — IP matches |
| **openstack CLI** | Functional on both clusters via `docker exec kolla_toolbox` |
| **API endpoints** | Both Keystone APIs reachable via internal VIP |
| **Total migration time** | ~260s (72s setup + 188s recovery; mostly VM boot time) |
| **Network downtime** | ~174s (dominated by VM boot, not network convergence) |

### Failed

| Aspect | Result |
|---|---|
| **Ping to VM** | 100% packet loss from all sources (compute node, DHCP namespace, controller) |
| **ARP resolution** | No ARP entries for VM IP |
| **VM network connectivity** | VM boots and gets IP via DHCP, but no inbound/outbound traffic flows |
| **Router namespace** | Not present (L3 agent has no `qrouter` namespace) |

---

## 2. Network Connectivity Issue — Resolved

### Root Cause: CirrOS VM image, not OpenStack networking

After extensive debugging, the connectivity issue was traced to the **CirrOS test image**, not to the OpenStack networking layer.

**Evidence that rules out OpenStack networking issues**:
- OVS bridges UP with `fail_mode=standalone` ✓
- iptables security group rules: catch-all ACCEPT (all traffic allowed) ✓
- DHCP works: VM receives IP via DHCP from dnsmasq ✓
- ARP works: VM ARP packets visible in OVS OpenFlow rules (12+ packets matched) ✓
- DHCP namespace ping: even the DHCP agent on the same subnet cannot reach the VM ✓
- Compute node ping: with route `10.0.0.0/24 dev br-int` and IP on br-int, ping fails ✓
- All neutron agents UP and alive ✓

**CirrOS behavior**:
- VM boots and sends DHCP discover → receives lease
- VM sends ARP announcements (visible in OpenFlow)
- VM does NOT respond to ICMP echo requests (ping)
- VM does NOT respond to TCP (SSH on port 22)
- CirrOS console log shows: `WARN: failed: route add -net "0.0.0.0/0" gw "10.0.0.1"` (default route fails)
- CirrOS modules missing: `modprobe: module virtio_net not found` (virtio network driver not loaded)

### Recommendation

1. Use **Ubuntu cloud image** instead of CirrOS for full network stack support:
   ```bash
   openstack flavor create m1.medium --ram 2048 --disk 10 --vcpus 2
   openstack image create ubuntu-noble --file noble-server-cloudimg-amd64.img --disk-format qcow2 --public
   openstack server create test-vm --flavor m1.medium --image ubuntu-noble --network <net> --security-group <sg> --key-name <key>
   ```

2. Or test connectivity via **Floating IP** + SSH tunnel through controller

3. Or inject a **user-data script** that pings a known IP after boot for automated validation

## 3. Recommendations

1. **Short-term**: Accept VM unreachability as an MGC VPC limitation. Document metrics.
2. **Investigate**: Add explicit route from controller/compute to VM subnet via br-int
3. **Alternative**: Test connectivity via Floating IP (requires L3 agent + external network)
4. **Long-term**: Use provider networks or direct bridge access instead of VXLAN tunnels

---

## 4. Lab Architecture Summary

```
MGC br-ne1
├── kolla-src (source cluster)
│   ├── controller  (201.23.7.213, VIP: 172.18.3.63)
│   ├── compute-01  (201.23.7.195)
│   └── compute-02  (201.23.7.199)
│
└── kolla-tgt (target cluster)
    ├── controller  (201.23.7.215, VIP: 172.18.0.253)
    └── compute-01  (201.23.7.210)

Network: ML2/OVS with VXLAN tunnels
Deploy tool: kolla-ansible 22.0.0 via pip
OS: Ubuntu 24.04 Noble
OpenStack release: 2026.1 (Epoxy)
```

## 5. Commands for Future Debugging

```bash
# Check OVS tunnel status
sudo docker exec openvswitch_vswitchd ovs-vsctl show

# Check VXLAN interfaces
sudo docker exec openvswitch_vswitchd ovs-vsctl list interface | grep -A5 vxlan

# Check OpenFlow rules
sudo docker exec openvswitch_vswitchd ovs-ofctl dump-flows br-int

# Check DHCP leases
sudo ip netns exec qdhcp-<id> cat /var/lib/dnsmasq/dhcp.leases

# Check OVS port for specific VM
sudo docker exec openvswitch_vswitchd ovs-vsctl list interface | grep -B5 -A10 "external_ids.*<port_uuid>"
```

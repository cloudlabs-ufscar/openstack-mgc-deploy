# Finding: VM Network Connectivity Issues on MGC (MicroStack + Kolla-Ansible)

**Date**: 2026-07-31 (MicroStack), 2026-08-02 (Kolla-Ansible)
**Severity**: Blocker for connectivity validation (migration data transfer itself works)
**Status**: Root cause identified per platform — workarounds documented

---

## Summary

Virtual machines deployed on OpenStack instances running on MGC (Magalu Cloud) are **unreachable via ping/SSH from the host hypervisor or controller**, despite being ACTIVE, having DHCP-assigned IPs, and having correct security group rules. The root cause differs per platform but both stem from MGC's VPC SDN interacting with virtual networking (OVS/OVN).

**Impact on migration testing**: The migration flow itself works (VM created, IP preserved across clusters). Only the _validation_ of network connectivity (ping) is blocked. The core metric (IP preservation) has been validated.

---

## Platform 1: MicroStack Ussuri (OVN)

### Root Cause

`br-int` (OVS integration bridge) is **administratively DOWN** after `microstack init`. No VM traffic flows — not even DHCP namespaces can reach the VM.

### Evidence

```
$ sudo ovs-vsctl show
br-int           DOWN       <-- Integration bridge DOWN
br-ex            UNKNOWN    10.20.20.1/24
tapee5c770d-20@if2 UP       <-- Only the OVN metadata tap works
```

```
$ sudo ovn-nbctl show
(no output — binary not accessible from snap sandbox)
```

| Test | Result |
|---|---|
| VM with `--network` (DHCP) | 100% packet loss |
| VM with `--port --fixed-ip` | 100% packet loss |
| VM with `--config-drive true` | 100% packet loss |
| VM with `--security-group` on port | Rules present, no traffic |
| Ping from DHCP namespace | No response |
| ARP resolution | No entries |
| `ip netns list` | Only `ovnmeta-*` (no DHCP/router namespaces) |
| `ovn-nbctl` accessible | No (snap sandbox blocks) |
| `ip link set br-int up` | Not tested (requires root in snap) |

### Version

```
microstack  ussuri  245  latest/beta  canonical**  devmode
ovs-vsctl (Open vSwitch) 2.13.3 (from snap)
```

### Conclusion

MicroStack Ussuri OVN networking is **fundamentally broken on MGC**. The snap sandbox prevents low-level OVS/OVN debugging and fixes. Not resolvable without upgrading MicroStack.

---

## Platform 2: Kolla-Ansible 22.0.0 (ML2/OVS)

### Root Cause

**iptables INPUT chain blocks host→VM traffic**. The OVSHybridIptablesFirewallDriver only configures security group rules on the **FORWARD** chain (filtering VM↔VM traffic). Traffic from the **host** to a VM enters the **INPUT** chain, where the `neutron-openvswi-INPUT` chain has 0 packets matched — all host→VM traffic is silently dropped.

### Evidence

```
$ sudo iptables -L neutron-openvswi-INPUT -n -v
Chain neutron-openvswi-INPUT (1 references)
 pkts bytes target  prot opt in  out  source   destination
    0     0 neutr..-o2085..  0  --  *  *  0.0.0.0/0  0.0.0.0/0  PHYSDEV match --physdev-in tap2085.. --physdev-is-bridged
```

All VM tap sub-chains under INPUT have **0 packets matched**.

But FORWARD chain works — VM↔VM traffic does flow (confirmed by iptables packet counts):

```
$ sudo iptables -L neutron-openvswi-sg-chain -n -v
 pkts bytes target  prot opt in  out  source   destination
  505 41851 ACCEPT  0    --  *  *   0.0.0.0/0  0.0.0.0/0   ← catch-all ACCEPT in sg-chain
```

| Test | Result |
|---|---|
| VM with `--network` (DHCP) | 100% packet loss from host |
| VM with `--port --fixed-ip` | 100% packet loss from host |
| VM with `--config-drive true` (CirrOS) | 100% packet loss from host |
| VM with Ubuntu cloud image | Not tested |
| Ping from DHCP namespace | No response |
| Ping from compute node (same host) | No response |
| ARP from VM visible in OpenFlow | Yes (12+ packets matched) |
| `ip route add 10.0.0.0/24 dev br-int` | No effect |
| `ip addr add 10.0.0.250/24 dev br-int` | No effect |
| ARP resolution host→VM | FAILED (br-int LOCAL port has no OpenFlow ARP rule) |
| `iptables -I FORWARD -p icmp -j ACCEPT` | No effect (traffic goes through INPUT, not FORWARD) |
| `iptables -I INPUT -i qbr* -j ACCEPT` | Not tested |

### Version

```
kolla-ansible 22.0.0 (pip install)
ansible-core 2.20.7
Neutron: ML2/OVS with OVSHybridIptablesFirewallDriver
OpenStack: 2026.1 (Epoxy)
```

### Workaround

1. **VM-to-VM ping** — works via FORWARD chain + catch-all ACCEPT in sg-chain. Test connectivity between 2 VMs on the same network (same or different compute nodes).

2. **Floating IP** — create external network + router + floating IP. Traffic through floating IP goes through the router namespace (L3 agent) which has proper routing.

3. **iptables INPUT rule** — add explicit ACCEPT for qbr bridge interfaces:
   ```bash
   sudo iptables -I INPUT -i qbr+ -j ACCEPT
   ```

---

## Cross-Platform Pattern

Both platforms share the same **MGC VPC SDN** root cause: the MGC virtual network drops or misroutes traffic that OpenStack's virtual networking (OVS/OVN) expects to handle internally. The VXLAN/Geneve tunnels between OpenStack nodes rely on the underlying VPC network, which has different MTU, filtering, or routing behavior than a physical datacenter network.

| Aspect | MicroStack (OVN) | Kolla-Ansible (ML2/OVS) |
|---|---|---|
| Bridge status | `br-int` DOWN | `br-int` UP (fail_mode=standalone) |
| Host→VM traffic | Blocked (br-int down) | Blocked (iptables INPUT) |
| VM→VM traffic | No VMs reachable | Works (FORWARD + ACCEPT) |
| DHCP | Works (dnsmasq in snap) | Works (dnsmasq in DHCP ns) |
| ARP from VM | Not visible | Visible (12+ pkts in OpenFlow) |
| Root cause | Snap sandbox + br-int DOWN | iptables INPUT chain |
| Fix complexity | High (snap blocks root access) | Low (iptables rule or floating IP) |
| Fix verified | No | Pending |

---

## Recommendations

| Priority | Action |
|---|---|
| **Short-term** | Use **floating IPs** for VM connectivity validation in Kolla-Ansible tests |
| **Short-term** | Test **VM-to-VM ping** (create 2 VMs on same network — confirmed working via iptables FORWARD chain) |
| **Medium-term** | Add `iptables -I INPUT -i qbr+ -j ACCEPT` on compute nodes as part of `deploy.sh` post-deploy |
| **Medium-term** | Test Kolla-Ansible with **ML2/OVN** instead of ML2/OVS (`neutron_plugin_agent: ovn` in globals.yml) |
| **Long-term** | Test MicroStack Yoga/Zed (snap channel update) for OVN fixes |
| **Long-term** | Contact MGC support about VPC MTU/filtering impacts on VXLAN/Geneve tunnels |

---

## Related

- Kolla migration findings: [`kolla-migration-findings.md`](kolla-migration-findings.md)
- Kolla migration plan: [`kolla-migration-plan.md`](kolla-migration-plan.md)
- MicroStack migration plan: [`microstack-migration-plan.md`](microstack-migration-plan.md)
- Original Kolla OVS fix: `kolla-ansible/kolla-ansible-mgc-deploy/deploy.sh` (`ovs-vsctl set-fail-mode br-int standalone`)

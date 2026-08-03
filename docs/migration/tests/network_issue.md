# Finding: MicroStack Ussuri OVN Networking — VM Unreachable via Fixed-Port

**Date**: 2026-07-31
**Environment**: lab-multi-controller (MicroStack Ussuri, MGC br-se1)
**Severity**: Blocker for network migration testing
**Status**: Open — requires Kolla-Ansible migration or MicroStack upgrade

---

## Summary

MicroStack Ussuri (snap, `--beta --devmode`) does not provide functional VM networking via OVN when using `port create --fixed-ip` + `server create --port`. The VM boots, receives an IP via DHCP, and shows as ACTIVE, but **ICMP/ping does not work** — 100% packet loss, no ARP entries. This blocks the network migration test (port+IP preservation) between MicroStack clusters.

---

## Evidence

### Test Setup

```bash
# Ctrl-02: Create network + SG + boot VM with --network (dynamic IP)
microstack.openstack network create migrate-net-X
microstack.openstack subnet create migrate-subnet-X --network migrate-net-X --subnet-range 10.0.0.0/24
microstack.openstack security group create migrate-sg-X
microstack.openstack security group rule create --proto icmp migrate-sg-X
microstack.openstack security group rule create --proto tcp --dst-port 22 migrate-sg-X
microstack.openstack server create ping-test --flavor m1.tiny --image cirros \
  --network migrate-net-X --security-group migrate-sg-X --wait
```

### Results

| Metric | Value |
|---|---|
| VM status | ACTIVE |
| IP assigned (DHCP) | 10.0.0.74 / 10.0.0.254 |
| SG ICMP rule | Present (ingress, IPv4, 0.0.0.0/0) |
| Ping from controller | **100% packet loss** |
| Ping to VM | No response |
| ARP entry | None |

### Root Cause Analysis

Debug on the controller revealed:

```
$ sudo ovs-vsctl show
br-int           DOWN       <-- Integration bridge DOWN
br-ex            UNKNOWN    10.20.20.1/24
tapee5c770d-20@if2 UP        <-- Only the OVN metadata tap interface works
```

- **`br-int` is DOWN**: The OVS integration bridge (`br-int`) where all VM virtual ports connect is **administratively down**. No VM traffic can flow through it.
- **`ovn-nbctl` not available as standalone binary**: MicroStack snap bundles OVN/OVS binaries under `/snap/` with non-standard paths, making debugging harder.
- **Only `ovnmeta-*` namespace exists**: No DHCP or router namespaces visible; only the metadata agent is partially functional.

This matches a known OVS pattern also seen in the Kolla-Ansible MGC deployment, where `fail_mode=secure` (OVN default) causes bridges to drop traffic on MGC's VPC SDN. The fix applied there (`ovs-vsctl set-fail-mode br-int standalone`) was a post-deploy workaround.

### Attempted Fixes

| Attempt | Result |
|---|---|
| Use `--network` instead of `--port` | Same failure (100% packet loss) |
| Add `--security-group` to port | Rules present but traffic still blocked |
| Verify DHCP assignment | Works (VM gets IP via DHCP) |
| Check OVN SB port binding | Not accessible (`ovn-nbctl` missing) |
| Bring `br-int` up manually | Not tested (requires root on MicroStack snap) |

### Version Info

```
snap list | grep microstack
microstack  ussuri    245    latest/beta    canonical**  devmode

ovs-vsctl --version
ovs-vsctl (Open vSwitch) 2.13.3 (from snap)
```

---

## Impact

- **Network migration testing** (the primary objective) cannot be performed on MicroStack Ussuri
- VM connectivity is fundamentally broken for CirrOS instances on MicroStack OVN networking
- The `--port` + `--fixed-ip` approach cannot be validated

---

## Recommendations

1. **Short-term**: Migrate testing to Kolla-Ansible (Docker-based OpenStack) where OVS/OVN is known to work with the `fail_mode=standalone` workaround
2. **Medium-term**: Test with MicroStack Yoga/Zed or newer (if snap channel updates are available) which may have OVN fixes
3. **Long-term**: If staying on MicroStack, investigate OVN SB database directly via `sudo snap connect microstack:ovn` and manually set `br-int` fail mode to `standalone`

---

## Related

- Kolla-Ansible MGC deploy has documented fix: `ovs-vsctl set-fail-mode br-int standalone` (see `kolla-ansible-mgc-deploy/deploy.sh:93`)
- OVN security groups (Port Security) may interact with `fail_mode=secure` to drop all traffic when rules don't match
- This is likely an MGC-specific issue: MGC's VPC SDN drops untagged/unknown traffic that OVN expects to handle via OpenFlow

# OpenStack Inter-Cluster Migration Flows

Reference document for migration flow diagrams between OpenStack clusters.

---

## 1. Component Overview

| Component | Project | Role in Migration |
|---|---|---|
| Instance (VM) | Nova | Compute unit to be migrated |
| Network Port | Neutron | Network interface with IP, MAC, security groups |
| Floating IP | Neutron | Public routable IP associated with a port |
| Volume | Cinder | Persistent disk attached to the instance |
| Image / Snapshot | Glance | Base disk template or recovery point |
| Security Group | Neutron | Per-port firewall rules |
| Router | Neutron | L3 routing between networks and external gateway |
| Subnet / Network | Neutron | L2/L3 network where the instance resides |
| Hypervisor | Nova (libvirt/QEMU) | Compute host running the VM |
| Metadata | Nova DB | Instance record, flavor, state |

### Component relationships in migration context

```
┌─────────────────────────────────────────────────┐
│                 OpenStack Source                │
│                                                 │
│  ┌─────────┐    ┌──────────┐    ┌────────────┐  │
│  │ Glance  │    │  Cinder  │    │  Neutron   │  │
│  │ (image) │    │ (volume) │    │ (port/ip)  │  │
│  └────┬────┘    └────┬─────┘    └─────┬──────┘  │
│       │              │                │         │
│       └──────────────┼────────────────┘         │
│                      │                          │
│               ┌──────┴──────┐                   │
│               │    Nova     │                   │
│               │  (instance) │                   │
│               └─────────────┘                   │
└─────────────────────────────────────────────────┘
                       │
                       │  Migration
                       ▼
┌─────────────────────────────────────────────────┐
│                 OpenStack Target                │
│                                                 │
│  ┌─────────┐    ┌──────────┐    ┌────────────┐  │
│  │ Glance  │    │  Cinder  │    │  Neutron   │  │
│  │ (image) │    │ (volume) │    │ (port/ip)  │  │
│  └─────────┘    └──────────┘    └────────────┘  │
│                                                 │
│               ┌─────────────┐                   │
│               │    Nova     │                   │
│               │  (instance) │                   │
│               └─────────────┘                   │
└─────────────────────────────────────────────────┘
```

### Key Documentation Sources

| Component | Official Documentation |
|---|---|
| Nova | https://docs.openstack.org/nova/latest/ |
| Neutron | https://docs.openstack.org/neutron/latest/ |
| Cinder | https://docs.openstack.org/cinder/latest/ |
| Glance | https://docs.openstack.org/glance/latest/ |
| libvirt | https://libvirt.org/docs.html |
| QEMU | https://www.qemu.org/docs/master/ |
| Kolla-Ansible | https://docs.openstack.org/kolla-ansible/latest/ |
| MicroStack | https://microstack.run/docs |
| Ceph RBD | https://docs.ceph.com/en/latest/rbd/ |
| OVN | https://www.ovn.org/en/ |
| BGP EVPN (RFC 7432) | https://datatracker.ietf.org/doc/html/rfc7432 |

---

## 2. Migration Types

### 2.1 Cold Migration (Offline / Shutdown-and-Transfer)

**Current research objective**: migrate an instance with downtime, ensuring complete resource replication.

**Description**: The instance is shut down on the source, its resources (disk, network config) are copied to the target, and the instance is booted there.

**Downtime**: High (minutes to hours, depending on disk size).

#### Components involved

| Step | Component | Operation | Data source |
|---|---|---|---|
| 1 | Nova | `nova stop <instance>` | - |
| 2 | Glance | `glance image-create` (root disk snapshot) | Nova -> Glance Source |
| 3 | Glance | `glance image-download` / `upload` | Glance Source -> Local -> Glance Target |
| 4 | Cinder | `cinder snapshot-create` + `cinder create --snapshot` | Cinder Source -> Cinder Target |
| 5 | Neutron | Register ports on target (MAC, IP, SG) | Neutron Source API -> Neutron Target |
| 6 | Nova | `nova boot --block-device ... --nic port-id=...` | Nova Target |

#### Detailed flow

```
1. nova stop <vm>
   └─ VM shut down, state saved

2. Cinder: snapshot the volume
   ├─ cinder snapshot-create <vol>
   └─ cinder snapshot-show <snap>

3. Volume transfer
   ├─ cinder snapshot-export? (backend-dependent)
   ├─ OR: attach volume to intermediate VM, dd + pipe
   └─ OR: cinder backup-create + backup-restore (Swift/S3)
                                      
4. Cinder: create volume from snapshot/backup
   └─ cinder create --snapshot-id <snap>

5. Glance: upload image (if root disk)
   └─ glance image-create --file <qcow2>

6. Neutron: recreate network topology
   ├─ network create (same CIDR)
   ├─ subnet create
   ├─ port create (same MAC, fixed IP)
   ├─ security group create + rules
   └─ router create + gateway

7. Nova: boot with migrated resources
   └─ nova boot --block-device <vol>
         --nic port-id=<port> --flavor <flavor>
```

#### Technical specifications

| Parameter | Detail |
|---|---|
| **Disk format** | QCOW2 (root disk), RAW (Cinder volumes) |
| **Volume transfer** | `cinder backup-create` -> intermediate Swift/S3 or `rbd export/import` (Ceph) |
| **Snapshots** | Cinder snapshot is copy-on-write; export depends on backend (LVM, Ceph, NFS) |
| **Network** | Must recreate: networks, subnets, ports (fixed MAC via `--mac-address`), security groups, routers |
| **Metadata** | Flavor (CPU, RAM, disk), metadata, tags, availability zone |
| **Limitation** | No native cross-cluster support in OpenStack; done via API calls + custom scripts |

#### Information sources

**CLI commands:**
```bash
# Source: collect data
nova show <vm>                      # flavor, metadata, AZ, attached volumes
nova interface-list <vm>            # ports and IPs
neutron port-show <port>            # MAC, fixed_ips, security_groups
neutron security-group-show <sg>    # rules
cinder list --all-tenants           # project volumes
glance image-show <image>           # format, size, properties

# Target: recreate
neutron net-create --provider:network_type vxlan <name>
neutron subnet-create --allocation-pool ... <net> <cidr>
neutron port-create --fixed-ip ip_address=<ip> --mac-address <mac> <net>
nova boot --flavor <f> --block-device ... --nic port-id=<port> <name>
```

**Documentation links:**
- Nova CLI: https://docs.openstack.org/python-novaclient/latest/cli.html
- Neutron CLI: https://docs.openstack.org/python-neutronclient/latest/cli.html
- Cinder CLI: https://docs.openstack.org/python-cinderclient/latest/cli.html
- Glance CLI: https://docs.openstack.org/python-glanceclient/latest/cli.html
- Cinder backups: https://docs.openstack.org/cinder/latest/admin/volume-backups.html
- Cinder snapshots: https://docs.openstack.org/cinder/latest/admin/snapshots.html
- Glance image upload: https://docs.openstack.org/glance/latest/admin/interoperable-image-import.html
- Neutron port creation: https://docs.openstack.org/neutron/latest/admin/config-port-security.html

---

### 2.2 Network Migration (Port Unbinding / Rebinding)

**Next research objective**: transfer network interfaces (Neutron ports) and IPs between clusters.

**Description**: The network interface (Neutron port) is detached from the source and reattached on the target. The IP (fixed and floating) migrates with it. The instance may be recreated or already exist on the target.

**Downtime**: Medium (seconds to minutes -- depends on network convergence time: BGP, EVPN, OVS).

#### Components involved

| Step | Component | Operation |
|---|---|---|
| 1 | Neutron Source | Collect port configuration (MAC, IP, SG, network) |
| 2 | Neutron Target | Recreate identical network topology |
| 3 | Neutron Target | Create port with same MAC and reserved IP |
| 4 | Nova Target | Attach port to instance on target |
| 5 | Neutron Source | Remove old port / release IP |
| 6 | Routing | Update BGP/EVPN routes for migrated IP |

#### Network migration variants

**A. L2 Migration (same segment)**

```
Source                           Interconnect                    Target
──────                         ──────────────                  ──────
Neutron OVS/OVN                                            Neutron OVS/OVN
     │                                                            │
     │  L2 extension (VXLAN/GRE/VLAN)                             │
     └────────────────────┬───────────────────────────────────────┘
                          │
                   [L2 Interconnect]
                   (same provider network)
```

- Both clusters share the same L2 provider network
- Migrated port keeps the same MAC and IP
- No routing reconfiguration needed
- **Requirement**: datacenters interconnected with L2 stretch (VXLAN EVPN, OTV, etc.)

**B. L3 Migration (different networks)**

```
Source                            Interconnect                     Target
──────                          ──────────────                     ──────
Router (SNAT/DNAT)                                        Router(SNAT/DNAT)
     │                                                              │
    Floating IP                                             Floating IP
    (public)                                              (reassociated)  
     │                                                              │
     └─────────────── BGP/EVPN Route Update ────────────────────────┘
                   (announces the migrated IP)
```

- Floating IP is disassociated from the source and reassociated on the target
- BGP/EVPN announces the new route for the migrated IP
- Convergence depends on the routing protocol (seconds with BGP)

#### Detailed flow

```
1. Identify port to migrate:
   └─ neutron port-show <port>

2. Collect configuration:
   ├─ network_id, subnet_id
   ├─ fixed_ips (ip_address, subnet_id)
   ├─ mac_address
   ├─ security_groups
   ├─ allowed_address_pairs
   └─ binding:host_id (will change)

3. Recreate topology if needed:
   ├─ network (same provider type, segmentation_id)
   ├─ subnet (same CIDR, gateway, DNS)
   └─ security groups + rules

4. Create identical port:
   └─ neutron port-create
         --network <net>
         --fixed-ip ip_address=<ip>
         --mac-address <mac>

5. Attach security groups
   └─ neutron port-update --security-group <sg>

6. Nova: attach port to VM
   └─ nova interface-attach --port-id <port> <vm>

7. (L3) Reassociate Floating IP:
   └─ neutron floatingip-associate <fip> <port>

8. Detach/remove source port:
   └─ neutron port-delete <port_source>

9. Update BGP/EVPN routing
   └─ The path for the migrated IP converges to the target
```

#### Technical specifications

| Parameter | Detail |
|---|---|
| **Provider network** | `vxlan`, `vlan`, `flat`, `gre` -- same type and segmentation_id on both sides |
| **MAC address** | Preserve via `--mac-address` in `port-create` (admin-only in OpenStack) |
| **Fixed IP** | Specify via `--fixed-ip ip_address=...` in `port-create` |
| **Floating IP** | Disassociate on source before reassociating on target; update BGP routes |
| **Security Groups** | Recreate with identical rules (direction, protocol, port, remote_ip_prefix) |
| **Allowed Address Pairs** | Preserve for VIP/HA scenarios |
| **BGP/EVPN** | Typical convergence time: 1-5s (BGP), <1s (EVPN with anycast gateway) |

#### Information sources

**CLI commands:**
```bash
# Collect port configuration
neutron port-show <port> -f json
neutron security-group-show <sg> -f json
neutron security-group-rule-list --security-group <sg> -f json
neutron net-show <net> -f json
neutron subnet-show <subnet> -f json
neutron router-show <router> -f json
neutron floatingip-show <fip> -f json

# Recreate on target
neutron net-create <name> \
  --provider:network_type vxlan \
  --provider:segmentation_id <id> \
  --shared

neutron port-create <net> \
  --mac-address <mac> \
  --fixed-ip ip_address=<ip> \
  --security-group <sg>

# Attach to VM on target
nova interface-attach --port-id <port> <vm>
```

**Documentation links:**
- Neutron port operations: https://docs.openstack.org/neutron/latest/admin/intro-network-ports.html
- Neutron provider networks: https://docs.openstack.org/neutron/latest/admin/config-provider-networks.html
- Neutron security groups: https://docs.openstack.org/neutron/latest/admin/config-security-groups.html
- Floating IPs: https://docs.openstack.org/neutron/latest/admin/config-floating-ips.html
- Neutron allowed address pairs: https://docs.openstack.org/neutron/latest/admin/config-allowed-address-pairs.html
- BGP EVPN in OpenStack (neutron-dynamic-routing): https://docs.openstack.org/neutron-dynamic-routing/latest/
- OVN networking: https://docs.openstack.org/neutron/latest/ovn/index.html
- Open vSwitch (OVS): https://docs.openvswitch.org/en/latest/
- Nova interface-attach: https://docs.openstack.org/nova/latest/admin/attach-ports.html

---

### 2.3 Live Migration (Hot Migration)

**Future research objective**: migrate a running instance without shutdown.

**Description**: The VM's RAM, CPU state, and devices are transferred while the VM continues running. Requires shared storage or simultaneous storage migration.

**Downtime**: Low (milliseconds to a few seconds -- only the final switchover).

#### Prerequisites

| Requirement | Detail |
|---|---|
| **Shared storage** | Ceph RBD, NFS, or other storage accessible by both hypervisors |
| **L2 network stretch** | Same network segment on source and target (or BGP EVPN for L3) |
| **CPU compatibility** | Compatible CPU model between hypervisors (or `cpu_mode=host-model`) |
| **QEMU/libvirt version** | Compatible between source and target |
| **Hypervisor access** | libvirt remote access or Nova API with orchestration |

#### Detailed flow

```
1. Pre-flight checks:
   ├─ CPU compatibility
   ├─ Storage accessible? (RBD/NFS)
   └─ Network reachable?

2. libvirt: virDomainMigrate3()
   ├─ Phase 1: Memory transfer (iterative)
   │   └─ Dirty pages resent until convergence
   ├─ Phase 2: Minimal pause (ms)
   │   ├─ Final CPU state
   │   ├─ Device state
   │   └─ Last memory pages
   └─ Phase 3: Switchover
       ├─ VM resumes on target
       └─ Resources freed on source

3. VM running on target
   └─ Same IP, same storage
```

#### Variant with storage migration (no shared storage)

```
1. Live disk snapshot
   └─ Cinder snapshot-create --force (if supported)

2. Snapshot transfer
   └─ cinder backup-create + backup-restore
   OR rbd export/import (Ceph)
   OR qemu-img convert via pipe

3. Live migration with storage copy
   └─ virDomainMigrate3() + VIR_MIGRATE_NON_SHARED_DISK
   └─ Disk copied alongside memory

4. VM running with local storage
```

#### Technical specifications

| Parameter | Detail |
|---|---|
| **Memory transfer** | `VIR_MIGRATE_LIVE` + iterative until convergence |
| **Max downtime** | Configurable in Nova: `live_migration_downtime` (default 500ms per step) |
| **Max bandwidth** | `live_migration_bandwidth` (MB/s) |
| **Post-copy** | `VIR_MIGRATE_POSTCOPY` -- VM starts on target before memory is fully copied |
| **Auto-converge** | `VIR_MIGRATE_AUTO_CONVERGE` -- throttles CPU on source to accelerate convergence |
| **Storage** | `VIR_MIGRATE_NON_SHARED_DISK` if storage is not shared |
| **libvirt URI** | `qemu+ssh://<target>/system` or `qemu+tls://<target>/system` |

#### Information sources

**CLI commands:**
```bash
# Nova live migration (intra-cluster)
nova live-migration <vm> <target-host>

# libvirt direct (cross-cluster or manual)
virsh migrate --live <vm> qemu+ssh://<target>/system \
  --verbose --persistent --undefinesource \
  --copy-storage-all

# Check parameters
nova hypervisor-show <host>
virsh capabilities
virsh domcapabilities
```

**Documentation links:**
- Nova live migration: https://docs.openstack.org/nova/latest/admin/live-migration-usage.html
- Nova migration configuration: https://docs.openstack.org/nova/latest/admin/migration.html
- libvirt migration API: https://libvirt.org/migration.html
- libvirt migration flags: https://libvirt.org/html/libvirt-libvirt-domain.html#virDomainMigrateFlags
- QEMU migration: https://www.qemu.org/docs/master/devel/migration.html
- Post-copy migration: https://libvirt.org/kbase/postcopy.html
- Ceph RBD live migration: https://docs.ceph.com/en/latest/rbd/rbd-live-migration/

---

### 2.4 Storage Migration (Volume Transfer)

**Description**: Migrate only disks/volumes between clusters, without the instance. Useful when the instance will be recreated on the target but data must be preserved.

#### Flow

```
1. Snapshot the volume
   └─ cinder snapshot-create <vol>

2a. Via backup (any backend):
   └─ cinder backup-create <vol>
   └─ cinder backup-export <backup>
   └─ download locally

2b. Via Ceph RBD (shared Ceph cluster):
   └─ rbd export <pool>/<image> <file>
   └─ rbd import <file> <pool>/<image>

2c. Via qemu-img (attached volume):
   └─ qemu-img convert <source> -O qcow2 <file>
   └─ glance image-create --file <file>
      └─ cinder create --image-id <img>

3. Recreate volume
   └─ cinder create --snapshot-id <snap>
      OR cinder create --image-id <img>
      OR cinder create --source-volid <vol>
            (if shared backend)
```

#### Information sources

**CLI commands:**
```bash
# Volume operations
cinder show <vol>
cinder snapshot-create <vol>
cinder snapshot-show <snap>
cinder backup-create <vol>
cinder backup-restore <backup>
cinder create --snapshot-id <snap> <size>

# RBD export/import
rbd export <pool>/<image> <file>
rbd import <file> <pool>/<image>

# qemu-img
qemu-img convert <source> -O qcow2 <output>
```

**Documentation links:**
- Cinder volumes: https://docs.openstack.org/cinder/latest/admin/volumes.html
- Cinder snapshots: https://docs.openstack.org/cinder/latest/admin/snapshots.html
- Cinder backups: https://docs.openstack.org/cinder/latest/admin/volume-backups.html
- Cinder backup restore: https://docs.openstack.org/cinder/latest/admin/volume-backups-restore.html
- Glance images from volumes: https://docs.openstack.org/cinder/latest/cli/cli-manage-volumes.html
- Ceph RBD import/export: https://docs.ceph.com/en/latest/rbd/rados-rbd-cmds/
- qemu-img: https://www.qemu.org/docs/master/tools/qemu-img.html

---

## 3. Flow and Downtime Summary

| Flow | Downtime | Complexity | Storage | Network | Use Case |
|---|---|---|---|---|---|
| **Cold Migration** | Minutes/hours | Low | Full copy | Recreate | Planned migration with window |
| **Network Migration** | Seconds | Medium | N/A (existing) | Recreate + BGP | Datacenter change preserving IP |
| **Live Migration** | ms ~ few sec | High | Shared or copy | L2 stretch | Migration without interruption |
| **Live + Storage Migration** | Seconds | High | Live copy | L2 stretch | No shared storage |
| **Storage Migration** | Minutes/hours | Low | Copy | N/A | Data replication |

---

## 4. Migration Contexts

### Context A: Intra-datacenter (same provider network)

```
┌──────────────┐         ┌──────────────┐
│   Cluster A  │  VXLAN  │   Cluster B  │
│   Source     │◄───────►│   Target     │
│              │  L2     │              │
│ 172.16.0.0/24│ stretch │ 172.16.0.0/24│
└──────────────┘         └──────────────┘
       │                        │
       └──────── Ceph ──────────┘
            (shared RBD)
```

- **Applicable**: Live Migration, Network Migration L2
- **Requirements**: same L2 segment, shared storage, compatible hypervisors
- **Example**: migration between AZs on MGC br-se1-a -> br-se1-b

### Context B: Inter-datacenter (isolated networks)

```
┌──────────────┐         ┌──────────────┐
│   Cluster A  │  BGP    │   Cluster B  │
│   Source     │◄───────►│   Target     │
│              │  EVPN   │              │
│ 10.0.0.0/24  │         │ 10.1.0.0/24  │
└──────────────┘         └──────────────┘
       │                        │
       └─── Internet/VPN ───────┘
```

- **Applicable**: Cold Migration, Network Migration L3, Storage Migration
- **Requirements**: IP connectivity between clusters, BGP/EVPN routing
- **Example**: migration MGC br-ne1 -> br-se1

### Context C: Heterogeneous clouds (OpenStack -> MGC)

```
┌──────────────┐         ┌──────────────┐
│ OpenStack    │  API    │ Magalu Cloud │
│ On-Premise   │◄───────►│  (MGC)       │
│ (Ceph/NFS)   │  calls  │  (NVMe/etc)  │
└──────────────┘         └──────────────┘
```

- **Applicable**: Cold Migration, Storage Migration
- **Requirements**: API access on both sides, intermediate machine for transfers
- **Example**: migration from local Incus lab -> MGC

### Context D: Current Lab (Jumphost + N Controllers)

```
┌─────────────────────────────────────────┐
│              Magalu Cloud               │
│                                         │
│  ┌──────────────┐                       │
│  │ lab-jumphost │  (public IP)          │
│  └──────┬───────┘                       │
│         │                               │
│    ┌────┴────┐                          │
│    │         │                          │
│    ▼         ▼                          │
│ ┌──────┐ ┌──────┐                       │
│ │Ctrl-1│ │Ctrl-2│  (MicroStack)         │
│ │ OS-1 │ │ OS-2 │                       │
│ └──────┘ └──────┘                       │
│    ▲         ▲                          │
│    │  VPC    │   (private network)      │
│    └────┬────┘                          │
│         │                               │
│  Migration Ctrl-1 -> Ctrl-2             │
└─────────────────────────────────────────┘
```

- **Applicable**: Cold Migration, Network Migration tests
- **Advantage**: controlled environment, same datacenter, minimal latency
- **Limitation**: both MicroStack (Ussuri), no real BGP/EVPN

---

## 5. Information Sources by Component

### Nova

| Source | Description |
|---|---|
| `nova show <vm>` | State, flavor, hypervisor, volumes, AZ |
| `nova interface-list <vm>` | Attached ports |
| `nova hypervisor-show <host>` | Hypervisor CPU, RAM, disk |
| `nova live-migration <vm> <host>` | Live migration API |
| `/etc/nova/nova.conf` | Config: `live_migration_downtime`, `live_migration_bandwidth` |
| libvirt XML: `virsh dumpxml <vm>` | Full VM definition (CPU, devices, disks, NICs) |

**Documentation links:**
- Nova admin guide: https://docs.openstack.org/nova/latest/admin/index.html
- Nova configuration reference: https://docs.openstack.org/nova/latest/configuration/config.html
- Nova live migration deep dive: https://docs.openstack.org/nova/latest/admin/live-migration-usage.html
- Nova flavors: https://docs.openstack.org/nova/latest/admin/flavors.html
- libvirt domain XML format: https://libvirt.org/formatdomain.html

### Neutron

| Source | Description |
|---|---|
| `neutron port-show <port>` | MAC, fixed_ips, security_groups, binding:host_id |
| `neutron net-show <net>` | provider:network_type, provider:segmentation_id |
| `neutron subnet-show <subnet>` | CIDR, gateway_ip, dns_nameservers |
| `neutron security-group-rule-list` | Firewall rules |
| `neutron floatingip-show <fip>` | Public IP, attached port |
| OVN NB/SB DB | Logical routing tables (OVN) |
| `ovs-vsctl show` | OVS bridges and ports |
| `ovs-ofctl dump-flows br-int` | OpenFlow rules on OVS |

**Documentation links:**
- Neutron admin guide: https://docs.openstack.org/neutron/latest/admin/index.html
- Neutron configuration reference: https://docs.openstack.org/neutron/latest/configuration/
- Networking architecture: https://docs.openstack.org/neutron/latest/admin/intro-network-components.html
- OVN in OpenStack: https://docs.openstack.org/neutron/latest/ovn/index.html
- OVS configuration: https://docs.openvswitch.org/en/latest/
- Neutron BGP VPN (inter-cloud): https://docs.openstack.org/networking-bgpvpn/latest/

### Cinder

| Source | Description |
|---|---|
| `cinder show <vol>` | Size, type, backend, snapshot |
| `cinder snapshot-show <snap>` | State, size, source volume |
| `cinder backup-show <backup>` | Backup location (Swift, S3) |
| `rbd info <pool>/<volume>` | (if Ceph backend) |
| `cinder get-pools` | Available backends |

**Documentation links:**
- Cinder admin guide: https://docs.openstack.org/cinder/latest/admin/index.html
- Cinder volume backends: https://docs.openstack.org/cinder/latest/admin/blockstorage-volume-drivers.html
- Cinder backups: https://docs.openstack.org/cinder/latest/admin/volume-backups.html
- Cinder configuration reference: https://docs.openstack.org/cinder/latest/configuration/
- Ceph as Cinder backend: https://docs.ceph.com/en/latest/rbd/rbd-openstack/

### Glance

| Source | Description |
|---|---|
| `glance image-show <img>` | Format (qcow2, raw), size, container_format |
| `glance image-download <img> --file <path>` | Download image |
| `glance image-create --file <path>` | Upload new image |

**Documentation links:**
- Glance admin guide: https://docs.openstack.org/glance/latest/admin/index.html
- Glance image formats: https://docs.openstack.org/glance/latest/admin/interoperable-image-import.html
- Glance configuration reference: https://docs.openstack.org/glance/latest/configuration/

---

## 6. Test Laboratory (Next Steps)

### Current MGC lab structure

```
lab-jumphost (public IP, mgc CLI + terraform + ansible)
    │
    ├── controller-01 (MicroStack, private IP)
    └── controller-02 (MicroStack, private IP)
```

### Test scenarios

1. **Cold Migration controller-01 -> controller-02**
   - Snapshot Cinder + Glance from Ctrl-01
   - Transfer to Ctrl-02
   - Boot on Ctrl-02 with same network config

2. **Network Migration between controllers**
   - Create a port on Ctrl-01
   - Collect configuration
   - Recreate identical port on Ctrl-02
   - Measure downtime

3. **Storage Migration**
   - Cinder volume on Ctrl-01
   - Backup/Restore to Ctrl-02
   - Compare checksums

### Metrics to collect

| Metric | Tool |
|---|---|
| Total migration time | `time` in script |
| Downtime (ping) | `ping -i 0.1 <ip>` during migration |
| Packet loss | `mtr` or `ping` with counters |
| Transfer throughput | `pv` on volumes, `iperf3` |
| Data consistency | `md5sum` / `sha256sum` pre and post |

### Useful references

- OpenStack CLI documentation: https://docs.openstack.org/python-openstackclient/latest/cli/
- OpenStack API reference: https://docs.openstack.org/api-ref/
- MicroStack documentation: https://microstack.run/docs
- Magalu Cloud (MGC) Terraform provider: https://registry.terraform.io/providers/MagaluCloud/mgc/latest/docs
- Kolla-Ansible migration: https://docs.openstack.org/kolla-ansible/latest/user/operating-kolla.html

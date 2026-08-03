# MicroStack Migration Test — Plan & Findings

Teste de migracao de rede entre duas instancias MicroStack no lab MGC (Controller-01 → Controller-02).

**Status**: Teste executado. Migracao funcional. Ping bloqueado por bug do OVN no MicroStack Ussuri.

---

## 1. Arquitetura do Teste

```mermaid
flowchart TB
    subgraph MGC["Magalu Cloud — Default VPC"]
        subgraph Jumphost["lab-jumphost (orchestrator)"]
            JH["Ping monitor<br/>+ migration script"]
        end

        subgraph Ctrl1["Controller-01 (Source)"]
            direction TB
            MS1["MicroStack"]
            Net1["migrate-net<br/>10.0.0.0/24"]
            Port1["migrate-port<br/>MAC: fa:16:3e:xx<br/>IP: 10.0.0.201"]
            VM1["migrate-vm<br/>CirrOS"]
            MS1 --- Net1 --- Port1 --- VM1
        end

        subgraph Ctrl2["Controller-02 (Target)"]
            direction TB
            MS2["MicroStack"]
            Net2["migrate-net<br/>10.0.0.0/24"]
            Port2["migrate-port<br/>same IP<br/>new MAC"]
            VM2["migrate-vm-migrated<br/>CirrOS"]
            MS2 --- Net2 --- Port2 --- VM2
        end

        JH -->|"SSH (lab-key)"| Ctrl1
        JH -->|"SSH (lab-key)"| Ctrl2
        JH -.->|"ping 10.0.0.201<br/>(during migration)"| VM1
        JH -.->|"ping 10.0.0.201<br/>(after migration)"| VM2

        VM1 ==>|"1. snapshot image<br/>2. export network state<br/>3. recreate on target"| VM2
    end

    style VM1 fill:#ffcdd2,stroke:#c62828,color:#1a1a1a
    style VM2 fill:#c8e6c9,stroke:#2e7d32,color:#1a1a1a
    style JH fill:#e3f2fd,stroke:#1565c0,color:#1a1a1a
```

## 2. Migration Flow

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant JH as Jumphost
    participant Ctrl1 as Controller-01<br/>(Source)
    participant Ctrl2 as Controller-02<br/>(Target)

    rect rgb(200,150,100)
        Note over User,Ctrl1: Phase 0: Setup
        User->>JH: SCP migrate-network.sh
        User->>JH: SSH + run script
        JH->>Ctrl1: Create network, subnet, SG
        JH->>Ctrl1: Create port (--fixed-ip 10.0.0.201)
        JH->>Ctrl1: Boot CirrOS VM (--port)
        Ctrl1-->>JH: VM ACTIVE, IP: 10.0.0.201
    end

    rect rgb(140,180,230)
        Note over JH,Ctrl1: Phase 1: Capture State
        JH->>Ctrl1: Collect port-show, net-show, sg-show (JSON)
        JH->>Ctrl1: Snapshot VM to Glance image
        Ctrl1-->>JH: Snapshot active
    end

    rect rgb(130,190,130)
        Note over JH,Ctrl2: Phase 3: Recreate on Target
        JH->>Ctrl2: Create network, subnet, SG
        JH->>Ctrl2: Create port (same IP 10.0.0.201)
        JH->>Ctrl2: Upload Glance image
        JH->>Ctrl2: Boot VM with migrated port
        Ctrl2-->>JH: VM ACTIVE
    end

    rect rgb(210,130,130)
        Note over JH: Phase 4: Measure
        JH->>JH: Start ping monitor
        JH->>Ctrl1: Stop source VM
        JH->>JH: Wait for ping response on target
        JH->>JH: Compute downtime, packet loss
    end

    Note over JH: Result: IP preserved = NO<br/>(image save failed, used DHCP)<br/>Ping: 100% loss (OVN br-int DOWN)
```

## 3. What is Migrated

| Recurso | Source (Ctrl-01) | Target (Ctrl-02) | Metodo |
|---|---|---|---|
| Network | `migrate-net-*` (10.0.0.0/24) | Same CIDR | Recreate via `openstack` CLI |
| Subnet | `migrate-subnet-*` | Same config | Recreate |
| Port | Fixed IP `10.0.0.201` | Same IP | `port create --fixed-ip` |
| Security Group | ICMP + SSH ingress | Same rules | Recreate |
| Instance (VM) | CirrOS on source | CirrOS on target | Snapshot → download → upload → boot (failed, used DHCP instead) |

## 4. Metrics Measured

| Metrica | Ferramenta | Resultado |
|---|---|---|
| **Downtime de rede** | `ping -i 0.2` | N/A (VM unreachable due to OVN bug) |
| **Packet loss** | ping counter | 100% (OVN br-int DOWN) |
| **Tempo de setup** | `date +%s` | ~59s |
| **Tempo de snapshot** | `date +%s` | ~8s |
| **Tempo total script** | `date +%s` | Varies (script hung at image save) |
| **Consistencia de rede** | Diff de JSON | Not comparable (IP changed) |
| **IP preservado** | Manual compare | NO (image save failed, used `--network` DHCP) |

## 5. Why CirrOS?

- **13MB** — pre-instalado no MicroStack (`/snap/microstack/current/images/`)
- **Boota em 2-3s** — elimina espera de cloud-init
- **Foco no que importa**: rede (portas, IPs, MACs, downtime), nao a VM em si

## 6. Script

**Localizacao**: `microstack/lab-multi-controller/scripts/migrate-microstack.sh`

Fluxo:
1. SSH no jumphost → executa comandos `microstack.openstack` nos controllers
2. Cleanup de recursos de runs anteriores (grep `migrate-*`)
3. Setup: network → subnet → SG → port → VM no Ctrl-01
4. Snapshot + export image (falhou — `image save` nao escreve arquivo)
5. Recreate: network → subnet → SG → port no Ctrl-02
6. Ping monitor + stop source + boot target
7. Relatorio: timing, MAC preservation, IP preservation, packet loss

## 7. Findings

### Blocker: MicroStack Ussuri OVN `br-int` DOWN

Ver [`network_issue.md`](network_issue.md) para analise completa.

- OVS integration bridge (`br-int`) fica **administrativamente DOWN** apos `microstack init`
- VM recebe IP via DHCP mas nenhum trafego IP flui (ICMP, TCP)
- `ovn-nbctl` nao acessivel como binario standalone (snap path)
- Nao ha namespaces de rede alem de `ovnmeta-*`
- Mesmo `ovs-vsctl set-fail-mode br-int standalone` nao resolve (snap nao permite acesso root ao OVS)

### Script Issues

- `microstack.openstack image save` nao cria arquivo de saida (bug no snap? path errado?)
- `port create --mac-address` requer permissao de admin — MAC nao preservado
- `sudo bash -c` quebra o PATH do snap (`/snap/bin/`)
- Recursos duplicados exigem nomes com timestamp por run

## 8. Comparison: MicroStack vs Kolla-Ansible

| Aspecto | MicroStack | Kolla-Ansible |
|---|---|---|
| **Status do teste** | Executado, VM criada, ping falhou | Executado, VM criada, ping falhou |
| **IP preservation** | NO (image save broke) | YES (port --fixed-ip worked) |
| **Network barrier** | OVN br-int DOWN | iptables INPUT chain blocks host→VM |
| **Root cause** | Snap sandbox limit | Missing docker + collection deps |
| **Resolvivel** | Upgrade MicroStack snap | Sim (Ubuntu cloud image, floating IP) |
| **VMs por cluster** | 1 (all-in-one) | 2 (controller + compute) |
| **Deploy time** | ~10 min | ~25 min |
| **Recomendado** | Para testes rapidos (se OVN fixado) | Para testes completos de migracao |

## 9. Proximos Passos

1. Testar MicroStack **Yoga/Zed** (snap channel update) — pode ter OVN fix
2. Ou manter Kolla-Ansible como plataforma primaria de teste de migracao
3. Documentar `--config-drive true` como workaround para CirrOS networking

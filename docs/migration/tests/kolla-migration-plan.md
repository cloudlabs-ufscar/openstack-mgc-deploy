# Kolla-Ansible Migration Test — Plan & Approach

Plano para substituir MicroStack por Kolla-Ansible no teste de migracao de rede.

---

## 1. Por que Kolla-Ansible?

MicroStack Ussuri tem `br-int` DOWN, bloqueando conectividade de rede das VMs (ver [`docs/migration/network_issue.md`](../docs/migration/network_issue.md)). Kolla-Ansible ja foi validado na MGC com o workaround `fail_mode=standalone` no `deploy.sh` (`kolla-ansible-mgc-deploy/deploy.sh:93`) e tem OVS/OVN funcional.

## 2. Abordagem: Jumphost + 2 Kolla All-in-One Clusters

Cada "controller" e uma **VM unica rodando Kolla-Ansible all-in-one** (todos os servicos Docker em um unico host). Isso:
- Minimiza VMs/recursos (1 jumphost + 2 Kolla VMs = 3 total)
- Elimina complexidade de multi-node (VIP, HAProxy)
- Foca no que importa: migracao de rede entre dois clusters OpenStack completos

```
┌──────────────────────────────────────────────────────┐
│                   Magalu Cloud MGC                    │
│                                                      │
│  ┌──────────────────────┐                            │
│  │    lab-jumphost      │  IP publico                │
│  │  (terraform+ansible) │  SSH aberto                │
│  └──────────┬───────────┘                            │
│             │                                         │
│     ┌───────┴───────┐                                │
│     │               │                                 │
│     ▼               ▼                                 │
│  ┌──────────┐  ┌──────────┐                          │
│  │ Kolla-01 │  │ Kolla-02 │  IPs privados            │
│  │ (Cluster │  │ (Cluster │                           │
│  │  Source) │  │  Target) │                           │
│  │          │  │          │                           │
│  │ Docker:  │  │ Docker:  │                           │
│  │ Nova     │  │ Nova     │                           │
│  │ Neutron  │  │ Neutron  │                           │
│  │ Cinder   │  │ Cinder   │                           │
│  │ Glance   │  │ Glance   │                           │
│  └──────────┘  └──────────┘                          │
│       │               │                               │
│       └─── Migracao ──┘                               │
│   (cold + network migration test)                     │
└──────────────────────────────────────────────────────┘
```

## 3. Como subir

### 3.1 Jumphost + 2 VMs (Terraform)

Mesmo padrao do `lab-multi-controller/main.tf`:
- Jumphost: IP publico, instala terraform + ansible
- 2 VMs Kolla: IPs privados, sem IP publico (acesso via jumphost)
- Security Groups: SSH do jumphost, all internal

### 3.2 Cloud-init das VMs Kolla

Cada VM Kolla precisa:
1. Ubuntu 24.04 base
2. Docker instalado
3. Kolla-Ansible instalado (pip install)
4. Configuracao basica: `globals.yml` com `kolla_base_distro: ubuntu`
5. `network_interface: "ens3"` (unica interface, sem `ens8`)
6. Script de bootstrap que roda `kolla-ansible deploy`

### 3.3 Provisionamento automatico (systemd no jumphost)

Igual ao MicroStack, mas o script de provisionamento:
1. Cria a VM Kolla via terraform na MGC
2. Aguarda cloud-init
3. SSHs na VM e:
   - Configura `/etc/kolla/globals.yml`
   - Roda `kolla-genpwd`
   - Roda `kolla-ansible -i all-in-one bootstrap-servers`
   - Roda `kolla-ansible -i all-in-one prechecks`
   - Roda `kolla-ansible -i all-in-one deploy`
   - Aplica fix `fail_mode=standalone`
   - Roda `kolla-ansible post-deploy`

## 4. Script de Migracao

O script de migracao (`migrate-kolla.sh`):
1. Source admin credentials de ambos clusters
2. Criar VM de teste no Cluster-01 (CirrOS ou Ubuntu cloud image)
3. Capturar IP, MAC, port details
4. Exportar imagem (Glance download) se necessario
5. Recriar network + subnet + SG + port no Cluster-02
6. Boot VM no Cluster-02
7. Medir downtime (ping)

## 5. Diferencas do MicroStack

| Aspecto | MicroStack | Kolla-Ansible |
|---|---|---|
| CLI | `microstack.openstack` | `openstack` (via venv ou /etc/kolla/admin-openrc.sh) |
| Services | Snap + systemd | Docker containers |
| Credentials | `snap get microstack config.credentials.keystone-password` | `/etc/kolla/admin-openrc.sh` |
| OVS fix | Nao aplicado (br-int DOWN) | `fail_mode=standalone` no deploy.sh |
| Network | 1 NIC | 1 NIC (all-in-one) ou 2 NICs (multi-node) |
| CirrOS | Pre-instalado | Precisamos baixar/upload |
| Admin access | `microstack.openstack` prefix | `source /etc/kolla/admin-openrc.sh` |

## 6. Proximos Passos

1. **Criar `lab-kolla-multi-controller/`**: Terraform + cloud-init pra jumphost + 2 Kolla all-in-one VMs
2. **Adaptar provision script**: Criar script que deploya Kolla-Ansible em cada VM
3. **Adaptar migrate script**: `migrate-kolla.sh` usando `openstack` CLI com `/etc/kolla/admin-openrc.sh`
4. **Testar**: Deploy -> criar VM de teste -> verificar ping funciona -> migrar -> medir

## 7. Estimativa de Tempo

| Etapa | Tempo estimado |
|---|---|
| Terraform (criar VMs) | ~5 min |
| Cloud-init (Docker + Kolla install) | ~5 min |
| Kolla-Ansible bootstrap + deploy | ~15 min |
| Post-deploy + OVS fix | ~2 min |
| **Total por cluster** | **~25 min** |
| Criar VM de teste | ~2 min |
| Migrar + medir | ~5 min |
| **Total do teste** | **~60 min** |

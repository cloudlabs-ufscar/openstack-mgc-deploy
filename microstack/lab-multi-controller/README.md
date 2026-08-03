# Lab Multi-Controller (Jumphost + N Single-Node OpenStack)

Laboratory setup with a single jumphost VM (public IP) that provisions and manages multiple single-node OpenStack (MicroStack) instances on Magalu Cloud.
Controllers use private IPs only -- no public IP quota consumed. All access goes through the jumphost.

## Architecture

```
                        Internet
                            │
                            ▼
                 ┌────────────────────┐
                 │    lab-jumphost    │  Public IP
                 │ (terraform+ansible)│  SSH open
                 └────────┬───────────┘
                          │ Private IP (default VPC)
            ┌─────────────┼─────────────┐
            ▼             │             ▼
   ┌──────────────┐       │    ┌──────────────┐
   │ controller-01│◄──────┘    │ controller-02│
   │ (MicroStack) │            │ (MicroStack) │
   │ private IP   │            │ private IP   │
   └──────────────┘            └──────────────┘
```

## Prerequisites

- [Magalu Cloud](https://magalu.cloud/) account + API Key with scopes:
  - Virtual Machine [Read/Write]
  - VPC [Read/Write]
  - Network [Read/Write]
- [Terraform](https://www.terraform.io/) installed locally
- SSH Key registered in your MGC dashboard

## Step by step

### 1. Configure credentials

```bash
cp .env.sample .env
```

Edit `.env`:

```bash
export TF_VAR_mgc_api_key=YOUR_API_KEY
export TF_VAR_ssh_key_name=YOUR_SSH_KEY_NAME
export SSH_KEY_PATH=~/.ssh/id_rsa          # path to your private key
export TF_VAR_controller_count=2           # default: 2
```

### 2. Deploy

```bash
source .env
terraform init
./deploy.sh
```

What happens:

1. Terraform creates the **jumphost** (public IP) + Security Groups
2. `deploy.sh` waits for SSH, then triggers controller provisioning on the jumphost
3. The jumphost creates N controller VMs via Terraform (private IPs only)
4. Each controller installs MicroStack via cloud-init (~10 min)

> Running `terraform apply` directly creates only the jumphost. Use `./deploy.sh` to also trigger controller provisioning.

### 3. Monitor controller setup

From your local machine:

```bash
JUMPHOST=$(terraform output -raw jumphost_public_ip)

# Check provisioning status
ssh ubuntu@$JUMPHOST 'cat /opt/lab/lab-hosts.txt'

# Watch MicroStack install on a controller (~10 min)
CTRL_IP=$(ssh ubuntu@$JUMPHOST "head -1 /opt/lab/lab-hosts.txt | grep -oP 'priv=\K[\d.]+'")
ssh -J ubuntu@$JUMPHOST ubuntu@$CTRL_IP 'tail -f /var/log/cloud-init-output.log'
```

### 4. Access controllers

From the jumphost (uses auto-generated lab-key, no user key needed on jumphost):

```bash
ssh ubuntu@$JUMPHOST
ssh -F /opt/lab/ssh_config lab-controller-01
```

Or from your local machine using a ProxyJump:

```bash
JUMPHOST=$(terraform output -raw jumphost_public_ip)
CTRL_IP=$(ssh $SSH_OPTS ubuntu@$JUMPHOST "head -1 /opt/lab/lab-hosts.txt | grep -oP 'priv=\K[\d.]+'")
ssh $SSH_OPTS -J ubuntu@$JUMPHOST ubuntu@$CTRL_IP
```

### 5. Using OpenStack on a controller

Each controller is an independent MicroStack single-node deployment.

```bash
ssh -F /opt/lab/ssh_config lab-controller-01

# Get admin password
sudo snap get microstack config.credentials.keystone-password

# OpenStack CLI (use 'microstack.openstack' prefix)
microstack.openstack server list
microstack.openstack image list
microstack.openstack flavor list

# Launch a test instance
microstack.openstack server create \
  --image cirros \
  --flavor m1.tiny \
  --key-name ssh-key \
  --security-group lab-secgroup \
  --net test \
  my-first-vm

# Access Horizon via SSH tunnel (from your local machine)
# ssh -L 8443:<CONTROLLER_PRIVATE_IP>:443 ubuntu@<JUMPHOST_IP>
# Then open http://localhost:8443
```

### 6. Add more controllers

On the jumphost:

```bash
# Add 1 more controller (becomes controller-03)
provision-controllers.sh 1 3

# Add 3 more controllers starting from index 5
provision-controllers.sh 3 5
```

Then regenerate SSH config and inventory:

```bash
lab-ssh-config
lab-inventory
```

The script is idempotent -- already provisioned controllers are skipped.

### 7. Ansible inventory

On the jumphost:

```bash
lab-inventory
cat /opt/lab/inventory
```

This generates an Ansible inventory using controller private IPs. Run playbooks from the jumphost:

```bash
ansible -i /opt/lab/inventory all -m ping
```

### 8. Tear down

```bash
./destroy.sh
```

This removes controllers first (via Terraform on the jumphost), then destroys the jumphost + Security Groups locally.

## Jumphost quick reference

| Command | Description |
|---|---|
| `provision-controllers.sh <n> [start]` | Create additional controllers |
| `lab-inventory` | Generate `/opt/lab/inventory` for Ansible |
| `lab-ssh-config` | Generate `/opt/lab/ssh_config` with SSH shortcuts |
| `cat /opt/lab/lab-hosts.txt` | List known controllers |
| `cloud-init status --wait` | Wait for MicroStack install on jumphost |

## How it works

1. `main.tf` creates only the jumphost + Security Groups (no custom VPC -- uses default MGC VPC)
2. Jumphost cloud-init installs Terraform, Ansible, and MGC CLI
3. Jumphost cloud-init writes a provisioning script that uses Terraform to create controller VMs
4. `deploy.sh` triggers the provisioning script after cloud-init completes
5. Controller cloud-init installs MicroStack (snap) and configures OpenStack

## File structure

```
lab-multi-controller/
├── main.tf                         # Jumphost + Security Groups
├── variables.tf                    # API key, SSH key, controller count
├── outputs.tf                      # Jumphost IPs
├── cloud-init-jumphost.sh.tmpl     # Jumphost cloud-init (tools + provisioning script)
├── cloud-init-controller.yaml      # Controller cloud-init (MicroStack)
├── deploy.sh                       # terraform apply + triggers provisioning
├── destroy.sh                      # Full teardown
├── .env.sample                     # Credentials template
└── .gitignore
```

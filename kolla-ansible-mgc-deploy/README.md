# openstack-mgc-deploy

Automation scripts for deploying OpenStack in Magalu Cloud
Single-node deployment in the `microstack-mgc-deploy` folder

For multi-node deployment:

```
# Install Python dependencies
sudo apt update
sudo apt install python3-venv python3-dev libffi-dev gcc libssl-dev

# Create and activate a virtual environment
python3 -m venv ~/kolla-venv
source ~/kolla-venv/bin/activate

# Install Ansible and Kolla-Ansible
pip install -U pip
pip install ansible
pip install git+https://opendev.org/openstack/kolla-ansible@master
kolla-ansible install-deps

# Create Kolla-Ansible configuration
sudo mkdir -p /etc/kolla
sudo chown $USER:$USER /etc/kolla
cp -r ~/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
```

Create and populate your .env file, then:

```
tofu init
source .env
tofu plan
tofu apply
```

This creates the VMs and the `multinode` Ansible file

To find out the network interfaces available in the VMs:

```
ssh -o StrictHostKeyChecking=no ubuntu@$(tofu output -json cluster_ips | jq -r '.controller') "ip -br a"
```

In this deployment, we have `ens3` and `ens7` available. Access `/etc/kolla/globals.yml` and edit the `network_interface` to `"ens3"` and `neutron_external_interface` property to `"ens7"`.
_(Note: The `./deploy.sh` script will automatically handle configuring the `kolla_internal_vip_address` and will disable `haproxy` and `proxysql` to support this single-node controller architecture without port collisions on Magalu Cloud.)_

Finally, you can run:

`./deploy.sh`

To get the credentials:

```
kolla-ansible post-deploy -i ./multinode
cat /etc/kolla/admin-openrc.sh
cat /etc/kolla/passwords.yml | grep keystone_admin_password
```

keystone_admin_password can be used to log into the Horizon web interface. Default username is admin.

To manage this OpenStack installation via CLI from your local machine, you must update the generated OpenRC file to use the Controller's Public IP instead of its internal private IP.

1. Open `/etc/kolla/admin-openrc.sh` and replace the internal IP in `OS_AUTH_URL` with your Controller's Public IP.

Then, install the client and access the cloud:

```bash
# 1. Activate the Kolla Virtual Environment
source ~/kolla-venv/bin/activate

# 2. Install the OpenStack CLI client
pip install python-openstackclient

# 3. Source your authentication variables
source /etc/kolla/admin-openrc.sh

# 4. Verify connection
openstack service list
openstack hypervisor list
```

# Documenting Hardships on Kolla-Ansible overcloud deployment

-> Read [docs/issues.md](docs/issues.md)

terraform {
  required_providers {
    mgc = {
      source = "magalucloud/mgc"
    }
  }
}

provider "mgc" {
  api_key = var.mgc_api_key
  region  = "br-ne1"
}

# Provision 3 instances using a set
resource "mgc_virtual_machine_instances" "openstack_nodes" {
  for_each             = toset(["controller", "compute-01", "compute-02"])
  name                 = "kolla-${each.key}"
  machine_type         = "BV4-16-100"
  image                = "cloud-ubuntu-24.04 LTS"
  ssh_key_name         = var.ssh_key_name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    cat << 'NETPLAN' > /etc/netplan/99-secondary-nic.yaml
    network:
      version: 2
      ethernets:
        ens8:
          dhcp4: false
          dhcp6: false
          optional: true
    NETPLAN
    chmod 600 /etc/netplan/99-secondary-nic.yaml
    netplan apply
    ip link set ens8 up
  EOF
  )
}

# Create a security group to allow SSH access
resource "mgc_network_security_groups" "ssh_sg" {
  name        = "kolla-ssh-sg"
  description = "Security group for SSH access"
}

# Add SSH rule to the security group
resource "mgc_network_security_groups_rules" "ssh_rule" {
  description       = "Allow SSH access"
  direction         = "ingress"
  ethertype         = "IPv4"
  port_range_min    = 22
  port_range_max    = 22
  protocol          = "tcp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = mgc_network_security_groups.ssh_sg.id
}

# Allow Kolla nodes to talk to each other (Ingress all from internal subnets, or easily 0.0.0.0/0 for lab)
resource "mgc_network_security_groups_rules" "ingress_all_lab" {
  description       = "Allow all ingress traffic for Kolla services"
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = mgc_network_security_groups.ssh_sg.id
}

# Attach security group to the primary interface of each VM
resource "mgc_network_security_groups_attach" "ssh_sg_attach" {
  for_each          = mgc_virtual_machine_instances.openstack_nodes
  security_group_id = mgc_network_security_groups.ssh_sg.id
  interface_id      = each.value.network_interface_id
}

# Create secondary network interfaces
resource "mgc_network_vpcs_interfaces" "secondary_interfaces" {
  for_each      = mgc_virtual_machine_instances.openstack_nodes
  name          = "${each.value.name}-secondary-nic"
  vpc_id        = each.value.vpc_id
  anti_spoofing = false
}

# Attach secondary interfaces to the instances
resource "mgc_virtual_machine_interface_attach" "secondary_attachments" {
  for_each     = mgc_virtual_machine_instances.openstack_nodes
  instance_id  = each.value.id
  interface_id = mgc_network_vpcs_interfaces.secondary_interfaces[each.key].id
}

# Manage public IPv4 addresses as Terraform resources so they are deleted on destroy.
resource "mgc_network_public_ips" "openstack_node_public_ips" {
  for_each    = mgc_virtual_machine_instances.openstack_nodes
  description = "Public IPv4 for ${each.key}"
  vpc_id      = each.value.vpc_id
}

resource "mgc_network_public_ips_attach" "openstack_node_public_ips" {
  for_each     = mgc_virtual_machine_instances.openstack_nodes
  public_ip_id = mgc_network_public_ips.openstack_node_public_ips[each.key].id
  interface_id = each.value.network_interface_id
}

# Output the IPs mapped to their roles so you can easily populate your Ansible inventory
output "cluster_ips" {
  value = {
    for name, ip in mgc_network_public_ips.openstack_node_public_ips :
    name => ip.public_ip
  }
}

# This tells Terraform to write a file named 'multinode' in your current directory
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/multinode"

  # The <<-EOT syntax allows for multi-line string templates
  content = <<-EOT
    [control]
    ${mgc_network_public_ips.openstack_node_public_ips["controller"].public_ip} ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

    [network]
    ${mgc_network_public_ips.openstack_node_public_ips["controller"].public_ip} ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

    [loadbalancer]
    ${mgc_network_public_ips.openstack_node_public_ips["controller"].public_ip} ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

    [compute]
    ${mgc_network_public_ips.openstack_node_public_ips["compute-01"].public_ip} ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    ${mgc_network_public_ips.openstack_node_public_ips["compute-02"].public_ip} ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

    [monitoring]
    ${mgc_network_public_ips.openstack_node_public_ips["controller"].public_ip} ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

    [storage]
    ${mgc_network_public_ips.openstack_node_public_ips["controller"].public_ip} ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

    [baremetal]
  EOT
}


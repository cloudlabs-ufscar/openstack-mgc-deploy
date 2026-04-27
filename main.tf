terraform {
  required_providers {
    mgc = {
      source = "magalucloud/mgc"
    }
  }
}

provider "mgc" {
  api_key = var.mgc_api_key
  region  = "br-se1"
}

# Provision 3 instances using a set
resource "mgc_virtual_machine_instances" "openstack_nodes" {
  for_each             = toset(["controller", "compute-01", "compute-02"])
  name                 = "kolla-${each.key}"
  machine_type         = "BV4-16-100"
  image                = "cloud-ubuntu-24.04 LTS"
  ssh_key_name         = var.ssh_key_name
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


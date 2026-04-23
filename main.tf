terraform {
  required_providers {
    mgc = {
      source  = "magalucloud/mgc"
      version = "~> 0.46.0"
    }
  }
}

provider "mgc" {
  api_key = var.mgc_api_key
  region  = "br-se1" 
}

variable "mgc_api_key" {
  type        = string
  sensitive   = true
}

variable "ssh_key_name" {
  type        = string
}

# Provision 3 instances using a set
resource "mgc_virtual_machine_instances" "openstack_nodes" {
  for_each = toset(["controller", "compute-01", "compute-02"])

  name = "kolla-${each.key}"
  
  machine_type = {
    name = "BV4-16-100" 
  }
  
  image = {
    name = "ubuntu-22.04"
  }
  
  ssh_key_name = var.ssh_key_name 
}

# Output the IPs mapped to their roles so you can easily populate your Ansible inventory
output "cluster_ips" {
  value = {
    for name, node in mgc_virtual_machine_instances.openstack_nodes : 
    name => node.network_interfaces[0].public_ipv4
  }
}
terraform {
  required_providers {
    mgc = {
      source = "magalucloud/mgc"
    }
  }
}

provider "mgc" {
  api_key = var.mgc_api_key
  region = "br-se1"
}

variable "mgc_api_key" {
  type        = string
  sensitive   = true
}

variable "ssh_key_name" {
  type        = string
}

resource "mgc_virtual_machine_instances" "microstack_test" {
  name = "microstack_test"
  machine_type = "BV4-16-100"
  image = "cloud-ubuntu-24.04 LTS"
  ssh_key_name = var.ssh_key_name
  allocate_public_ipv4 = true
  user_data = base64encode(file("${path.module}/cloud-init.yaml"))
}

output "vm_public_ip" {
  value = mgc_virtual_machine_instances.microstack_test.ipv4
}
terraform {
  required_providers {
    mgc = {
      source = "magalucloud/mgc"
    }
  }
}

provider "mgc" {
  region = var.region
}

variable "region" {
  description = "MGC region where the VM will be created."
  type        = string
  default     = "br-se1"
}

variable "vm_name" {
  description = "Name of the VM instance for the MicroStack host."
  type        = string
  default     = "microstack-test"
}

variable "ssh_key_name" {
  description = "Existing MGC SSH key name to inject into the VM."
  type        = string
}

variable "microstack_keypair_name" {
  description = "OpenStack keypair name created inside MicroStack."
  type        = string
  default     = "my-local-key"
}

resource "mgc_virtual_machine_instances" "microstack_test" {
  name = var.vm_name
  machine_type = "BV4-16-100"
  image = "cloud-ubuntu-24.04 LTS"
  ssh_key_name = var.ssh_key_name
  allocate_public_ipv4 = true
  user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    microstack_keypair_name = var.microstack_keypair_name
  }))
}

output "vm_public_ip" {
  value = mgc_virtual_machine_instances.microstack_test.ipv4
}

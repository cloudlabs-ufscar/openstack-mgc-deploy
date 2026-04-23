terraform {
  required_providers {
    mgc = {
      source = "magalucloud/mgc"
    }
  }
}

provider "mgc" {
  api_key = "d476e661-0e5a-494d-b359-57d1f50a2534"
  region = "br-se1"
}

resource "mgc_virtual_machine_instances" "microstack_test" {
  name = "microstack_test"
  machine_type = "BV4-16-100"
  image = "cloud-ubuntu-24.04 LTS"
  ssh_key_name = "lucas-vvb"
  allocate_public_ipv4 = true
  user_data = base64encode(file("${path.module}/cloud-init.yaml"))
}

output "vm_public_ip" {
  value = mgc_virtual_machine_instances.microstack_test.ipv4
}
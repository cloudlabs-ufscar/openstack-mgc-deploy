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

# --- Security Groups ---

resource "mgc_network_security_groups" "jumphost_sg" {
  name        = "jumphost-sg"
  description = "Jumphost - SSH from anywhere"
}

resource "mgc_network_security_groups_rules" "jumphost_ssh" {
  security_group_id = mgc_network_security_groups.jumphost_sg.id
  description       = "Allow SSH from anywhere"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "mgc_network_security_groups" "controller_sg" {
  name        = "controller-sg"
  description = "Controllers - restricted SSH + internal OpenStack"
}

# Allow all traffic from private IP ranges (covers jumphost and inter-controller)
resource "mgc_network_security_groups_rules" "controller_internal_all" {
  security_group_id = mgc_network_security_groups.controller_sg.id
  description       = "Internal OpenStack services"
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
}

# --- Jumphost VM (uses default VPC; provisions controllers on boot) ---

resource "mgc_virtual_machine_instances" "jumphost" {
  name                     = "lab-jumphost"
  machine_type             = "BV4-16-100"
  image                    = "cloud-ubuntu-24.04 LTS"
  ssh_key_name             = var.ssh_key_name
  allocate_public_ipv4     = true
  creation_security_groups = [mgc_network_security_groups.jumphost_sg.id]

  user_data = base64encode(templatefile("${path.module}/cloud-init-jumphost.sh.tmpl", {
    mgc_api_key       = var.mgc_api_key
    ssh_key_name      = var.ssh_key_name
    controller_count  = var.controller_count
    controller_sg_id  = mgc_network_security_groups.controller_sg.id
    vpc_id            = ""
    controller_cloud_init_b64 = base64encode(file("${path.module}/cloud-init-controller.yaml"))
  }))
}

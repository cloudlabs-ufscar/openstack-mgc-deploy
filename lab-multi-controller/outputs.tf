output "jumphost_public_ip" {
  description = "Public IP of the jumphost (SSH access point)"
  value       = mgc_virtual_machine_instances.jumphost.ipv4
}

output "jumphost_private_ip" {
  description = "Private IP of the jumphost"
  value       = mgc_virtual_machine_instances.jumphost.local_ipv4
}

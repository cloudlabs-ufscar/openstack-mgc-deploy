variable "cluster_prefix" {
  type    = string
  default = "kolla"
}

variable "mgc_api_key" {
  type      = string
  sensitive = true
}

variable "ssh_key_name" {
  type = string
}

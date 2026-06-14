
variable "mgc_api_key" {
  type      = string
  sensitive = true
}

variable "ssh_key_name" {
  type = string
}

variable "controller_count" {
  type        = number
  default     = 2
  description = "Number of single-node OpenStack controllers to deploy"
}

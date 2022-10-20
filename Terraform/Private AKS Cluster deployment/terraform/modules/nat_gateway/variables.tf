variable location {
  description = "Location where Firewall will be deployed"
  type        = string
}

variable resource_group {
  description = "Resource group name"
  type        = string
}

variable pip_prefix_name {
  description = "Firewall public IP prefix name"
  type        = string
  default     = "pip-prefix-nat-gw"
}

variable nat_gw_name {
  description = "NAT gateway name"
  type        = string
}

variable subnet_id {
  description = "NAT gateway Subnet ID to be associated with"
  type        = string
}
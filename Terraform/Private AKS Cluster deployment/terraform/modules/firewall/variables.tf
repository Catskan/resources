variable resource_group {
  description = "Resource group name"
  type        = string
}

variable location {
  description = "Location where Firewall will be deployed"
  type        = string
}

variable pip_name {
  description = "Firewall public IP name"
  type        = string
  default     = "ip-firewall"
}

variable fw_name {
  description = "Firewall name"
  type        = string
}

variable fw_policy_name {
  description = "Firewall Policy name"
  type        = string
}

variable fw_rcg_name {
  description = "Firewall policy rule collection group name"
  type        = string
}


variable subnet_id {
  description = "Subnet ID"
  type        = string
}

variable rabbitmq_fqdn {
  description = "The FQDN of the rabbitmq server used in this deployment"
  type        = string
}

variable subnet_cluster_space {
  description = "address space for the cluster"
  type = string
}
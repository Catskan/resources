variable resource_group {
  description = "Resource group where RouteTable will be deployed"
  type        = string
}

variable location {
  description = "Location where RouteTable will be deployed"
  type        = string
}

variable rt_name {
  description = "RouteTable name"
  type        = string
}

variable r_name {
  description = "AKS route name"
  type        = string
}

variable firewall_private_ip {
  description = "Firewall private IP"
  type        = string
}
variable firewall_public_ip {
  description = "Firewall public IP"
  type        = string
}

variable subnet_ids {
  description = "AKS subnet IDs that need to be associated with the route table"
  type        = map
}
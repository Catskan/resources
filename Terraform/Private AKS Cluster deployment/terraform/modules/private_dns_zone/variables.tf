variable private_dns_zone_name {
  description = "Name of the private dns zone where you want to add a record for the newly created private endpoint. This zone will be created."
  type = string
}
variable resource_group_name {
  description = "Resource group where the private endpoint will live"
  type = string
}

variable private_dns_vnet_links {
  description = "Map of VNET ids that should have access to this DNS zone and entry. In our case, always Hub and Kube vnets so we resolve private names from the jumpbox, etc."
  type = map
}

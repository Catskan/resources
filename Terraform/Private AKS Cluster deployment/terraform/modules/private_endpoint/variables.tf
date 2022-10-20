variable name {
  description = "Name of the private endpoint. This will end up being the DNS common name, too."
  type = string
}

variable resource_group_name {
  description = "Resource group where the private endpoint will live"
  type = string
}

variable location {
  description = "Location of the private endpoint"
  type = string
}

variable subnet_id {
  description = "Which subnet should this private endpoint be provided access"
  type = string
}

variable private_connection_resource_id {
  description = "The id of the resource to which you want to connect privately"
  type = string
}

variable subresource_names {
  description = "Some resources require subresource names to properly identify them"
  type = list(string)
  default = []
}

variable private_dns_zone_id {
  description = "Id of the private DNS zone created for the databases private link"
}
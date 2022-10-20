variable resource_group {
  type = string
}

variable location {
  type = string
}

variable subnet_id {
  description = "ID of subnet where jumpbox VM will be installed"
  type        = string
}

variable vm_user {
  description = "Jumpbox VM user name"
  type        = string
  default     = "azureuser"
}

variable admin_group_ids {
  description = "The list of AAD group ids for those who can login as admins for this VM"
  type = list(string)
}

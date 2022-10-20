variable resource_group {
  type = string
}

variable location {
  type = string
}

variable subnet_id {
  description = "ID of subnet where agent VM will be installed"
  type        = string
}

variable agent_user {
  description = "Agent VM user name"
  type        = string
  default     = "azureuser"
}

variable admin_group_ids {
  description = "The list of AAD group ids for those who can login as admins for this VM"
  type = list(string)
}

variable public_ip_name {
  description = "Public IP for Azure DevOPS Agent"
  type = string
}

variable network_security_group_name {
  description = "Security group name assigned to the agent vm"
  type = string
}

variable network_interface_name {
  description = "Azure NIC assigned to the agent vm"
  type = string
}

variable network_interface_configuration {
  description = "Configuration of the agent network interface"
  type = string
}

variable devops_agent_name {
  description = "Name of the agent vm"
  type = string
}

variable devops_agent_osDisk_Name {
  description = "OS disk name of the devops agent vm"
}
output "ssh_command_jumpbox" {
  value = "ssh ${module.jumpbox.jumpbox_username}@${module.jumpbox.jumpbox_ip}"
}

output "jumpbox_password" {
  description = "Jumpbox Admin Password"
  value       = module.jumpbox.jumpbox_password
}

output "ssh_command_agent" {
 value = "ssh ${module.devops_agent.agent_username}@${module.devops_agent.agent_ip}"
}

output "agent_password" {
 description = "Agent Admin Password"
 value       = module.devops_agent.agent_password
}

output "logstorage_name" {
  description = "The name of the storage account that will store logs"
  value = azurerm_storage_account.logstorage.name
}

output "logstorage_accesskey" {
  description = "The access key to use for deploying Fluent-Bit"
  value       = azurerm_storage_account.logstorage.primary_access_key
}

output "loganalitycs_workspace" {
  description = "Log analytics workspace created for AKS & SQL DB backups"
  value       = module.log_analytics.name
}

output "vaults_rg_name"{
  description = "name of the resource group for the clients vaults"
  value = azurerm_resource_group.vaults.name
}

output "ingress_public_ip"{
  description = "name of the resource group for the clients vaults"
  value = azurerm_public_ip.ingress_lb_public_ip.ip_address
}

#### KEYCLOAK POSTGRES RELATED VARIABLES ####

output "cluster1-kc-pg01-fqdn"{
  description = "FQDN for the resources to connect to the keycloak database"
  value = azurerm_postgresql_flexible_server.cluster1kcpg01.fqdn
}
output "cluster1-kc-pg01-login"{
  description = "FQDN for the resources to connect to the keycloak database"
  value = azurerm_postgresql_flexible_server.cluster1kcpg01.administrator_login
}
output "cluster1-kc-pg01-password"{
  description = "FQDN for the resources to connect to the keycloak database"
  value = random_password.kc_pgadminpassword.result
}

#### ANPM POSTGRES RELATED VARIABLES ####

output "cluster1-anpm-pg01-fqdn"{
  description = "FQDN for the resources to connect to the keycloak database"
  value = azurerm_postgresql_flexible_server.cluster1anpmpg01.fqdn
}
output "cluster1-anpm-pg01-login"{
  description = "FQDN for the resources to connect to the keycloak database"
  value = azurerm_postgresql_flexible_server.cluster1anpmpg01.administrator_login
}
output "cluster1-anpm-pg01-password"{
  description = "FQDN for the resources to connect to the keycloak database"
  value = random_password.anpm_pgadminpassword.result
}
output "name" {
  description = "Log analytics workspace created for AKS & SQL DB logs"
  value       = azurerm_log_analytics_workspace.la.name
}

output "rg_name" {
  description = "The name of the new resource group"
  value = azurerm_resource_group.larg.name
}

output "rg_location" {
  description = "The location of the new resource group"
  value = azurerm_resource_group.larg.location
}

output "id" {
  description = "The id for the newly created workspace"
  value = azurerm_log_analytics_workspace.la.id
}
resource "azurerm_resource_group" "larg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_log_analytics_workspace" "la" {
  name                = var.name
  location            = azurerm_resource_group.larg.location
  resource_group_name = azurerm_resource_group.larg.name
  sku                 = var.sku
  retention_in_days   = var.retention
}
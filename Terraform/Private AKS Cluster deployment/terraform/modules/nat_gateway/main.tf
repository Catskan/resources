resource "azurerm_public_ip_prefix" "natgw-pip-prefix" {
  name                = var.pip_prefix_name
  location            = var.location
  resource_group_name = var.resource_group
  prefix_length       = 30
}

resource "azurerm_nat_gateway" "nat-gateway" {
  name                    = var.nat_gw_name
  location                = var.location
  resource_group_name     = var.resource_group
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
}

resource "azurerm_subnet_nat_gateway_association" "nat-gw-sn-association" {
  subnet_id      = var.subnet_id
  nat_gateway_id = azurerm_nat_gateway.nat-gateway.id
}

resource "azurerm_nat_gateway_public_ip_prefix_association" "nat-gw-pip-prefix-association" {
  nat_gateway_id      = azurerm_nat_gateway.nat-gateway.id
  public_ip_prefix_id = azurerm_public_ip_prefix.natgw-pip-prefix.id
}
# Create the private dns zone for a service
resource "azurerm_private_dns_zone" "private_dns" {
   name                = var.private_dns_zone_name
   resource_group_name = var.resource_group_name
}

# Create the private link for the desired vnets in the DNS private Zone
resource "azurerm_private_dns_zone_virtual_network_link" "dns_link" {
  for_each = var.private_dns_vnet_links
  name                  = each.key
  resource_group_name   = azurerm_private_dns_zone.private_dns.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.private_dns.name
  virtual_network_id    = each.value
}
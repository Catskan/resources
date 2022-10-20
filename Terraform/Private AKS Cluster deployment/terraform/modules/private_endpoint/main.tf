resource "azurerm_private_endpoint" "private_endpoint" {
  name = var.name
  resource_group_name = var.resource_group_name
  location = var.location
  subnet_id = var.subnet_id
  private_dns_zone_group {
    name = var.name
    private_dns_zone_ids = [ var.private_dns_zone_id ]
  }
  private_service_connection {
    name = "private-endpoint-connection-${var.name}"
    is_manual_connection = false
    private_connection_resource_id = var.private_connection_resource_id
    subresource_names = var.subresource_names
  }
}

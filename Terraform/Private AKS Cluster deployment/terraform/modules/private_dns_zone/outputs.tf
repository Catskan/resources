output "id" {
  description = "DNS Private zone ID"
  value = azurerm_private_dns_zone.private_dns.id
}

output "name" {
  description = "DNS private zone name"
  value       = var.private_dns_zone_name
}
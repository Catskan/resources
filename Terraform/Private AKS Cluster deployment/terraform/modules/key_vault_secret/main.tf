resource "azurerm_key_vault_secret" "secret" {
  name         = var.secret.name
  value        = var.secret.value
  key_vault_id = var.keyvault_id
}
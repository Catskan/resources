output "agent_ip" {
  description = "Agent VM IP"
  value       = azurerm_linux_virtual_machine.devops_agent.public_ip_address
}

output "vm_id" {
  description = "agent VM ID"
  value       = azurerm_linux_virtual_machine.devops_agent.id
}

output "agent_username" {
  description = "Agent VM username"
  value       = var.agent_user
}

output "agent_password" {
  description = "Agent VM admin password"
  value       = random_password.adminpassword.result
}

output "agent_identity_sp_id" {
  description = "service principal Id of the system assigned managed identity"
  value       = azurerm_linux_virtual_machine.devops_agent.identity.0.principal_id
}

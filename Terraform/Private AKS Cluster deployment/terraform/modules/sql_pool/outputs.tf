output "sqlserver_id" {
  description = "Id of the created SQL server"
  value       = azurerm_mssql_server.sqlserver.id
}
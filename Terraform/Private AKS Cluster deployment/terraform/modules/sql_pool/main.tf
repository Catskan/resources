resource "azurerm_mssql_server" "sqlserver" {
  name                         = var.elastic_pool.sql_server_name
  resource_group_name          = var.elastic_pool.resource_group_name
  location                     = var.elastic_pool.location
  version                      = var.elastic_pool.version
  administrator_login          = var.elastic_pool.admin_login
  administrator_login_password = var.elastic_pool.admin_password
  minimum_tls_version          = "1.2"
  tags = {
      "environment" = var.elastic_pool.environment
  }
}

resource "azurerm_mssql_elasticpool" "elasticpool" {
  name                = var.elastic_pool.elastic_pool_name
  resource_group_name = var.elastic_pool.resource_group_name
  location            = var.elastic_pool.location
  server_name         = var.elastic_pool.sql_server_name
  max_size_gb         = var.elastic_pool.max_size_gb
  tags = {
      "environment" = var.elastic_pool.environment
  }

  sku {
    name     = var.elastic_pool.elastic_pool_sku
    tier     = var.elastic_pool.elastic_pool_tier
    capacity = var.elastic_pool.total_capacity
  }

  per_database_settings {
    min_capacity = var.elastic_pool.min_per_db
    max_capacity = var.elastic_pool.max_per_db
  }

  depends_on              = [azurerm_mssql_server.sqlserver]
}
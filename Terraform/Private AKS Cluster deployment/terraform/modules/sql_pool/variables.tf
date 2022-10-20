variable elastic_pool {
    type = object({
        sql_server_name      = string
        resource_group_name  = string
        location             = string
        version              = string
        admin_login          = string
        admin_password       = string
        elastic_pool_name    = string 
        elastic_pool_sku     = string
        elastic_pool_tier    = string
        max_size_gb          = number
        total_capacity       = number
        min_per_db           = number
        max_per_db           = number
        environment          = string
      })
    }
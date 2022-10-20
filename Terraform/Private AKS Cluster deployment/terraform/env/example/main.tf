terraform {
  required_version = ">= 0.13"
  required_providers {
    azurerm = "=2.71.0"
  }
  #
  # THe backend storage for the teraform state is configured with the terraform init command - see README.md for details
  #
  backend "azurerm" { }
}

provider "azurerm" {
  subscription_id = var.subscriptionid
  features {}
}

resource "azurerm_resource_group" "hub" {
  name     = "${var.prefix}-${var.hub_resource_group_name}"
  location = var.location
}

resource "azurerm_resource_group" "spoke" {
  name     = "${var.prefix}-${var.aks_resource_group_name}"
  location = var.location
}

resource "azurerm_resource_group" "vaults" {
  name     = "${var.prefix}-${var.vaults_resource_group_name}"
  location = var.location
}

resource "azurerm_resource_group" "postgres" {
  name     = "${var.prefix}-${var.postgres_resource_group_name}"
  location = var.location
}

module "hub_vnet" {
  source              = "../../modules/vnet"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  vnet_name           = var.hub_vnet_name
  address_space       = ["10.100.0.0/16"]
  subnets = [
    {
      # DO NOT change this name; *must* be called AzureFirewallSubnet
      name : "AzureFirewallSubnet"
      address_prefixes : ["10.100.50.0/24"]
      allowPrivateEndpoints : false
    },
    {
      name : "subnet-jumpbox"
      address_prefixes : ["10.100.0.0/28"]
      allowPrivateEndpoints : false
    },
    {
      name : "subnet-agents_devops"
      address_prefixes : ["10.100.0.16/28"]
      allowPrivateEndpoints : false
    }
  ]
}

module "spoke_vnet" {
  source              = "../../modules/vnet"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = var.location
  vnet_name           = var.spoke_vnet_name
  address_space       = [var.vnet_spoke_address_space]
  subnets = [
    {
      name : "subnet-cluster"
      address_prefixes : [var.subnet_cluster]
      allowPrivateEndpoints : true
    },
    {
      name : "subnet-ingress"
      address_prefixes : [var.subnet_ingress]  
      allowPrivateEndpoints : false
    },
    {
      name : "subnet-applicationgateway"
      address_prefixes : [var.subnet_app_gw]
      allowPrivateEndpoints : false
    }

  ]
}

resource "azurerm_subnet" "postgres-snet" {
  name                 = "subnet-postgres"
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = var.spoke_vnet_name
  address_prefixes     = [var.subnet_postgres]
  enforce_private_link_endpoint_network_policies = true

  delegation {
    name = "postgres-delegation"

    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
  depends_on           = [module.spoke_vnet]
}

module "vnet_peering" {
  source              = "../../modules/vnet_peering"
  vnet_1_name         = var.hub_vnet_name
  vnet_1_id           = module.hub_vnet.vnet_id
  vnet_1_rg           = azurerm_resource_group.hub.name
  vnet_2_name         = var.spoke_vnet_name
  vnet_2_id           = module.spoke_vnet.vnet_id
  vnet_2_rg           = azurerm_resource_group.spoke.name
  peering_name_1_to_2 = "HubToSpokeAks"
  peering_name_2_to_1 = "SpokeAksToHub"
}

# First NAT Gateway to provide enough source NAT ports to the cluster's node pools
module "nat_gateway_hub" {
  source          = "../../modules/nat_gateway"
  location        = var.location
  resource_group  = azurerm_resource_group.hub.name
  pip_prefix_name = "pip-prefix-nat-gw-hub"
  nat_gw_name     = "nat-gw-hub"
  subnet_id       = module.hub_vnet.subnet_ids["AzureFirewallSubnet"]
}

# Second NAT Gateway to provide internet access to the ingress node pool only
module "nat_gateway_spoke" {
  source          = "../../modules/nat_gateway"
  location        = var.location
  resource_group  = azurerm_resource_group.spoke.name
  pip_prefix_name = "pip-prefix-nat-gw-spoke"
  nat_gw_name     = "nat-gw-spoke"
  subnet_id       = module.spoke_vnet.subnet_ids["subnet-ingress"]
}

module "firewall" {
  source               = "../../modules/firewall"
  resource_group       = azurerm_resource_group.hub.name
  location             = var.location
  pip_name             = "ip-firewall-hub"
  fw_name              = "firewall-hub"
  fw_policy_name       = "firewall-hub-policy"
  fw_rcg_name          = "firewall-hub-rcg"
  subnet_id            = module.hub_vnet.subnet_ids["AzureFirewallSubnet"]
  rabbitmq_fqdn        = var.rabbitmq_fqdn
  subnet_cluster_space = var.subnet_cluster
  depends_on           = [module.nat_gateway_hub]
}

resource "azurerm_public_ip" "ingress_lb_public_ip" {
  name                = "${var.prefix}_Ingress_PublicIp"
  #Resource group that contains the cluster resources created by Azure
  resource_group_name = "MC_${azurerm_resource_group.spoke.name}_${azurerm_kubernetes_cluster.private_aks_cluster.name}_${var.location}"
  location            = var.location
  sku                 = "Standard"
  allocation_method   = "Static"
  depends_on = [azurerm_kubernetes_cluster.private_aks_cluster]
}

module "routetable_spoke" {
  source              = "../../modules/route_table"
  resource_group      = azurerm_resource_group.spoke.name
  location            = var.location
  rt_name             = "routetable-spoke"
  r_name              = "route-routetable-spoke"
  firewall_private_ip = module.firewall.fw_private_ip
  firewall_public_ip  = module.firewall.fw_public_ip
  subnet_ids          = {
    "subnet-cluster"          = module.spoke_vnet.subnet_ids["subnet-cluster"]
  }
}

module "log_analytics" {
  source              = "../../modules/log_analytics"
  name                = "${var.prefix}-loganalytics-ws"
  resource_group_name = "${var.prefix}-logs"
  location            = var.location
  sku                 = var.log_analytics_sku
  retention           = var.log_analytics_retention
}

##### FIRST INSTANCE CREATION ######
resource "random_password" "kc_pgadminpassword" {
  keepers = {
    resource_group = azurerm_resource_group.postgres.name
  }

  length      = 14
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  special     = false
}
resource "azurerm_postgresql_flexible_server" "cluster1kcpg01" {
  name                   = "${var.prefix}-cluster1kcpg01"
  resource_group_name    = azurerm_resource_group.postgres.name
  location               = var.location
  version                = "13"
  delegated_subnet_id    = azurerm_subnet.postgres-snet.id
  private_dns_zone_id    = module.dns_zone_postgres.id
  backup_retention_days = 7
  administrator_login    = "cluster1kcpgadmin"
  administrator_password = random_password.kc_pgadminpassword.result

  storage_mb = 32768

  sku_name   = "B_Standard_B1ms"
  depends_on = [module.dns_zone_postgres, azurerm_subnet.postgres-snet]

}

##### SECOND INSTANCE CREATION ######
resource "random_password" "anpm_pgadminpassword" {
  keepers = {
    resource_group = azurerm_resource_group.postgres.name
  }

  length      = 14
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  special     = false
}
resource "azurerm_postgresql_flexible_server" "cluster1anpmpg01" {
  name                   = "${var.prefix}-cluster1anpmpg01"
  resource_group_name    = azurerm_resource_group.postgres.name
  location               = var.location
  version                = "13"
  delegated_subnet_id    = azurerm_subnet.postgres-snet.id
  private_dns_zone_id    = module.dns_zone_postgres.id
  backup_retention_days = 7
  administrator_login    = "cluster1anpmpgadmin"
  administrator_password = random_password.anpm_pgadminpassword.result

  storage_mb = 32768

  sku_name   = "B_Standard_B1ms"
  depends_on = [module.dns_zone_postgres, azurerm_subnet.postgres-snet]

}

resource "azurerm_kubernetes_cluster" "private_aks_cluster" {
  name                    = "${var.prefix}-cluster"
  location                = var.location
  kubernetes_version      = var.kube_version
  resource_group_name     = azurerm_resource_group.spoke.name
  dns_prefix              = "${var.prefix}-cluster"
  private_cluster_enabled = true
  tags = {
    "environment" = var.environment
  }
  default_node_pool {
    name           = "default"
    node_count     = var.nodepool_nodes_count
    vm_size        = "Standard_B2s"
    vnet_subnet_id = module.spoke_vnet.subnet_ids["subnet-cluster"]
    tags = {
      "environment" = var.environment
    }
  }

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control {
    enabled = true
    azure_active_directory {
      managed = true
      admin_group_object_ids = var.cluster_admin_group_ids
    }
  }

  network_profile {
    docker_bridge_cidr = var.network_docker_bridge_cidr
    dns_service_ip     = var.network_dns_service_ip
    network_plugin     = "azure"
    outbound_type      = "userDefinedRouting"
    service_cidr       = var.network_service_cidr  
    network_policy     = "calico"
  }

  addon_profile {
    oms_agent {
      enabled = true
      log_analytics_workspace_id = module.log_analytics.id
    }
    kube_dashboard {
      enabled = false
    }
  }
  depends_on = [module.routetable_spoke]
}

resource "azurerm_kubernetes_cluster_node_pool" "wnpg" {
    name                    = "wnpg"
    kubernetes_cluster_id   = azurerm_kubernetes_cluster.private_aks_cluster.id
    vm_size                 = var.msmonitor_windows_nodepool_vm_size
    node_count              = var.msmonitor_windows_nodepool_nodes_count
    os_type                 = "Windows"
    vnet_subnet_id          = module.spoke_vnet.subnet_ids["subnet-cluster"]
    tags = {
        environment = var.environment
    }
    depends_on              = [azurerm_kubernetes_cluster.private_aks_cluster]
    node_labels = {
       pods = "cbmt_msmonitor"
    }
}

resource "azurerm_kubernetes_cluster_node_pool" "wnprm" {
    name                    = "wnprm"
    kubernetes_cluster_id   = azurerm_kubernetes_cluster.private_aks_cluster.id
    vm_size                 = var.MSM-Agent_windows_nodepool_vm_size
    node_count              = var.MSM-Agent_windows_nodepool_nodes_count
    os_type                 = "Windows"
    vnet_subnet_id          = module.spoke_vnet.subnet_ids["subnet-cluster"]
    tags = {
        environment = var.environment
    }
    depends_on              = [azurerm_kubernetes_cluster.private_aks_cluster]
    node_labels = {
       pods = "cbmt_MSM-Agent"
    }
}

resource "azurerm_kubernetes_cluster_node_pool" "windowsnp" {
    name                    = "wnp"
    kubernetes_cluster_id   = azurerm_kubernetes_cluster.private_aks_cluster.id
    vm_size                 = var.cluster1_windows_nodepool_vm_size
    node_count              = var.cluster1_windows_nodepool_nodes_count
    os_type                 = "Windows"
    vnet_subnet_id          = module.spoke_vnet.subnet_ids["subnet-cluster"]
    tags = {
        environment = var.environment
    }
    depends_on              = [azurerm_kubernetes_cluster.private_aks_cluster]
    node_labels = {
       pods = "cluster1"
    }
}

resource "azurerm_kubernetes_cluster_node_pool" "linuxnp" {
    name                    = "lnp"
    kubernetes_cluster_id   = azurerm_kubernetes_cluster.private_aks_cluster.id
    vm_size                 = var.cluster1_linux_nodepool_vm_size
    node_count              = var.cluster1_linux_nodepool_nodes_count
    os_type                 = "Linux"
    vnet_subnet_id          = module.spoke_vnet.subnet_ids["subnet-cluster"]
    tags = {
        environment = var.environment
    }
    depends_on              = [azurerm_kubernetes_cluster.private_aks_cluster]
    node_labels = {
      pods = "cluster1"
    }
}

resource "azurerm_kubernetes_cluster_node_pool" "ingresspool" {
     name                    = "ingress"
     kubernetes_cluster_id   = azurerm_kubernetes_cluster.private_aks_cluster.id
     vm_size                 = var.nodepool_vm_size
     node_count              = var.ingress_nodepool_nodes_count
     os_type                 = "Linux"
     vnet_subnet_id          = module.spoke_vnet.subnet_ids["subnet-ingress"]
     tags = {
         environment = var.environment
     }
     depends_on              = [azurerm_kubernetes_cluster.private_aks_cluster]
     node_labels = {
       pods = "ingress"
     }
}

resource "azurerm_role_assignment" "networkcontributor-snet-cluster" {
  role_definition_name = "Network Contributor"
  scope                = module.spoke_vnet.subnet_ids["subnet-cluster"]
  principal_id         = azurerm_kubernetes_cluster.private_aks_cluster.identity[0].principal_id
  depends_on           = [azurerm_kubernetes_cluster.private_aks_cluster, module.spoke_vnet]
}

resource "azurerm_role_assignment" "networkcontributor-snet-ingress" {
  role_definition_name = "Network Contributor"
  scope                =  module.spoke_vnet.subnet_ids["subnet-ingress"]
  principal_id         = azurerm_kubernetes_cluster.private_aks_cluster.identity[0].principal_id
  depends_on           = [azurerm_kubernetes_cluster.private_aks_cluster, module.spoke_vnet]
}

#to check the permissions to resources at subscriptions level, the identity needs the reader role in the IAM of the agent VM 
resource "azurerm_role_assignment" "devops_agent_identity" {
 role_definition_name = "Reader"
 scope                = module.devops_agent.vm_id
 principal_id         = module.devops_agent.agent_identity_sp_id
 depends_on           = [module.devops_agent]
}

resource "azurerm_role_assignment" "retrieve_aks_creds" {
  for_each             = toset(var.cluster_admin_group_ids)
  scope                = azurerm_kubernetes_cluster.private_aks_cluster.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
  depends_on           = [azurerm_kubernetes_cluster.private_aks_cluster]
}

#Allow this cluster the ability to pull images from the container registry
resource "azurerm_role_assignment" "aks_acr" {
  scope                = var.registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.private_aks_cluster.kubelet_identity[0].object_id
  depends_on           = [azurerm_kubernetes_cluster.private_aks_cluster]
}

# add the vnet hub to the DNS private zone of the cluster to be able to reach it using the private endpoint 
resource "azurerm_private_dns_zone_virtual_network_link" "hublink" {
  name                  = "hubnetdnsconfig"
  resource_group_name   = azurerm_kubernetes_cluster.private_aks_cluster.node_resource_group
  private_dns_zone_name = join(".", slice(split(".", azurerm_kubernetes_cluster.private_aks_cluster.private_fqdn), 1, length(split(".", azurerm_kubernetes_cluster.private_aks_cluster.private_fqdn))))
  virtual_network_id    = module.hub_vnet.vnet_id
}

module "jumpbox" {
  source                  = "../../modules/jumpbox"
  location                = var.location
  resource_group          = azurerm_resource_group.hub.name
  subnet_id               = module.hub_vnet.subnet_ids["subnet-jumpbox"]
  admin_group_ids         = var.cluster_admin_group_ids
}

module "devops_agent" {
  source                  = "../../modules/devops_agent"
  location                = var.location
  resource_group          = azurerm_resource_group.hub.name
  subnet_id               = module.hub_vnet.subnet_ids["subnet-agents_devops"]
  admin_group_ids         = var.cluster_admin_group_ids
}

resource "random_integer" "randomnumber" {
  min     = 10000
  max     = 99999
}
resource "azurerm_storage_account" "logstorage" {
  name                     = "logstorage${random_integer.randomnumber.result}"
  resource_group_name      = module.log_analytics.rg_name
  location                 = module.log_analytics.rg_location
  account_kind             = "BlobStorage"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  blob_properties {
  #this retention policy is for the purge of soft-deleted files by the lifecycle management rules
    delete_retention_policy {
      days = 2
    }
  }

  tags = {
    environment = var.environment
  }
}

module "dns_zone_cr" {
  source = "../../modules/private_dns_zone"
  resource_group_name = azurerm_resource_group.spoke.name
  private_dns_zone_name = "privatelink.azurecr.io"
  private_dns_vnet_links = { 
    "kube" = module.spoke_vnet.vnet_id
    "hub" = module.hub_vnet.vnet_id 
  }
}
module "dns_zone_db" {
  source = "../../modules/private_dns_zone"
  resource_group_name = azurerm_resource_group.spoke.name
  private_dns_zone_name = "privatelink.database.windows.net"
  private_dns_vnet_links = { 
    "kube" = module.spoke_vnet.vnet_id
    "hub" = module.hub_vnet.vnet_id 
  }
}
module "dns_zone_sa" {
  source = "../../modules/private_dns_zone"
  resource_group_name = azurerm_resource_group.spoke.name
  private_dns_zone_name = "privatelink.blob.core.windows.net"
  private_dns_vnet_links = { 
    "kube" = module.spoke_vnet.vnet_id
    "hub" = module.hub_vnet.vnet_id 
  }
}
module "dns_zone_postgres" {
  source = "../../modules/private_dns_zone"
  resource_group_name = azurerm_resource_group.spoke.name
  private_dns_zone_name = "${var.prefix}.private.postgres.database.azure.com"
  private_dns_vnet_links = { 
    "spoke" = module.spoke_vnet.vnet_id
    "hub" = module.hub_vnet.vnet_id 
  }
}

module "pe-registry" {
  source = "../../modules/private_endpoint"
  name = "registry"
  resource_group_name = azurerm_resource_group.spoke.name
  location = var.location
  subnet_id = module.spoke_vnet.subnet_ids["subnet-cluster"]
  private_connection_resource_id = var.registry_id
  subresource_names = [ "registry" ]
  private_dns_zone_id = module.dns_zone_cr.id
}
module "pe-sql" {
  source = "../../modules/private_endpoint"
  for_each = toset(var.sqlserver_ids)
  name = "sql${index(var.sqlserver_ids, each.value) + 1}"
  resource_group_name = azurerm_resource_group.spoke.name
  location = var.location
  subnet_id = module.spoke_vnet.subnet_ids["subnet-cluster"]
  private_connection_resource_id = each.value
  subresource_names = [ "SQLServer" ]
  private_dns_zone_id = module.dns_zone_db.id
}
module "pe-storageaccount" {
  source = "../../modules/private_endpoint"
  name = "storageaccount"
  resource_group_name = azurerm_resource_group.spoke.name
  location = var.location
  subnet_id = module.spoke_vnet.subnet_ids["subnet-cluster"]
  private_connection_resource_id = azurerm_storage_account.logstorage.id
  subresource_names = [ "blob" ]
  private_dns_zone_id = module.dns_zone_sa.id
}

data "azurerm_key_vault_secret" "primary_cert" {
    name         = var.primary_cert_name
    key_vault_id = var.certificate_keyvault_id
}
data "azurerm_key_vault_secret" "secondary_cert" {
    name         = var.secondary_cert_name
    key_vault_id = var.certificate_keyvault_id
}

module "app-gateway" {
  source                         = "../../modules/application_gateway"
  name                           = "${var.prefix}-appgw"
  resource_group_name            = azurerm_resource_group.spoke.name
  location                       = var.location
  app_gateway_sku                = var.app_gateway_sku
  app_gateway_tier               = var.app_gateway_tier
  app_gateway_backend_probe_path = var.app_gateway_backend_probe_path
  app_gateway_capacity           = var.app_gateway_capacity
  waf_enabled                    = var.waf_enabled
  waf_mode                       = var.waf_mode
  waf_rule_set_type              = var.waf_rule_set_type
  waf_rule_set_version           = var.waf_rule_set_version  
  subnet_id                      = module.spoke_vnet.subnet_ids["subnet-applicationgateway"]
  ingress_controller_ip          = var.ingress_controller_ip
  hosts_map               = {
    "primary"    = {
      hostname            = var.primary_hostname,
      certificate_data    = data.azurerm_key_vault_secret.primary_cert.value
    },
    "secondary"  = {
      hostname            = var.secondary_hostname,
      certificate_data    = data.azurerm_key_vault_secret.secondary_cert.value
    }
  }
}
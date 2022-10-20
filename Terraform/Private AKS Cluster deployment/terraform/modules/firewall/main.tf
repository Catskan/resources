resource "azurerm_public_ip" "pip" {
  name                = var.pip_name
  resource_group_name = var.resource_group
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall" "fw" {
  name                = var.fw_name
  location            = var.location
  resource_group_name = var.resource_group
  firewall_policy_id = azurerm_firewall_policy.fw_policy.id

  ip_configuration {
    name                 = "fw_ip_config"
    subnet_id            = var.subnet_id
    public_ip_address_id = azurerm_public_ip.pip.id
  }
  depends_on=[azurerm_public_ip.pip, azurerm_firewall_policy.fw_policy]
}

resource "azurerm_firewall_policy" "fw_policy" {
  name                = var.fw_policy_name
  location            = var.location
  resource_group_name = var.resource_group
  # This is to set the DNS Servers are "Azure Provided"
  # https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
  dns {
    servers = ["168.63.129.16"]
    proxy_enabled = true
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "fw_policy_rcg" {
  name               = var.fw_rcg_name
  firewall_policy_id = azurerm_firewall_policy.fw_policy.id
  priority           = 500
  
  application_rule_collection {
    name     = "aksbasics"
    priority = 201
    action   = "Allow"
    rule {
      name = "allow_network"
      source_addresses  = ["*"]
      destination_fqdns = [
            "*.cdn.mscr.io",
            "mcr.microsoft.com",
            "*.data.mcr.microsoft.com",
            "management.azure.com",
            "login.microsoftonline.com",
            "acs-mirror.azureedge.net",
            "dc.services.visualstudio.com",
            "*.opinsights.azure.com",
            "*.oms.opinsights.azure.com",
            "*.microsoftonline.com",
            "*.monitoring.azure.com"
      ]

      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
      
    }
  }

  application_rule_collection {
    name     = "osupdates"
    priority = 202
    action   = "Allow"
    rule {
      name = "allow_network"
      source_addresses  = ["*"]
      destination_fqdns = [
          "download.opensuse.org",
          "security.ubuntu.com",
          "ntp.ubuntu.com",
          "packages.microsoft.com",
          "snapcraft.io"
      ]

      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
      
    }
  }

  application_rule_collection {
    name     = "devopsagents"
    priority = 203
    action   = "Allow"
    rule {
      name = "allow_network"
      source_addresses  = ["*"]
      destination_fqdns = [
          "login.microsoftonline.com",
          "app.vssps.visualstudio.com",
          "gsxsolutions.visualstudio.com",
          "gsxsolutions.vsrm.visualstudio.com",
          "gsxsolutions.vstmr.visualstudio.com",
          "gsxsolutions.pkgs.visualstudio.com",
          "gsxsolutions.vssps.visualstudio.com",
          "dev.azure.com",
          "*.dev.azure.com",
          "login.microsoftonline.com",
          "management.core.windows.net",
          "vstsagentpackage.azureedge.net",
          "api.github.com",
          "kubernetes.github.io"
      ]

      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
      
    }
  }

  application_rule_collection {
    name     = "publicimages"
    priority = 204
    action   = "Allow"
    rule {
      name = "allow_network"
      source_addresses  = ["*"]
      destination_fqdns = [
          "auth.docker.io",
          "registry-1.docker.io",
          "production.cloudflare.docker.com",
          "k8s.gcr.io",   # ingress-nginx
          "storage.googleapis.com" # also ingress-nginx
      ]

      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
      
    }
  }

  application_rule_collection {
    name     = "rabbitmp_app"
    priority = 216
    action   = "Allow"
    rule {
      name              = "allow_network"
      source_addresses  = ["*"]
      destination_fqdns = [
          "*.cloudamqp.com"
      ]

      protocols {
        type = "Https"
        port = 443
      }
      
    }
  }

  network_rule_collection {
    name     = "time"
    priority = 101
    action   = "Allow"
    rule {
      name                  = "aks_node_time_sync_rule"
      protocols             = ["UDP"]
      source_addresses      = ["*"]
      destination_addresses = ["*"]
      destination_ports     = ["123"]
    }
  }

  network_rule_collection {
    name     = "dns"
    priority = 102
    action   = "Allow"
    rule {
      name                  = "aks_node_dns_rule"
      protocols             = ["UDP"]
      source_addresses      = ["*"]
      destination_addresses = ["*"]
      destination_ports     = ["53"]
    }
  }

  network_rule_collection {
    name     = "servicetags"
    priority = 110
    action   = "Allow"
    rule {
      name                  = "allow_service_tags"
      protocols             = ["Any"]
      source_addresses      = ["*"]
      destination_addresses = [
        "AzureContainerRegistry",
        "MicrosoftContainerRegistry",
        "AzureActiveDirectory"
      ]
      destination_ports     = ["1-65535"]
    }
  }

  network_rule_collection {
    name     = "rabbitmq"
    priority = 115
    action   = "Allow"
    rule {
      name              = "allow_rabbitmq"
      protocols         = ["TCP","UDP"]
      source_addresses  = ["*"]
      destination_fqdns = [ var.rabbitmq_fqdn ]
      destination_ports = ["5671"]
    }
  }

  network_rule_collection {
    name     = "open_traffic"
    priority = 150
    action   = "Allow"
    rule {
      name                  = "open_traffic_for_pods"
      protocols             = ["Any"]
      source_addresses      = [var.subnet_cluster_space]
      destination_addresses = ["*"]
      destination_ports     = ["1-65535"]
    }
  }
}
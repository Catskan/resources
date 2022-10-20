resource "azurerm_public_ip" "pip" {
  name                = "${var.name}-publicip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

locals {
    backend_address_pool_name      = "appgw-beap"
    frontend_port_name             = "appgw-feport"
    frontend_ip_configuration_name = "appgw-feip"
    http_setting_name              = "appgw-be-htst"
    https_listener_name            = "appgw-httpslstn"
    https_listener_name2           = "appgw-httpslstn2"
    https_routing_rule_name        = "appgw-https-rqrt"
    https_routing_rule_name2       = "appgw-https-rqrt2"
    health_probe_name              = "nginx-health-probe"
}

resource "azurerm_application_gateway" "appgw" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  enable_http2 = true

  sku {
    name     = var.app_gateway_sku
    tier     = var.app_gateway_tier
    capacity = var.app_gateway_capacity
  }

  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = var.subnet_id
  }

  waf_configuration {
    enabled = var.waf_enabled
    firewall_mode = var.waf_mode
    rule_set_type = var.waf_rule_set_type
    rule_set_version = var.waf_rule_set_version
    dynamic "disabled_rule_group" {
      for_each = var.disabled_rule_groups
      content {
        rule_group_name = disabled_rule_group.value.rule_group_name
        rules           = disabled_rule_group.value.rules
      }
    }
  }

  frontend_port {
    name = "httpsPort"
    port = 443
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.pip.id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
    ip_addresses = [ var.ingress_controller_ip ]
  }

  probe {
    name = local.health_probe_name
    protocol = "http"
    host = var.ingress_controller_ip
    pick_host_name_from_backend_http_settings = false
    path = var.app_gateway_backend_probe_path
    interval = 30
    timeout = 30
    unhealthy_threshold = 3
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = local.health_probe_name
  }
  # The secondary listener goes first because it is a deeper domain than the primary.
  # Secondary: *.swo.ongsx.com
  # Primary: *.ongsx.com
  # If primary went first, then the SWO requests would match it. The more specific domain (secondary) must 
  # be first in line to be matched first To handle this a priority in the request routing rules has been set
  http_listener {
    name                           = local.https_listener_name2
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = "httpsPort"
    protocol                       = "Https"
    ssl_certificate_name           = "secondary_cert"
    host_names                     = [ var.hosts_map["secondary"].hostname ]
  }
  http_listener {
    name                           = local.https_listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = "httpsPort"
    protocol                       = "Https"
    ssl_certificate_name           = "primary_cert"
    host_names                     = [ var.hosts_map["primary"].hostname ]
  }

  ssl_certificate {
    name                       = "primary_cert"
    data                       = var.hosts_map["primary"].certificate_data
  }

  ssl_certificate {
    name                       = "secondary_cert"
    data                       = var.hosts_map["secondary"].certificate_data
  }

  request_routing_rule {
    name                       = local.https_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.https_listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
    priority = 200
  }
  request_routing_rule {
    name                       = local.https_routing_rule_name2
    rule_type                  = "Basic"
    http_listener_name         = local.https_listener_name2
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
    priority = 100
  }
}
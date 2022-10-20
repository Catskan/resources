variable name {}
variable resource_group_name {}
variable location {}
variable subnet_id {
  description = "The subnet to host the application gateway. This subnet cannot have anything in it other than other application gateways, if anything"
}
variable ingress_controller_ip {
  description = "The private external IP of the Nginx Ingress Controller"
}
variable hosts_map {
  description = "The actual data for the cerficates to use on the HTTPS listener. Read the value from the keyvault and pass it in to this variable"
  type = map(object({
    hostname                = string
    certificate_data        = string
  }))
}
variable app_gateway_sku {
  default = "WAF_V2"
}
variable app_gateway_tier {
  default="WAF_V2"
}
variable "app_gateway_backend_probe_path" {
}
variable waf_enabled {
  default=true
}
variable waf_mode {
  default="Prevention"
}
variable waf_rule_set_type {
  default="OWASP"
}
variable waf_rule_set_version {
  default = "3.0"
}
variable "disabled_rule_groups" {
  description = "rules to be disabled in the WAF of the App Gateway"
  default     = [
    {
      rule_group_name = "REQUEST-920-PROTOCOL-ENFORCEMENT"
      rules           = [920320]
    },
    {
      rule_group_name = "REQUEST-932-APPLICATION-ATTACK-RCE"
      rules           = []
    },
    {
      rule_group_name = "REQUEST-942-APPLICATION-ATTACK-SQLI"
      rules           = []
    }
  ]
}

variable app_gateway_capacity {
  description="The Capacity of the SKU to use for this Application Gateway. When using a V1 SKU this value must be between 1 and 32, and 1 to 125 for a V2 SKU"
  default=2
}
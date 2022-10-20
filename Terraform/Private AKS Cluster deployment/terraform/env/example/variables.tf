variable "subscriptionid" {}
variable "environment" {
  description = "Gets added as a tag to identify the deployment as production, development or test"
}
variable "prefix" {
  description = "Many named items will be prefixed with this value to prevent duplication"
}
variable "location" {
  description = "The resource group location"
  default     = "westeurope"
}

variable "registry_id" {
  description = "The ID of the registry where the MSmonitor containers live. This registry will be accessed privately"
}

variable "sqlserver_ids" {
  description = "The IDS for the sqlservers hosting databases for MSmonitor Hosted and Partners."
}
variable "certificate_keyvault_id" {
  description = "The ID of the keyvault where the certificate is stored. User running Terraform requires READ access. Both certs need to be in same keyvault"
}
variable "primary_cert_name" {
  description = "The name of the primary certificate stored in a keyvault to be used by the Application Gateway for its HTTPS listener. The certificated must be base-64 encoded and unencrypted pfx"
}
variable "secondary_cert_name" {
  description = "The name of the secondary certificate stored in a keyvault to be used by the Application Gateway for its HTTPS listener. The certificated must be base-64 encoded and unencrypted pfx"
}

variable "primary_hostname" {
  description = "The hostname to use on the primary listener in the applictaion gateway. In our use case, it must contain wildcards: *.ongsx.com"
}

variable "secondary_hostname" {
  description = "The hostname to use on the secondary listener in the applictaion gateway. We require wildcards to have just 2 listeners: *.swo.ongsx.com"
}
variable "rabbitmq_fqdn" {
  description = "The FQDN of the rabbitmq server used in this deployment"
}

variable "cluster_admin_group_ids" {
  description = "List of AAD groups IDs that are able to perform kubectl commands against this cluster"
  type = list(string)
}

variable "hub_resource_group_name" {
  description = "The resource group name to be created"
  default     = "hub"
}
variable "aks_resource_group_name" {
  description = "The resource group name to be created"
  default     = "spoke_aks"
}
variable "vaults_resource_group_name" {
  description = "The resource group name to be created"
  default     = "vaults"
}

variable "postgres_resource_group_name" {
  description = "The resource group name to be created"
  default     = "postgres"
}

variable "hub_vnet_name" {
  description = "Hub VNET name"
  default     = "vnet-hub"
}

variable "spoke_vnet_name" {
  description = "Spoke AKS VNET name"
  default     = "vnet-spoke_aks"
}

variable "kube_version" {
  description = "AKS Kubernetes version"
  default     = "1.20.9"
}


variable "nodepool_nodes_count" {
  description = "Default nodepool nodes count"
  default     = 1
}
variable "ingress_nodepool_nodes_count" {
  description = "Ingress controller nodepool nodes count"
  default     = 1
}

variable "msmonitor_windows_nodepool_vm_size" {
  description = "Windows nodepool VM size"
}

variable "msmonitor_windows_nodepool_nodes_count" {
  description = "Windows nodepool nodes count"
}

variable "MSM-Agent_windows_nodepool_vm_size" {
  description = "Windows nodepool VM size"
}

variable "MSM-Agent_windows_nodepool_nodes_count" {
  description = "Windows nodepool nodes count"
}

variable "cluster1_windows_nodepool_nodes_count" {
  description = "Windows nodepool nodes count"
}

variable "cluster1_windows_nodepool_vm_size" {
  description = "Windows nodepool VM size"
}

variable "cluster1_linux_nodepool_nodes_count" {
  description = "Linux nodepool nodes count"
}
variable "cluster1_linux_nodepool_vm_size" {
  description = "Linux nodepool VM size"
}

variable "nodepool_vm_size" {
  description = "Default nodepool VM size"
  default     = "Standard_D2_v2"
}

variable "network_docker_bridge_cidr" {
  description = "CNI Docker bridge cidr"
  default     = "172.17.0.1/16"
}

variable "network_dns_service_ip" {
  description = "CNI DNS service IP"
  default     = "10.2.0.10"
}

variable "network_service_cidr" {
  description = "CNI service cidr"
  default     = "10.2.0.0/17"
}

variable "vnet_spoke_address_space" {
  description = "address space for the spoke vnet"
}

variable "subnet_cluster" {
  description = "Subnet of the Cluster to be used for all the pods"
}

variable "subnet_ingress" {
  description = "Subnet for the ingress controller"
}

variable "subnet_app_gw" {
  description = "subnet for the application gateway"
}

variable "subnet_postgres" {
  description = "subnet for the postgres flexible servers"
}

variable "ingress_controller_ip" {
  description = "Private external IP used by Nginx Ingress Controller"
}

variable "log_analytics_sku" {
  description = "The SKU for the log analytics workspace. This dictates the cost of storing metrics and logs"
  default = "pergb2018"
}

variable "log_analytics_retention" {
  description = "How long to keep the files. 7 is minimum only for Free; 30 is min for all other SKUs"
  default = 30
}

variable "agent_name" {
  description = "Name of the agent to be configured in azure devops"
  default = "devops-agent"
}
variable app_gateway_sku {
  # Need to use this SKU to support multi-site listeners
  default = "WAF_V2"
}
variable app_gateway_tier {
  # Need to use this tier to support multi-site listeners
  default="WAF_V2"
}
variable "app_gateway_backend_probe_path" {
  default="/nginx-health"
}
variable waf_enabled {
  description = "application gateway web application firewall activation"
  default=true
}
variable waf_mode {
  description = "application gateway web application firewall mode"
  default="Prevention"
}
variable waf_rule_set_type {
  description = "application gateway web application firewall rules standard"
  default="OWASP"
}
variable waf_rule_set_version {
  default = "3.0"
}
variable "app_gateway_capacity" {
  description = "The Capacity of the SKU to use for this Application Gateway. When using a V1 SKU this value must be between 1 and 32, and 1 to 125 for a V2 SKU"
  default = 2
}
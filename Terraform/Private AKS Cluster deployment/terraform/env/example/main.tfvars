### SUBSCRIPTIONS VARIABLES ###
subscriptionid="a548cb3d-0887-4b87-8460-6bf34967538b"
prefix="example"
environment="dev"
registry_id="/subscriptions/a548cb3d-0887-4b87-8460-6bf34967538b/resourceGroups/cbmtdev-shared/providers/Microsoft.ContainerRegistry/registries/cbmtdev"
rabbitmq_fqdn="brisk-charcoal-raccoon.rmq.cloudamqp.com"
certificate_keyvault_id="/subscriptions/a548cb3d-0887-4b87-8460-6bf34967538b/resourceGroups/cbmtdev-shared/providers/Microsoft.KeyVault/vaults/cbmtVaultDev"
### APP GATEWAY HOSTNAMES & CERTIFICATES ###
primary_hostname="*.dev.ongsx.com"
secondary_hostname="*.partner.dev.ongsx.com"
primary_cert_name="dev-ongsx-com"
secondary_cert_name="test-self-signed"
### NODEPOOLS VARIABLES ###
msmonitor_windows_nodepool_nodes_count=1
msmonitor_windows_nodepool_vm_size="Standard_D4s_v3"
MSM-Agent_windows_nodepool_nodes_count=1
MSM-Agent_windows_nodepool_vm_size="Standard_D4s_v3"
cluster1_windows_nodepool_nodes_count=1
cluster1_windows_nodepool_vm_size="Standard_D4s_v3"
cluster1_linux_nodepool_nodes_count=1
cluster1_linux_nodepool_vm_size="Standard_D4s_v3"
### NETWORK VARIABLES ###
#network_service_cidr in variables.tf should be equal in network size to subnet_cluster variable here
vnet_spoke_address_space="10.240.0.0/16"
subnet_cluster="10.240.0.0/17"
subnet_postgres="10.240.200.0/24"
subnet_ingress="10.240.250.0/24"
subnet_app_gw="10.240.254.0/24"
### IP OF THE INGRESS CONTROLLER FOR THE APP GW IN CBMT, THIS SHOULD BELONG TO THE SUBNET_CLUSTER TO BE ABLE TO COMMUNICATE WITH THE OTHER PODS, 
### THE INGRESS PODS WILL TAKE THE PRIVATE IP ADDRESS OF THE INGRESS SUBNET AND THE SERVICE IN THE NAMESPACE WILL TAKE THIS IP AS ENTRYPOINT
ingress_controller_ip="10.240.100.101"
### SQL & CLUSTER ADMIN VARIABLES ###
sqlserver_ids=[
    "/subscriptions/a548cb3d-0887-4b87-8460-6bf34967538b/resourceGroups/cbmtdev-sql/providers/Microsoft.Sql/servers/cbmtdev1"
]
cluster_admin_group_ids=[
    "AAD_group_id_1", # ex. "f07915c2-ac91-4dcc-b63c-153730689bcb" clusteradmins dev
    "AAD_group_id_2" # ex. "5da58aee-f155-4b6d-ba15-dfb55cabc423" managedidentities dev
]
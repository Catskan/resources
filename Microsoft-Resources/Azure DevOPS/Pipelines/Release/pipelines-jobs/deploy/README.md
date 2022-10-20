# Deploy VantageDX tenant
This pipeline deploy a VantageDX tenant into your Kubernetes cluster with all required components

# Variables available before start pipeline
- AGENT_POOL_NAME **$(AGENT_POOL_NAME)** : Name of the Azure DevOPS Agent Pool
- AZURE_SUBSCRIPTION **$(AZURE_SUBSCRIPTION)** : Azure Subscription used to build and push images into Azure Registry
- BUILD_DEFINITION_ID_IQ **$(BUILD_DEFINITION_ID_IQ)** : Same as MSmonitor expected build pipeline **BuildAndRelease** in iQ project
- CERT-MANAGER_ACME_SERVER_URL **$(CERT-MANAGER_ACME_SERVER_URL)** : ACMR Server URL for registration
  - Staging : https://acme-staging-v02.api.letsencrypt.org/directory
  - Production : https://acme-v02.api.letsencrypt.org/directory
- CERT-MANAGER_DNS_ZONE_NAME **$(CERT-MANAGER_DNS_ZONE_NAME)** : Azure resource DNS zone name
- CERT-MANAGER_DNS_ZONE_RG_NAME **$(CERT-MANAGER_DNS_ZONE_RG_NAME)** : Azure Resource group to the DNS zone name
- CERT-MANAGER_PRIVATE_KEY_NAME **$(CERT-MANAGER_PRIVATE_KEY_NAME)** : Issuer letsencrypt private key name
  - Staging : letsencrypt-staging
  - Production : letsencrypt-prod
- CUSTOMERNAME **$(CUSTOMERNAME)** : Name of the tenant to create Kubernetes namepsace and resources associated
- DEPLOY_MSmonitor_msm-agent **$(DEPLOY_MSmonitor_msm-agent)** : Start the msm-agent container deployement if needed.
  - Possibles values : Yes / No
- DEPLOY_IQ **$(DEPLOY_IQ)** : Start the iQ container deployement if needed.
  - Possibles values : Yes / No
- ELASTIC_ENDPOINT **$(ELASTIC_ENDPOINT)** : URL of the Elastic Search Endpoint used by the client you want to deploy
- ELASTIC_PASSWORD **$(ELASTIC_PASSWORD)** : Password genereated at the ElasticSearch creation
- ELASTIC_USER **$(ELASTUC_USER)** : Username generated at the ElasticSearch creation
- MSmonitor_IMAGE_VERSION **$(MSmonitor_IMAGE_VERSION)** : MSmonitor image version in the repository selected
- MSmonitor_LICENSE_CLIENT_CONTACT **$(MSmonitor_LICENSE_CLIENT_CONTACT)** : Client email adress
- MSmonitor_LICENSE_EXPIRATION_DATE **$(MSmonitor_LICENSE_EXPIRATION_DATE)** : Expiration date of the license
- MSmonitor_LICENSE_LEVEL **$(MSmonitor_LICENSE_LEVEL)** : Level associated with the license type
- MSmonitor_LICENSE_STATUS **$(MSmonitor_LICENSE_STATUS)** : Active or Inactive license
- MSmonitor_LICENSE_TYPE **$(MSmonitor_LICENSE_TYPE)** : Type of the MSmonitor license
  - Possible values : Essentiel / Enterprise / Ultimate
- MSmonitor_LICENSE_USERS_NUMBER **$(MSmonitor_LICENSE_USERS_NUMBER)** : Number of users in the client’s network
- IMAGE_REPO_MSmonitor **$(IMAGE_REPO_MSmonitor)** : Name of the repository to deploy an MSmonitor image
- IMAGE_REPO_IQ **$(IMAGE_REPO_IQ)** : Name of the repository to deploy an iQ image 
- IMAGE_REPO_msm-agent **$(IMAGE_REPO_msm-agent)** : Name of the repository to deploy an MSmonitor's msm-agent image
- IQ_IMAGE_VERSION **$(IQ_IMAGE_VERSION)** : iQ image version in the repository selected
- IQ_LICENSE_CODE **$(IQ_LICENSE_CODE)** : Enter the client's iQ License code
- KEYCLOAK_FRONTEND_URL **$(KEYCLOAK_FRONTEND_URL)** : External URL of the keycloak server
- KEYCLOAK_MONITORING_USER_PASSWORD **$(KEYCLOAK_MONITORING_USER_PASSWORD)** : Password of the user "Monitoring" created in the keycloak server
- KEYCLOAK_SERVER_URI **$(KEYCLOAK_SERVER_URI)** : Keycloak server address
- msm-agent_IMAGE_VERSION **$(msm-agent_IMAGE_VERSION)** : MSmonitor's msm-agent image version in the repository selected
- SHARED_KEYVAULT **$(SHARED_KEYVAULT)** : Shared keyvault name for the deployment of every tenant
- SSO_CLIENT_DOMAIN **$(SSO_CLIENT_DOMAIN)** : Microsoft Client domain to set the SSO
- SWO_TENANT **$(SWO_TENANT)** : Is SoftwareOne tenant ?
  - Possible values : Yes / No

# Variables available only in edit mode
- API_CONNECTION **$(API_CONNECTION)** : Servie connection name for the LogicApp linked /!\ No need to modify /!\
- BUILD_PIPELINE_ID_MSmonitor **$(BUILD_PIPELINE_ID_MSmonitor)** : MSmonitor build pipeline ID
- BUILD_PIPELINE_ID_IQ **$(BUILD_PIPELINE_ID_IQ)** : iQ build pipeline ID
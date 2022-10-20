# VARIABLES FILES STRUCTURE

This folder contains the infrastructure-related static variables organized by environment and also the static & runtime variables of each environment's pipelines. this allows to modify the variables of each individual environment and be able to test the changes without affecting the others.

The environment variables are for variables that affect the individual application(eg. ntwmonitor) variables that are cluster-wide. 
The pipeline variables are for things that directly affect the pipelines. The static ones are for pipeline are for pipeline task configuration independent of runtime. And the runtime ones are for pipeline execution configuration independent of cluster. Both of these groups of variables need to exist per execution.


The following list contains the variables configured at the runtime of the pipelines:

# Deploy Pipeline Runtime Variables

- CLIENT_DBNAME: By default value is '$(CUSTOMERNAME)' variable and the pipeline adds the '_ntwmonitor' or '_msmonitor' to differentiate the component's SQL DB.
- CLIENT_KEYVAULT_NAME: By default is 'KV$(CUSTOMERNAME)' could be change if the pipeline detects that it already exists as the Keyvaults names are globally unntwmonitorue.
- CUSTOMERNAME: Name of the tenant to be deployed.
- MSmonitor_IMAGE_VERSION: MSmonitor image version to deploy (e.g.'2.3.0.22315.22968')
- IQ_IMAGE_VERSION: Iq image version to deploy (e.g.'3.0.0.22825.22834')
- KEYCLOAK_IMAGE_VERSION: Keycloak image version to deploy (e.g.'v20211109.1')
- NPV_IMAGE_VERSION: NPV image version to deploy (e.g.'1.1.3-24390')
- ES_VERSION: Elastic Search Version to deploy (e.g. '7.16.3')

# Upgrade Pipeline Runtime Variables

- CUSTOMERNAME: Name of the tenant to be updated (e.g.'client1')
- MSmonitor_IMAGE_VERSION: New MSmonitor image version to deploy (e.g.'3.0.0.22825.22834')
- IQ_IMAGE_VERSION: New Iq image version to deploy (e.g.'3.0.0.22825.22834')
- KEYCLOAK_IMAGE_VERSION: New Keycloak image version to deploy (e.g.'v20211109.1')
- NPV_IMAGE_VERSION: New NPV image version to deploy (e.g.'1.1.3-24390')
- ES_VERSION: New Elastic-Search image version to deploy (e.g.'7.16.3')
- UPGRADE_INGRESS: Update tenant's ingress object with latest annotations & config (e.g.'True/False')

# Offboarding Pipeline Runtime Variables

- CUSTOMERNAME: Name of the tenant to offboard (e.g.'client1')
- SOFT_DELETE_KEYVAULT: Soft-delete tenant's Keyvault (could be restored) (e.g.'true/false')
- PURGE_KEYVAULT: Purge the keyvault after being soft-deleted (permanently delete it) (e.g.'true/false')
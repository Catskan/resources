## Terraform 

This directory allows you to create the entire infrastructure required to deploy MSmonitor into k8s. The implementation is based on https://github.com/patuzov/terraform-private-aks.

It creates a private cluster, jumpbox/bastion, the vnets and firewall necessary to secure the infrastructure.

## Steps to get started

We need to setup remote storage for the terraform state. We are using steps detailed here: 
https://blog.jcorioland.io/archives/2019/09/09/terraform-microsoft-azure-remote-state-management.html

The **myname** value in the example should be replaced by your name or the deployment: dev, qa or prod, etc.

```
mkdir env/myname
cp env/example/* env/myname/
<nano env/myname/main.tfvars with values for your deployment>
<nano env/myname/backend.tfvars with values for how to save the terraform state>
```

set the subscription according to the environment to be deployed by executing the following commands:
```
az login
az account set --subscription "subscriptionName"
```

Then you run a script to create the necessary elements in Azure to save the state in a storage account:
```
./env/setup-shared-storage.sh
```

Now, you can initialize your terraform setup according to the environment
```
terraform -chdir=./env/myname init -backend-config=backend.tfvars
```

Plan and deploy:
```
terraform -chdir=./env/myname plan --var-file=main.tfvars -out build.tfplan
terraform -chdir=./env/myname apply build.tfplan
```

Should you want to tear-down the deployment, run these commands:
```
terraform -chdir=./env/myname plan -destroy --var-file=main.tfvars -out destroy.tfplan
terraform -chdir=./env/myname apply destroy.tfplan
```

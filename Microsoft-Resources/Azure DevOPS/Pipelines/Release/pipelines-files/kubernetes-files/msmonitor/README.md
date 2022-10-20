# Steps to deploy MSmonitor container in K8s

This file describes how to deploy the MSmonitor container into K8s. There are some assumptions that the cluster is already deployed and that the `kubectl` tool has access to said cluster.

# Connect to k8s cluster

In this document, it is assumed that a cluster is already created.  Also, it is assumed that the kubectl tool is authenticated against that cluster using the `az` tool, as follows:
```
az account set --subscription <GUID>
az aks get-credentials --resource-group <RESOURCE_GROUP> --name <CLUSTER_NAME>
```

You can get the specific value for GUID, RESOURCE_GROUP and CLUSTER_NAME by clicking on the “connect” button in the Azure portal for the cluster.

# Namespace

For a new tenant, a new namespace is required. The examples below assume a namespace called `tenant1`. Change the name according to the tenant, of course.  To create a new namespace, execute the following command:
```
kubectl create namespace tenant1
```

To make future commands reference this newly-created namespace by default, change the context:
```
kubectl config set-context --current --namespace=tenant1
```

# Create ConfigMap and Secrets

Use the template files to create text files that will contain values for your tenant deployment
```
cp configmap-template.txt configmap.txt
cp secret-template.txt secret.txt
```

*Edit the configmap.txt and secret.txt* to put in the tenant-specific values.

Now, create the configmap and secret.  Change *tenant1* to the namespace you will use for the tenant.

```
kubectl create configmap --from-env-file=configmap.txt configmap-msmonitor --namespace=tenant1
kubectl create secret generic --from-env-file=secret.txt secret-msmonitor --namespace=tenant1 
```

# Deploy the pod

To deploy the MSmonitor pod, execute the following command:

```
kubectl apply -n tenant1 -f deploy-msmonitor.yaml
```

To see if the pod is deployed, you can check:
```
kubectl get pods -n tenant1
```



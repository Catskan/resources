#!/bin/bash

set -e
echo "Enter the environment directory name (i.e., ./env/geoff/backend.tfvars, enter geoff)"
read envdir

source ./env/$envdir/backend.tfvars

if [ -z "$resource_group_name" ] || [ -z "$storage_account_name" ] || [ -z "$container_name" ] || [ -z "$key"  ];
then
  echo "You are missing your setup environment. See README.md"
  echo "mkdir env/myname"
  echo "cp env/example/* env/myname/"
  echo "nano env/myname/backend.tfvars to edit the values and re-run this script"
  exit 1
else
  echo "Enter the name for the key vault where to store the storage account key:"
  read keyvault_name

  echo ""
  echo "All set. Here is the environment to be used:"
  echo "resource_group_name=$resource_group_name"
  echo "storage_account_name=$storage_account_name"
  echo "container_name=$container_name"
  echo "key=$key"
  echo "keyvault_name=$keyvault_name"
  echo ""
  echo "Press enter to continue creating the above elements or CTRL-C to quit:"
  read
fi

LOCATION=westeurope
COMMON_RESOURCE_GROUP_NAME=$resource_group_name
TF_STATE_STORAGE_ACCOUNT_NAME=$storage_account_name
TF_STATE_CONTAINER_NAME=$container_name
TF_KEY_NAME=$key
KEYVAULT_NAME=$keyvault_name

# Create the resource group
echo "Creating $COMMON_RESOURCE_GROUP_NAME resource group..."
az group create -n $COMMON_RESOURCE_GROUP_NAME -l $LOCATION

echo "Resource group $COMMON_RESOURCE_GROUP_NAME created."

# Create the storage account
echo "Creating $TF_STATE_STORAGE_ACCOUNT_NAME storage account..."
az storage account create -g $COMMON_RESOURCE_GROUP_NAME -l $LOCATION \
  --name $TF_STATE_STORAGE_ACCOUNT_NAME \
  --sku Standard_LRS \
  --encryption-services blob

echo "Storage account $TF_STATE_STORAGE_ACCOUNT_NAME created."

# Retrieve the storage account key
echo "Retrieving storage account key..."
ACCOUNT_KEY=$(az storage account keys list --resource-group $COMMON_RESOURCE_GROUP_NAME --account-name $TF_STATE_STORAGE_ACCOUNT_NAME --query [0].value -o tsv)

echo "Storage account key retrieved."

# Create a storage container (for the Terraform State)
echo "Creating $TF_STATE_CONTAINER_NAME storage container..."
az storage container create --name $TF_STATE_CONTAINER_NAME --account-name $TF_STATE_STORAGE_ACCOUNT_NAME --account-key $ACCOUNT_KEY

echo "Storage container $TF_STATE_CONTAINER_NAME created."

# Create an Azure KeyVault
echo "Creating $KEYVAULT_NAME key vault..."
az keyvault create -g $COMMON_RESOURCE_GROUP_NAME -l $LOCATION --name $KEYVAULT_NAME

echo "Key vault $KEYVAULT_NAME created."

# Store the Terraform State Storage Key into KeyVault
echo "Store storage access key into key vault secret..."
az keyvault secret set --name tfstate-storage-key --value $ACCOUNT_KEY --vault-name $KEYVAULT_NAME

echo "Key vault secret created."

# Display information
echo "Azure Storage Account and KeyVault have been created."
echo "Run the following command to initialize Terraform to store its state into Azure Storage (replace myname with where you stored your env):"
echo "terraform init -backend-config=./env/$envdir/backend.tfvars"
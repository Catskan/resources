#!/bin/bash
tenants=`cat source.txt | sed 's/\r$//' | cut -d "." -f1`
for t in $tenants
do
  az pipelines run --organization https://azdevopstenant.visualstudio.com/ --project ProjectName --id 257 --variables "CUSTOMERNAME=$t" "SOFT_DELETE_KEYVAULT=true"
  echo "############################# updating tenant: $t #####################################"
  sleep 9m
done

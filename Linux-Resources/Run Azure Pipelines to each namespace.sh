#!/bin/bash
tenants=`cat swo-wave2-1.txt | sed 's/\r$//' | cut -d "." -f1`
for t in $tenants
do
  az pipelines run --organization https://gsxsolutions.visualstudio.com/ --project CBMT --id 257 --variables "CUSTOMERNAME=$t" "SOFT_DELETE_KEYVAULT=true"
  echo "############################# updating tenant: $t #####################################"
  sleep 9m
done

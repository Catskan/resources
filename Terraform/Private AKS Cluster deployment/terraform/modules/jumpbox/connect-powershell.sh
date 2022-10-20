#!/bin/bash

if [ $# -eq 0 ]; then
	echo -n "Enter the tenant namespace and press [ENTER]: "
	read NS
else 
	NS="$1"
fi

# validate namespace
nsCheck=$(kubectl get namespace "$NS" 2> /dev/null) 

if [ -z "$nsCheck" ]; then
  echo "Namespace for tenant, $NS, not found. Exiting"
  exit -1
fi

podname=$(kubectl get pods -o=jsonpath='{.items..metadata.name}' -n "$NS" | awk '{print $1}' | grep -e "msmonitor")

# validate pod name
if [ -z "$podname" ]; then
  echo "The msmonitor pod not found. Exiting"
  exit -1
fi

kubectl exec -it -n $NS $podname -- powershell 
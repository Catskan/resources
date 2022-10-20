#!/bin/bash
sudo apt-get update && sudo apt-get install -y apt-transport-https gnupg2 unzip
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo 'deb https://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az version
sudo az aks install-cli
sudo snap install helm --classic

cat <<\EOF >> /tmp/connect-powershell.sh
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
EOF

sudo mv /tmp/connect-powershell.sh /usr/local/bin
sudo chmod a+x /usr/local/bin/connect-powershell.sh
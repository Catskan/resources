#!/bin/bash
echo $@echo "start"
sudo apt-get update && sudo apt-get install -y apt-transport-https gnupg2 unzip
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo 'deb https://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az version
sudo az aks install-cli
sudo snap install helm --classic
sudo apt install postgresql-client -y
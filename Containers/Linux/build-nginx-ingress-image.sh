#!/bin/bash

###################################################################
############### Install all requirements to build #################
############## NGINX PLUS Ingress Controller image ################
###################################################################


        
#Install requirements packages
sudo apt update && sudo apt install docker.io containerd runc

#Clone the git repo of the latest kubernetes ingress tag
git clone https://github.com/nginxinc/kubernetes-ingress/
cd ./kubernetes-ingress

#NGINX Version can be find with git describe or directly in the git repo
git checkout $IngressVersion

#Copy NGINX Plus License certificate
cp $AgentBuildDirectory/containers/nginx-ingress/licenses/nginx-repo.crt .
cp $AgentBuildDirectory/containers/nginx-ingress/licenses/nginx-repo.key .
ls nginx-repo.*

#Build the image
make debian-image-plus PREFIX=$GsxContainerRegistryName/nginx-plus-ingress TARGET=container TAG=$IngressVersion

#Push image into the container registry
make push PREFIX=$GsxContainerRegistryName/nginx-plus-ingress TAG=$IngressVersion
echo "Rename image tag to push to Martello registry"
docker tag $GsxContainerRegistryName/nginx-plus-ingress:$IngressVersion $MtloContainerRegistryName/nginx-plus-ingress:$IngressVersion
make push PREFIX=$MtloContainerRegistryName/nginx-plus-ingress TAG=$IngressVersion


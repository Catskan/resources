#!/bin/bash
#Create group "docker"
groupadd docker

#Add the current user to docker group
usermod -aG docker $USER

#Actvates changes to the group
newgrp docker
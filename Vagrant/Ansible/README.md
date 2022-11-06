# Vagrants commands notes

Initialize your directory to create a basic Vagrantfile

`vagrant init`

Start a Vagrant virtual machine from vagrant file

`vagrant up`

Delete the Vagrant virtual machine

`vagrant destroy`

## Docker provider

Open a interactive terminal inside the docker container

`vagrant docker-exec -it <<vagrant-vm-name>> -- /bin/sh `

*Note : `<vagrant-vm-name>` is the name from block `config.vm.define`inside the Vagrantfile*

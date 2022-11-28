#!/bin/bash

#Add the correct permissions to mounted sshkeys
chmod 644 /.ssh_keys/id_rsa_debian_ansible.pub 
chmod 600 /.ssh_keys/id_rsa_debian_ansible

tail -f /dev/null
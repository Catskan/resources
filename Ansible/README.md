# Ansible command line notes

##### Run a playbook :

`ansible-playbook -i inventory/file/path.yml /ansible/playbook/file/path.yml`

*Example :*
`ansible-playbook -i /share/Ansible/Inventory/hosts.yaml /share/Ansible/Macbook/Remove-FondueDeDeco.yaml`

ansible-playbook -i /share/Ansible/Inventory/hosts.yaml /share/Ansible/Gaming/main_playbook.yml
ansible-playbook -i /share/Ansible/Inventory/hosts.yaml /share/Ansible/Gaming/User.yaml

ansible-playbook -i /share/Ansible/Inventory/hosts.yaml /share/Ansible/Gaming/main_remove_softwares.yml


*Encrypt a secret file:*

`ansible-vault encrypt /path/to/the/unencrypted/secret/file.yml`

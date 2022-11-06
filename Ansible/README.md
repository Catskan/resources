# Ansible command line notes

##### Run a playbook :

`ansible-playbook -i inventory/file/path.yml /ansible/playbook/file/path.yml`

*Example :*
`ansible-playbook -i /share/Ansible/Inventory/hosts.yaml /share/Ansible/Macbook/Remove-FondueDeDeco.yaml`


*Encrypt a secret file:*

`ansible-vault encrypt /path/to/the/unencrypted/secret/file.yml`

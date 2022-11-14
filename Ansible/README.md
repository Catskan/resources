# Ansible command line notes

##### Run a playbook :

`ansible-playbook -i inventory/file/path.yml /ansible/playbook/file/path.yml`

*Example :*
`ansible-playbook -i /share/Ansible/Inventory/hosts.yaml /share/Ansible/Macbook/Remove-FondueDeDeco.yaml`

ansible-playbook -i /share/Ansible/Inventory/hosts.yaml /share/Ansible/main_windows_playbook.yml --ask-vault-password

ansible-playbook -i /share/Ansible/Inventory/hosts.yaml /share/Ansible/main_remove_softwares.yml


*Encrypt a secret file:*

`ansible-vault encrypt /path/to/the/unencrypted/secret/file.yml`
ansible-vault encrypt /share/Ansible/Roles/windows_common/vars/aurelien-gaming-vars-secrets.yml
ansible-vault decrypt /share/Ansible/Roles/windows_common/vars/aurelien-gaming-vars-secrets.yml

*Encrypt only one String*
`ansible-vault encrypt_string --vault-password-file /share/Ansible/Variables/w11-VM/W11-VM-secrets.yml 'password-value' --name 'ansible_w11_utm_password'`

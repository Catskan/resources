# Ansible command line notes

##### Run a playbook :

`ansible-playbook -i inventory/file/path.yml /ansible/playbook/file/path.yml`

*Example :*
`ansible-playbook -i /share/git/resources/Inventory/hosts.yaml /share/git/resources/Ansible/Macbook/Remove-FondueDeDeco.yaml`

ansible-playbook -i /share/git/resources/Ansible/Inventory/hosts.yaml /share/git/resources//Ansible/main_windows_playbook.yml --ask-vault-password

ansible-playbook -i /share/git/resources/Ansible/Inventory/hosts.yaml /share/git/resources//Ansible/main_linux-arch_playbook.yml --ask-vault-password --start-at-task

ansible-playbook -i /share/git/resources/Ansible/Inventory/hosts.yaml /share/git/resources//Ansible/main_remove_softwares.yml



*Encrypt a secret file:*

`ansible-vault encrypt /path/to/the/unencrypted/secret/file.yml`
ansible-vault encrypt /share/git/resources/Ansible/Roles/windows_common/vars/aurelien-gaming-vars-secrets.yml
ansible-vault decrypt /share/git/resources/Ansible/Roles/windows_common/vars/aurelien-gaming-vars-secrets.yml

*Encrypt only one String*
`ansible-vault encrypt_string --vault-password-file /share/Ansible/Variables/w11-VM/W11-VM-secrets.yml 'password-value' --name 'ansible_w11_utm_password'`

ansible-vault encrypt /share/git/resources/Ansible/Roles/windows_common/vars/common_secrets.yml
ansible-vault decrypt /share/git/resources/Roles/windows_common/vars/aurelien-gaming-vars-secrets.yml

ansible-vault encrypt_string -- '=£Abgbabgb06£="' --name ‘ansible_password’
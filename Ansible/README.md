# Ansible

Configuration automatisée des machines persos, lancée **depuis le MacBook contrôleur**. Secrets dans une base KeePass sur le NAS Synology (`/Volumes/home/Drive/Vault/Aurel-vault.kdbx` par défaut — le partage SMB `home` doit être monté), master password prompté à chaque run. Override via `KEEPASS_LOCATION` pour pointer une copie locale.

Plus de pipeline cloud : ni AWS, ni Vagrant, ni container Debian-Ansible. Seul reste un workflow GitHub Actions de lint (`.github/workflows/ansible-lint.yml`, yamllint + ansible-lint). Tous les runs tournent en local.

## Setup initial (une fois sur le MacBook)

```bash
brew install ansible
ansible-galaxy collection install ansible.windows community.windows community.general community.docker viczem.keepass
pip3 install --user pykeepass pyyaml    # pykeepass = lookup KeePass (+ lxml transitif) ; pyyaml = scripts/inspect_keepass.py
```

## Lancer un run

```bash
cd Ansible/
make windows                       # cible Windows complet
make linux                         # cible Arch Linux laptop
make uninstall-bloat               # juste les AppX bloatware
make check-windows                 # dry-run --check --diff
make windows ARGS='--tags rdp,wol' # sous-ensemble par tags
make ping-windows                  # win_ping de validation
make lint                          # yamllint + ansible-lint
```

Le wrapper `scripts/run.sh` prompte le master password KeePass une fois et exporte `KEEPASS_LOCATION` + `KEEPASS_PSW` avant d'exec `ansible-playbook`. Override possible :

```bash
KEEPASS_LOCATION=/tmp/test.kdbx make windows
```

## Arborescence

```
Ansible/
├── Makefile                             # raccourcis (cf. ci-dessus)
├── ansible.cfg                          # inventory + roles_path fixés, pas de tokens
├── scripts/run.sh                       # wrapper KeePass → ansible-*
├── main_windows_playbook.yml            # → role windows_gaming
├── main_linux_playbook.yml              # → role linux_laptop + common
├── main_remove_softwares.yml            # → include_role tasks_from appx_bloatware.yml
├── playbooks/
│   ├── blog_maman_deploy.yml            # container Docker "fonduededeco" sur le Mac
│   └── blog_maman_remove.yml
├── inventory/
│   ├── hosts.yaml
│   ├── group_vars/
│   │   ├── all/                         # vars communes (Firefox extensions, NAS URL)
│   │   └── windows_hosts/               # WinRM + Windows-common vars
│   └── host_vars/<host>/                # connection.yml + main.yml + secrets.yml
│       ├── aurelien-gaming/             # PC gaming AM5
│       ├── w11-vm-aurel/                # VM W11 sur Mac
│       ├── arch-linux-laptop/
│       └── macbook-air-aurelien/        # cible local (le contrôleur lui-même)
└── roles/
    ├── windows_gaming/
    │   ├── tasks/main.yml               # orchestrateur avec tags
    │   ├── tasks/system_settings.yml    # power plan, RDP, AutoLogon, MS account, WoL, UAC
    │   ├── tasks/user_folders.yml       # User Shell Folders → M:\Aurel
    │   ├── tasks/softwares_{check,download,install,uninstall}.yml
    │   ├── tasks/ms_store_apps.yml      # winget
    │   ├── files/bootstrap_winrm.ps1    # script à lancer manuellement après réinstall
    │   └── templates/synology_config_win.json.j2
    ├── common/                          # Firefox policies cross-platform
    └── linux_laptop/
```

## Secrets via KeePass

Les `secrets.yml` et `connection.yml` font des lookups :

```yaml
ansible_password: "{{ lookup('viczem.keepass.keepass', 'ansible/aurelien-gaming/local_user', 'password') }}"
nas_username: "{{ lookup('viczem.keepass.keepass', 'ansible/aurelien-gaming/nas', 'username') }}"
nas_password: "{{ lookup('viczem.keepass.keepass', 'ansible/aurelien-gaming/nas', 'password') }}"
```

Structure attendue dans `Aurel-vault.kdbx` :

```
ansible/
├── aurelien-gaming/
│   ├── local_user                  (Aurel / pw du compte)
│   ├── microsoft_account           (email / pw MS)
│   ├── ubisoft_connect             (user / pw Ubisoft)
│   └── nas                         (user / pw Synology)
├── w11-vm-aurel/
│   └── local_user                  (Aurel / pw du compte VM)
├── arch-linux-laptop/
│   └── sudo                        (pw sudo)
└── macbook-air-aurelien/
    └── dockerhub                   (user / pw Docker Hub, pour blog_maman_deploy)
```

## Tags disponibles (rôle `windows_gaming`)

| Tag                                            | Effet                                            |
| ---------------------------------------------- | ------------------------------------------------ |
| `bootstrap`                                    | WinRM startup, UAC, AdminAutoLogon (1ʳᵉ install) |
| `system`                                       | power plan, services, MS account                 |
| `rdp`, `wol`                                   | les sous-systèmes                                |
| `user_folders`                                 | redirection User Shell Folders sur `M:\Aurel`    |
| `softwares`                                    | cycle complet (check + download + install)       |
| `softwares_{check,download,install,uninstall}` | chaque étape isolément                           |
| `ms_store`                                     | apps via winget                                  |
| `firefox`                                      | policies Firefox (du rôle `common`)              |
| `cleanup`                                      | alias `softwares_uninstall`                      |

## Réinstallation d'un PC Windows from scratch

1. **Installer Windows 11 24H2** depuis la clé USB. Bypass du compte Microsoft pendant l'OOBE :
   - À l'écran "se connecter avec Microsoft", `Shift+F10` puis `OOBE\BYPASSNRO`.
   - Créer le compte local `Aurel`.
2. **Côté machine cible** : exécuter `roles/windows_gaming/files/bootstrap_winrm.ps1` en PowerShell admin (transit via clé USB, partage SMB ou copie/colle dans une session locale).
3. **Côté MacBook (contrôleur)** : valider la connectivité
   ```bash
   make ping-windows
   ```
4. **Run complet** :
   ```bash
   make windows
   ```

## CI

`.github/workflows/ansible-lint.yml` lance `yamllint` + `ansible-lint` sur Ubuntu hosted à chaque push touchant `Ansible/**`. C'est le seul reliquat de l'ancien pipeline cloud — utile pour valider la syntaxe.

Local équivalent : `make lint`.

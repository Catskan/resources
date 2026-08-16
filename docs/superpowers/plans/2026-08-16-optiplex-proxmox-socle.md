# Socle Ansible de l'hôte Proxmox Optiplex — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter le Dell OptiPlex 7090 Micro (hôte Proxmox VE) à l'inventaire Ansible, avec dépôts APT sains, hygiène disque, plafond ARC ZFS, durcissement SSH et rattachement au tailnet — sans régression sur le Wyse ni sur les Macs.

**Architecture:** `proxmox_hosts` devient un groupe parent avec deux enfants (`proxmox_wyse`, `proxmox_optiplex`). L'hygiène d'hyperviseur, aujourd'hui enfouie dans le rôle `proxmox_claude_lxc`, est extraite dans un rôle `proxmox_host_maintenance` partagé par les deux hôtes. Le rôle `sshd_hardening`, macOS-only en pratique, gagne des branches Linux sans que les gardes Darwin existantes ne bougent.

**Tech Stack:** Ansible (`ansible.builtin` : `stat`, `copy`, `assert`, `systemd_service`, `import_tasks`), Proxmox VE 9 (base Debian 13), ZFS on Linux, OpenSSH, Headscale/Tailscale.

**Spec:** `docs/superpowers/specs/2026-08-16-optiplex-proxmox-socle-design.md`

## Global Constraints

Ces contraintes s'appliquent à **toutes** les tâches ci-dessous.

- **Toutes les commandes se lancent depuis `Ansible/`** — c'est le répertoire qui contient le `Makefile` et `ansible.cfg`.
- **Tout passe par `./scripts/run.sh`**, qui prompte le master password KeePass. Le partage NAS doit être monté : sans `/Volumes/home/Drive/Vault/Aurel-vault.kdbx`, le script abandonne avec « KeePass DB introuvable ». Override possible : `KEEPASS_LOCATION=/autre/chemin.kdbx`.
- **Connexion à l'Optiplex** : `root@192.168.1.100`, port **2125**, par clé. Aucun `become`, aucun secret KeePass pour cet hôte.
- **Valeurs ARC, littérales** : `pve_zfs_arc_max_bytes: 4294967296` (4 GiB), `pve_zfs_arc_min_bytes: 1073741824` (1 GiB). Elles n'existent que dans `host_vars/optiplex-proxmox/main.yml`.
- **Durcissement SSH de l'Optiplex** : `sshd_allowed_users: [root]`, `sshd_permit_root_login: "prohibit-password"`. Les autres directives restent aux défauts du rôle.
- **Ne JAMAIS définir `sshd_port` pour `optiplex-proxmox`.** La tâche qui le consomme est gardée sur macOS ; la déclarer laisserait croire qu'Ansible gère le 2125 alors qu'il reste manuel.
- **Ne JAMAIS modifier les gardes `when: ansible_os_family == "Darwin"` existantes** de `roles/sshd_hardening/`. On n'ajoute que des branches `!= "Darwin"`. C'est par SSH sur ces Macs que passe `run-on`.
- **`make lint` doit être vert avant chaque commit** (`yamllint .` + `ansible-lint main_*.yml`).
- **Messages de commit en français**, convention du repo : `type(scope): sujet` en minuscules, corps expliquant le pourquoi.

---

### Task 1: Groupe parent Proxmox et recâblage des playbooks existants

Aucun nouvel hôte à ce stade. On prouve que la restructuration des groupes ne change **rien** à ce qui est planifié pour le Wyse.

**Files:**

- Modify: `Ansible/inventory/hosts.yaml`
- Modify: `Ansible/main_wyse_playbook.yml`
- Modify: `Ansible/main_headscale_playbook.yml`

**Interfaces:**

- Produces: les groupes `proxmox_wyse` (contenant `wyse-proxmox`) et `proxmox_hosts` (parent). Les tâches 4 et 9 s'appuient sur ce parent ; la tâche 4 ajoute l'enfant `proxmox_optiplex`.

- [ ] **Step 1: Capturer la référence de non-régression**

```bash
cd Ansible/
./scripts/run.sh ansible-playbook main_wyse_playbook.yml --list-hosts > /tmp/wyse-hosts-avant.txt
./scripts/run.sh ansible-playbook main_headscale_playbook.yml --list-hosts > /tmp/hs-hosts-avant.txt
cat /tmp/wyse-hosts-avant.txt
```

`--list-hosts` n'ouvre aucune connexion : il n'affiche que les hôtes que chaque play viserait. C'est exactement ce que la modification risque de casser.

- [ ] **Step 2: Restructurer le groupe dans l'inventaire**

Dans `Ansible/inventory/hosts.yaml`, remplacer :

```yaml
proxmox_hosts:
  hosts:
    wyse-proxmox:
```

par :

```yaml
proxmox_hosts:
  children:
    proxmox_wyse:
      hosts:
        wyse-proxmox:
```

- [ ] **Step 3: Vérifier que la hiérarchie de groupes se résout**

```bash
./scripts/run.sh ansible proxmox_wyse --list-hosts
./scripts/run.sh ansible proxmox_hosts --list-hosts
```

Attendu : les deux commandes listent `wyse-proxmox` — le parent hérite bien des hôtes de son enfant.

À ce stade les playbooks ciblent encore `proxmox_hosts` : ils attraperaient l'Optiplex dès son ajout en tâche 4. C'est ce que les steps suivants corrigent, et la tâche 4 step 7 est le test qui l'aurait attrapé.

- [ ] **Step 4: Recâbler `main_wyse_playbook.yml`**

Dans le play 1 (`Créer le LXC claude-code sur le Wyse (Proxmox)`), remplacer :

```yaml
hosts: proxmox_hosts
```

par :

```yaml
hosts: proxmox_wyse
```

Le play 2 (`claude_code_hosts`) n'est pas touché.

- [ ] **Step 5: Recâbler `main_headscale_playbook.yml`**

Trois plays ciblent `proxmox_hosts`. Remplacer `hosts: proxmox_hosts` par `hosts: proxmox_wyse` dans **les trois** :

1. `Créer le LXC headscale sur le Wyse (Proxmox)`
2. `Activer /dev/net/tun sur le CT claude-code (prérequis tailscale kernel-mode)`
3. `Rattacher l'hôte Proxmox (Wyse) au tailnet (client tailscale)`

Mettre également à jour le bloc de commentaires en tête de fichier :

```yaml
# make headscale                                   → les quatre plays (déploiement complet)
# make headscale ARGS='--limit proxmox_wyse'       → création du CT headscale seule
# make headscale ARGS='--limit headscale_hosts'    → (re)config du serveur headscale
# make headscale ARGS='--limit claude_code_hosts'  → (re)join du client tailscale seul
```

- [ ] **Step 6: Vérifier l'absence de régression**

```bash
./scripts/run.sh ansible-playbook main_wyse_playbook.yml --list-hosts > /tmp/wyse-hosts-apres.txt
./scripts/run.sh ansible-playbook main_headscale_playbook.yml --list-hosts > /tmp/hs-hosts-apres.txt
diff /tmp/wyse-hosts-avant.txt /tmp/wyse-hosts-apres.txt && echo "WYSE OK"
diff /tmp/hs-hosts-avant.txt /tmp/hs-hosts-apres.txt && echo "HEADSCALE OK"
```

Attendu : les deux `diff` sont vides, `WYSE OK` et `HEADSCALE OK` s'affichent. Si un diff n'est pas vide, un `hosts:` a été oublié ou mal orthographié — corriger avant de continuer.

- [ ] **Step 7: Lint**

```bash
make lint
```

Attendu : aucune erreur.

- [ ] **Step 8: Commit**

```bash
git add inventory/hosts.yaml main_wyse_playbook.yml main_headscale_playbook.yml
git commit -m "refactor(inventory): proxmox_hosts devient un groupe parent

Prépare l'arrivée d'un second hyperviseur : les plays propres au Wyse
ciblent désormais proxmox_wyse, et proxmox_hosts est réservé à ce qui
vaut pour TOUS les hôtes Proxmox.

Vérifié par --list-hosts identique avant/après sur les deux playbooks."
```

---

### Task 2: Extraire l'hygiène d'hôte dans un rôle `proxmox_host_maintenance`

**Files:**

- Create: `Ansible/roles/proxmox_host_maintenance/tasks/main.yml` (par `git mv`)
- Create: `Ansible/roles/proxmox_host_maintenance/files/{pct-fstrim,disk-alert}` (par `git mv`)
- Create: `Ansible/roles/proxmox_host_maintenance/handlers/main.yml` (par `git mv`)
- Create: `Ansible/roles/proxmox_host_maintenance/defaults/main.yml`
- Create: `Ansible/roles/proxmox_host_maintenance/meta/main.yml`
- Modify: `Ansible/roles/proxmox_claude_lxc/tasks/main.yml` (retrait des 3 dernières lignes)
- Modify: `Ansible/roles/proxmox_claude_lxc/defaults/main.yml` (retrait de `pve_journal_max_use`)
- Modify: `Ansible/main_wyse_playbook.yml`

**Interfaces:**

- Consumes: le groupe `proxmox_wyse` de la tâche 1.
- Produces: le rôle `proxmox_host_maintenance`, variable `pve_journal_max_use` (défaut `200M`). La tâche 5 y ajoutera `tasks/zfs_arc.yml`, les tâches 7 et 8 l'appelleront depuis le playbook Optiplex.

- [ ] **Step 1: Capturer la référence**

```bash
cd Ansible/
./scripts/run.sh ansible-playbook main_wyse_playbook.yml --list-tasks > /tmp/wyse-tasks-avant.txt
grep -c "maint" /tmp/wyse-tasks-avant.txt
```

Attendu : `4` — les quatre tâches préfixées `[maint]`.

- [ ] **Step 2: Déplacer les fichiers avec `git mv`**

`git mv` préserve l'historique — ne pas copier-coller à la main.

```bash
mkdir -p roles/proxmox_host_maintenance/{tasks,files,handlers,defaults,meta}
git mv roles/proxmox_claude_lxc/tasks/maintenance.yml roles/proxmox_host_maintenance/tasks/main.yml
git mv roles/proxmox_claude_lxc/files/pct-fstrim      roles/proxmox_host_maintenance/files/pct-fstrim
git mv roles/proxmox_claude_lxc/files/disk-alert      roles/proxmox_host_maintenance/files/disk-alert
git mv roles/proxmox_claude_lxc/handlers/main.yml     roles/proxmox_host_maintenance/handlers/main.yml
```

Le handler `Redémarrer systemd-journald` était le seul de `proxmox_claude_lxc` et n'était notifié que par `maintenance.yml` — il part donc en entier. (Vérifié : aucun `notify` dans `roles/proxmox_claude_lxc/tasks/main.yml`.)

- [ ] **Step 3: Corriger l'en-tête de `tasks/main.yml` du nouveau rôle**

Dans `Ansible/roles/proxmox_host_maintenance/tasks/main.yml`, remplacer le bloc de commentaires de tête par :

```yaml
---
# Hygiène disque d'un hôte Proxmox. Évite le retour de la saturation qui a mis
# pve-root à 100 % le 2026-07-13 (build cache Docker dans le CT + blocs .raw
# jamais rendus à l'hôte).
#   - pct fstrim hebdo : rend à l'hôte l'espace libéré dans les CT
#   - journald plafonné : borne les journaux systemd de l'hôte
#   - alerte disque : prévient (journald) avant saturation
#   - plafond ARC ZFS (zfs_arc.yml) : conditionné à la présence de ZFS
# Tags : maintenance, zfs
```

Le reste du fichier (les quatre tâches `[maint]`) n'est pas modifié.

- [ ] **Step 4: Corriger la provenance annoncée dans les deux scripts**

Dans `Ansible/roles/proxmox_host_maintenance/files/pct-fstrim` et `files/disk-alert`, remplacer la ligne :

```sh
# Déposé par Ansible — rôle proxmox_claude_lxc (ne pas éditer à la main).
```

par :

```sh
# Déposé par Ansible — rôle proxmox_host_maintenance (ne pas éditer à la main).
```

Sans quoi le commentaire ment sur l'origine du fichier, ce qui coûte cher au prochain débogage.

- [ ] **Step 5: Créer `defaults/main.yml`**

Créer `Ansible/roles/proxmox_host_maintenance/defaults/main.yml` :

```yaml
---
# Plafond des journaux systemd de l'hôte.
pve_journal_max_use: 200M

# Plafond ARC de ZFS — VOLONTAIREMENT VIDE. À définir par hôte dans
# inventory/host_vars/<host>/main.yml : le bon plafond dépend de la RAM de la
# machine. Sans valeur, tout le bloc de tasks/zfs_arc.yml est sauté.
pve_zfs_arc_max_bytes: ""
pve_zfs_arc_min_bytes: ""
```

- [ ] **Step 6: Créer `meta/main.yml`**

Créer `Ansible/roles/proxmox_host_maintenance/meta/main.yml` :

```yaml
---
galaxy_info:
  role_name: proxmox_host_maintenance
  description: Hygiène d'un hôte Proxmox (fstrim des CT, alerte disque, journald, plafond ARC ZFS)
  min_ansible_version: "2.14"
```

- [ ] **Step 7: Retirer l'import et la variable de `proxmox_claude_lxc`**

Dans `Ansible/roles/proxmox_claude_lxc/tasks/main.yml`, supprimer les trois dernières lignes :

```yaml
- name: Maintenance disque de l'hôte Proxmox (fstrim/journald/alerte)
  ansible.builtin.import_tasks: maintenance.yml
  tags: maintenance
```

Dans `Ansible/roles/proxmox_claude_lxc/defaults/main.yml`, supprimer les deux dernières lignes :

```yaml
# Maintenance disque de l'hôte (tasks/maintenance.yml) : plafond journaux systemd.
pve_journal_max_use: 200M
```

- [ ] **Step 8: Brancher le rôle sur le play Wyse**

Dans `Ansible/main_wyse_playbook.yml`, play 1, remplacer :

```yaml
roles:
  - role: proxmox_claude_lxc
```

par :

```yaml
roles:
  - role: proxmox_claude_lxc
  - role: proxmox_host_maintenance
    tags: [maintenance]
```

- [ ] **Step 9: Vérifier que les tâches de maintenance sont toujours planifiées**

```bash
./scripts/run.sh ansible-playbook main_wyse_playbook.yml --list-tasks > /tmp/wyse-tasks-apres.txt
grep -c "maint" /tmp/wyse-tasks-apres.txt
./scripts/run.sh ansible-playbook main_wyse_playbook.yml --list-tasks --tags maintenance
```

Attendu : `4` de nouveau, et le run filtré par tag liste bien les quatre tâches `[maint]`. Le tag `maintenance` conserve donc son comportement d'origine.

- [ ] **Step 10: Lint et commit**

```bash
make lint
git add -A roles/proxmox_host_maintenance roles/proxmox_claude_lxc main_wyse_playbook.yml
git commit -m "refactor(proxmox): extrait l'hygiène d'hôte dans proxmox_host_maintenance

Ces tâches concernent l'hyperviseur, pas la création d'un conteneur :
les laisser dans proxmox_claude_lxc empêchait de les appliquer à un
second hôte Proxmox sans y créer aussi le CT claude-code.

git mv pour préserver l'historique. Vérifié par --list-tasks : les
quatre tâches [maint] sont toujours planifiées sur le Wyse, et le tag
maintenance fonctionne à l'identique."
```

---

### Task 3: Commiter `proxmox_repos` et supprimer les `pre_tasks` inline

**Files:**

- Create (commit de fichiers déjà présents en non suivi) : `Ansible/roles/proxmox_repos/tasks/main.yml`, `Ansible/roles/proxmox_repos/meta/main.yml`
- Modify: `Ansible/main_headscale_playbook.yml`

**Interfaces:**

- Produces: le rôle `proxmox_repos`, utilisé par les tâches 7 et 9.

- [ ] **Step 1: Vérifier que le rôle est bien présent en non suivi**

```bash
cd Ansible/
git status --short roles/proxmox_repos/
cat roles/proxmox_repos/tasks/main.yml
```

Attendu : `?? roles/proxmox_repos/`, et le fichier contient trois tâches (désactivation enterprise, ajout de `pve-no-subscription`, `apt update`). **Ne rien modifier dans ce rôle** — il est correct tel quel.

Si le répertoire est absent, il a été perdu : le recréer à l'identique depuis la spec §2 avant de continuer.

- [ ] **Step 2: Capturer la référence**

```bash
./scripts/run.sh ansible-playbook main_headscale_playbook.yml --list-tasks > /tmp/hs-tasks-avant.txt
grep -n "enterprise" /tmp/hs-tasks-avant.txt
```

Attendu : deux tâches `pre_tasks` mentionnant les dépôts entreprise.

- [ ] **Step 3: Remplacer les `pre_tasks` par le rôle**

Dans `Ansible/main_headscale_playbook.yml`, dans le play `Rattacher l'hôte Proxmox (Wyse) au tailnet (client tailscale)`, supprimer tout le bloc `pre_tasks:` (du commentaire « Le dépôt pve-enterprise… » jusqu'à la fin de la tâche « Désactiver les dépôts entreprise ») et le remplacer par un rôle en tête de liste. Le play devient :

```yaml
# L'hôte Proxmox n'est pas joignable en 8006 depuis l'extérieur (Freebox refuse un
# forward de port public < 32768). On le met sur le tailnet → la WebUI est atteinte
# via https://<IP-tailnet-du-Wyse>:8006 depuis n'importe quel nœud (Mac). L'hôte a
# /dev/net/tun nativement (hyperviseur) → pas de prérequis tun comme pour le CT.
- name: Rattacher l'hôte Proxmox (Wyse) au tailnet (client tailscale)
  hosts: proxmox_wyse
  become: true
  gather_facts: true
  roles:
    # Sans ça, le dépôt pve-enterprise (401 sans abonnement) fait échouer tout
    # `apt update`, et tailscale_client plante dès l'installation du paquet.
    - role: proxmox_repos
    - role: tailscale_client
```

- [ ] **Step 4: Vérifier que le travail est toujours planifié**

```bash
./scripts/run.sh ansible-playbook main_headscale_playbook.yml --list-tasks > /tmp/hs-tasks-apres.txt
grep -n "enterprise\|no-subscription" /tmp/hs-tasks-apres.txt
```

Attendu : les tâches du rôle `proxmox_repos` apparaissent (désactivation enterprise, activation `pve-no-subscription`, mise à jour du cache) à la place des deux `pre_tasks`. Le rôle en fait **plus** que l'inline : c'est voulu.

- [ ] **Step 5: Lint et commit**

```bash
make lint
git add roles/proxmox_repos main_headscale_playbook.yml
git commit -m "feat(proxmox): commite le rôle proxmox_repos et remplace le bricolage inline

Le rôle traînait en non suivi depuis des semaines pendant que
main_headscale_playbook.yml refaisait le même travail en pre_tasks, en
moins complet (pas de format .list legacy, pas de pve-no-subscription).

Une seule source de vérité pour les dépôts APT des hôtes Proxmox."
```

---

### Task 4: Entrée d'inventaire de l'Optiplex

**Files:**

- Modify: `Ansible/inventory/hosts.yaml`
- Create: `Ansible/inventory/host_vars/optiplex-proxmox/connection.yml`
- Create: `Ansible/inventory/host_vars/optiplex-proxmox/main.yml`

**Interfaces:**

- Consumes: le groupe parent `proxmox_hosts` de la tâche 1.
- Produces: l'hôte `optiplex-proxmox` dans le groupe `proxmox_optiplex`, et les variables `pve_zfs_arc_max_bytes`, `pve_zfs_arc_min_bytes`, `sshd_allowed_users`, `sshd_permit_root_login` consommées par les tâches 5, 7 et 8.

- [ ] **Step 1: Vérifier que l'hôte n'existe pas encore (le test échoue)**

```bash
cd Ansible/
./scripts/run.sh ansible proxmox_optiplex -m ansible.builtin.ping
```

Attendu : échec — `Could not match supplied host pattern, ignoring: proxmox_optiplex` et zéro hôte traité.

- [ ] **Step 2: Ajouter le groupe enfant dans l'inventaire**

Dans `Ansible/inventory/hosts.yaml`, sous `proxmox_hosts.children`, ajouter le second enfant :

```yaml
proxmox_hosts:
  children:
    proxmox_wyse:
      hosts:
        wyse-proxmox:
    proxmox_optiplex:
      hosts:
        optiplex-proxmox:
```

- [ ] **Step 3: Créer le fichier de connexion**

Créer `Ansible/inventory/host_vars/optiplex-proxmox/connection.yml` :

```yaml
# Hôte Proxmox VE (Dell OptiPlex 7090 Micro) — LAN de la maison, accès direct.
# Nœud de runtime : Immich, vinted-bot, pokemon-monitor à venir. Le NAS Synology
# reste le stockage de masse.
# Root en direct : c'est le mode natif d'un hyperviseur Proxmox, et ça évite de
# stocker un mot de passe sudo (sudo n'est pas garanti sur une install PVE nue).
# ⚠️ ansible_port EXPLICITE : sshd écoute sur 2125, et le contrôleur (l'Air)
#    remappe par ailleurs `ssh`->2122 dans /etc/services — aucun défaut n'est bon.
ansible_connection: ssh
ansible_host: 192.168.1.100
ansible_port: 2125
ansible_user: root
ansible_ssh_common_args: -o StrictHostKeyChecking=accept-new
```

Aucun `secrets.yml` : root en direct, pas de `become`, donc aucun secret à résoudre.

- [ ] **Step 4: Créer les variables d'hôte**

Créer `Ansible/inventory/host_vars/optiplex-proxmox/main.yml` :

```yaml
---
# Plafond ARC de ZFS. 4 GiB max / 1 GiB min sur 16 Go de RAM : laisse la mémoire
# aux conteneurs applicatifs. Valeur propre à CETTE machine — le rôle
# proxmox_host_maintenance n'a pas de défaut, justement pour éviter qu'un autre
# hôte ZFS hérite d'un plafond calibré ailleurs.
pve_zfs_arc_max_bytes: 4294967296
pve_zfs_arc_min_bytes: 1073741824

# Durcissement SSH (rôle sshd_hardening).
# root par clé uniquement : c'est le modèle de connexion ci-dessus. Le défaut du
# rôle (PermitRootLogin "no") verrouillerait l'hôte, et l'assert anti-lockout du
# rôle ne contrôle que AllowUsers — il ne l'aurait pas vu.
# AllowUsers est le point d'extension prévu si un compte de service apparaît.
sshd_allowed_users:
  - root
sshd_permit_root_login: "prohibit-password"

# ⚠️ NE PAS définir sshd_port ici : la tâche qui le consomme est gardée sur macOS.
#    Le port 2125 reste réglé à la main dans /etc/ssh/sshd_config sur l'hôte.
```

- [ ] **Step 5: Vérifier la connexion**

```bash
./scripts/run.sh ansible proxmox_optiplex -m ansible.builtin.ping
```

Attendu : `optiplex-proxmox | SUCCESS => {"ping": "pong"}`.

En cas de `Permission denied (publickey)` : la clé publique du contrôleur n'est pas dans `/root/.ssh/authorized_keys` de l'Optiplex. C'est le prérequis d'amorçage de la spec §1 — l'ajouter sur l'hôte, puis relancer.

- [ ] **Step 6: Vérifier le comportement de `become` sur cet hôte**

```bash
./scripts/run.sh ansible proxmox_optiplex -m ansible.builtin.command -a 'id -un' --become
```

Attendu : `root`.

Ce contrôle n'est pas décoratif : plusieurs tâches du rôle `sshd_hardening` portent `become: true` en dur. Si cette commande échoue avec `sudo: command not found`, installer sudo une fois sur l'hôte (`apt install -y sudo`, après la tâche 7 qui assainit les dépôts) et relancer. Détecter ça maintenant évite de le découvrir pendant la tâche 8, la plus risquée.

- [ ] **Step 7: Vérifier que le Wyse n'a pas bougé**

```bash
./scripts/run.sh ansible-playbook main_wyse_playbook.yml --list-hosts
```

Attendu : les plays listent `wyse-proxmox` seul. **Si `optiplex-proxmox` apparaît, la tâche 1 a été mal appliquée** — corriger avant tout run réel.

- [ ] **Step 8: Lint et commit**

```bash
make lint
git add inventory/hosts.yaml inventory/host_vars/optiplex-proxmox/
git commit -m "feat(inventory): ajoute l'hôte optiplex-proxmox

Dell OptiPlex 7090 Micro, Proxmox VE sur ZFS, LAN 192.168.1.100:2125,
root par clé. Destiné à porter Immich, vinted-bot et pokemon-monitor
pour soulager le NAS, qui reste le stockage.

Vérifié : ping OK, et les plays du Wyse ne l'attrapent pas."
```

---

### Task 5: Plafond ARC de ZFS

**Files:**

- Create: `Ansible/roles/proxmox_host_maintenance/tasks/zfs_arc.yml`
- Modify: `Ansible/roles/proxmox_host_maintenance/tasks/main.yml` (ajout de l'import en fin de fichier)
- Modify: `Ansible/roles/proxmox_host_maintenance/handlers/main.yml` (deux handlers ajoutés)

**Interfaces:**

- Consumes: `pve_zfs_arc_max_bytes` et `pve_zfs_arc_min_bytes` de la tâche 4 ; le rôle de la tâche 2.
- Produces: le tag `zfs`, utilisable via `make optiplex ARGS='--tags zfs'` (tâche 7).

- [ ] **Step 1: Créer `tasks/zfs_arc.yml`**

Créer `Ansible/roles/proxmox_host_maintenance/tasks/zfs_arc.yml` :

```yaml
---
# Plafond ARC de ZFS, avec DOUBLE GARDE :
#   1. le module zfs doit être chargé (le Wyse est sur LVM-thin → tout est sauté)
#   2. une valeur doit être définie pour cet hôte (les defaults du rôle sont vides)
#
# Contresens fréquent à éviter : depuis PVE 8.1 l'installeur pose déjà une limite
# à 10 % de la RAM. Le problème qu'on corrige ici est qu'elle est trop BASSE, pas
# trop haute. Le vieux défaut « 50 % de la RAM » ne vaut que pour les installs
# antérieures ou les pools ajoutés après coup.
#
# Tag : zfs

- name: "[zfs] Détecter le module ZFS"
  ansible.builtin.stat:
    path: /sys/module/zfs
  register: zfs_module

- name: "[zfs] Détecter proxmox-boot-tool (ESP synchronisées)"
  ansible.builtin.stat:
    path: /etc/kernel/proxmox-boot-uuids
  register: proxmox_boot_uuids

- name: "[zfs] Réglage du plafond ARC"
  when:
    - zfs_module.stat.exists
    - pve_zfs_arc_max_bytes | string | length > 0
    - pve_zfs_arc_min_bytes | string | length > 0
  block:
    - name: "[zfs] Déposer /etc/modprobe.d/99-zfs.conf (persistant, appliqué au boot)"
      ansible.builtin.copy:
        dest: /etc/modprobe.d/99-zfs.conf
        owner: root
        group: root
        mode: "0644"
        content: |
          # Géré par Ansible — rôle proxmox_host_maintenance. Ne pas éditer à la main.
          options zfs zfs_arc_max={{ pve_zfs_arc_max_bytes }}
          options zfs zfs_arc_min={{ pve_zfs_arc_min_bytes }}
      notify:
        - Régénérer l'initramfs
        - Rafraîchir proxmox-boot-tool

    - name: "[zfs] Appliquer le plafond à chaud (évite d'attendre un reboot)"
      ansible.builtin.shell: |
        set -eu
        changed=0
        cur_max=$(cat /sys/module/zfs/parameters/zfs_arc_max)
        cur_min=$(cat /sys/module/zfs/parameters/zfs_arc_min)
        if [ "$cur_max" != "{{ pve_zfs_arc_max_bytes }}" ]; then
          echo {{ pve_zfs_arc_max_bytes }} > /sys/module/zfs/parameters/zfs_arc_max
          changed=1
        fi
        if [ "$cur_min" != "{{ pve_zfs_arc_min_bytes }}" ]; then
          echo {{ pve_zfs_arc_min_bytes }} > /sys/module/zfs/parameters/zfs_arc_min
          changed=1
        fi
        echo "changed=$changed"
      register: zfs_arc_live
      changed_when: "'changed=1' in zfs_arc_live.stdout"
```

Le plafond est écrit **avant** le plancher dans le fichier comme dans le shell : ZFS refuse un `arc_min` supérieur à l'`arc_max` courant, et on monte ici le plafond depuis ~1,6 GiB.

- [ ] **Step 2: Importer le fichier depuis `tasks/main.yml`**

Ajouter en **fin** de `Ansible/roles/proxmox_host_maintenance/tasks/main.yml` :

```yaml
- name: Plafond ARC de ZFS (conditionné à la présence du module)
  ansible.builtin.import_tasks: zfs_arc.yml
  tags: zfs
```

- [ ] **Step 3: Ajouter les deux handlers**

Ajouter à la fin de `Ansible/roles/proxmox_host_maintenance/handlers/main.yml` :

```yaml
# ⚠️ ORDRE SIGNIFICATIF : Ansible exécute les handlers dans leur ordre de
# DÉFINITION, pas dans l'ordre des notify. L'initramfs doit être régénéré avant
# que proxmox-boot-tool ne recopie les noyaux vers les ESP.
- name: Régénérer l'initramfs
  ansible.builtin.command: update-initramfs -u -k all
  changed_when: true

- name: Rafraîchir proxmox-boot-tool
  ansible.builtin.command: proxmox-boot-tool refresh
  changed_when: true
  when: proxmox_boot_uuids.stat.exists
```

- [ ] **Step 4: Vérifier que le Wyse est bien épargné**

```bash
cd Ansible/
./scripts/run.sh ansible-playbook main_wyse_playbook.yml --list-tasks --tags zfs
```

Attendu : les tâches `[zfs]` sont **listées** (le filtrage par tag est statique), mais elles seront sautées à l'exécution puisque `/sys/module/zfs` n'existe pas sur un hôte LVM-thin. C'est la garde runtime qui protège, pas le tag.

- [ ] **Step 5: Dry-run sur l'Optiplex**

```bash
./scripts/run.sh ansible optiplex-proxmox -m ansible.builtin.stat -a 'path=/sys/module/zfs'
```

Attendu : `"exists": true`. Si c'est `false`, l'hôte n'est pas sur ZFS et la spec est à revoir avant d'aller plus loin.

- [ ] **Step 6: Lint et commit**

```bash
make lint
git add roles/proxmox_host_maintenance/
git commit -m "feat(proxmox): plafond ARC ZFS conditionné à la présence du module

Double garde : module zfs chargé ET valeur définie pour l'hôte. Le Wyse
(LVM-thin) est donc épargné sans condition d'inventaire, et aucun hôte
ZFS futur n'hérite d'un plafond calibré pour une autre quantité de RAM.

Appliqué à chaud en plus du modprobe.d, pour ne pas dépendre d'un reboot.
Handlers dans l'ordre initramfs puis proxmox-boot-tool : Ansible les
exécute dans leur ordre de définition."
```

---

### Task 6: Étendre `sshd_hardening` à Linux

Cette tâche **n'applique rien** sur l'Optiplex — elle rend le rôle utilisable. L'application se fait en tâche 8.

**Files:**

- Modify: `Ansible/roles/sshd_hardening/tasks/main.yml`
- Modify: `Ansible/roles/sshd_hardening/handlers/main.yml`

**Interfaces:**

- Produces: le handler `Recharger sshd (Linux)` et le fait `sshd_reload_unit`. Consommés par la tâche 8.

- [ ] **Step 1: Capturer la référence macOS**

```bash
cd Ansible/
./scripts/run.sh ansible-playbook main_macos_playbook.yml --check --diff > /tmp/macos-avant.txt 2>&1
tail -5 /tmp/macos-avant.txt
```

Attendu : un récapitulatif `PLAY RECAP` avec les Macs. Ce fichier est la preuve de non-régression : c'est par SSH sur ces machines que passe `run-on`.

- [ ] **Step 2: Ajouter les tâches Linux avant le dépôt du drop-in**

Dans `Ansible/roles/sshd_hardening/tasks/main.yml`, insérer ces trois tâches **juste avant** la tâche `Déposer le drop-in de durcissement SSH` :

```yaml
# --- Branche Linux (Debian/Proxmox) -------------------------------------------
# Le rôle a d'abord été écrit pour macOS : ses handlers étaient tous gardés sur
# Darwin, donc sur Linux le drop-in était écrit mais sshd n'était JAMAIS rechargé
# — un run vert sur un hôte non durci. Les tâches ci-dessous ferment ce trou.

- name: Vérifier que sshd lit le répertoire drop-in (Linux)
  become: true
  ansible.builtin.command: grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config
  register: sshd_include_check
  changed_when: false
  failed_when: false
  check_mode: false
  when: ansible_os_family != "Darwin"

- name: Échouer si l'Include du drop-in est absent (le durcissement serait décoratif)
  ansible.builtin.assert:
    that:
      - sshd_include_check.rc == 0
    fail_msg: >-
      /etc/ssh/sshd_config ne contient pas « Include /etc/ssh/sshd_config.d/*.conf ».
      Le fichier déposé par ce rôle ne serait jamais lu, et le run serait vert
      pour rien. Ajouter la ligne en TÊTE du fichier (sshd retient la PREMIÈRE
      occurrence de chaque directive), puis relancer.
    success_msg: Le drop-in sshd_config.d est bien inclus.
  when: ansible_os_family != "Darwin"

- name: Déterminer l'unité systemd à recharger (Debian 13/PVE 9 active ssh.socket)
  become: true
  ansible.builtin.command: systemctl is-enabled ssh.socket
  register: sshd_socket_state
  changed_when: false
  failed_when: false
  check_mode: false
  when: ansible_os_family != "Darwin"

- name: Retenir l'unité à recharger
  ansible.builtin.set_fact:
    sshd_reload_unit: "{{ 'ssh.socket' if sshd_socket_state.stdout | trim == 'enabled' else 'ssh.service' }}"
  when: ansible_os_family != "Darwin"
```

- [ ] **Step 3: Notifier aussi le handler Linux**

Dans la même tâche `Déposer le drop-in de durcissement SSH`, remplacer :

```yaml
notify: Recharger sshd
```

par :

```yaml
notify:
  - Recharger sshd
  - Recharger sshd (Linux)
```

Les deux handlers portent des gardes d'OS mutuellement exclusives : un seul s'exécutera.

- [ ] **Step 4: Ajouter le handler Linux**

Ajouter à la fin de `Ansible/roles/sshd_hardening/handlers/main.yml` :

```yaml
# Pendant Linux des deux handlers Darwin ci-dessus. `ssh.socket` n'accepte pas
# `reloaded` → restart ; `ssh.service` accepte reload, moins brutal.
# Un restart de sshd ne coupe PAS les sessions déjà établies (chacune vit dans
# son propre processus), mais il faut malgré tout valider une NOUVELLE connexion
# avant de fermer la session courante.
- name: Recharger sshd (Linux)
  become: true
  ansible.builtin.systemd_service:
    name: "{{ sshd_reload_unit }}"
    state: "{{ 'restarted' if sshd_reload_unit == 'ssh.socket' else 'reloaded' }}"
  when: ansible_os_family != "Darwin"
```

- [ ] **Step 5: Vérifier la non-régression macOS**

```bash
./scripts/run.sh ansible-playbook main_macos_playbook.yml --check --diff > /tmp/macos-apres.txt 2>&1
diff /tmp/macos-avant.txt /tmp/macos-apres.txt
```

Le diff **ne sera pas vide** : les quatre tâches ajoutées apparaissent, en `skipping`, puisque leur garde `!= "Darwin"` est fausse sur un Mac. C'est attendu.

Ce qu'il faut vérifier, ligne à ligne :

- toutes les lignes ajoutées sont des `skipping: [macbook-...]` portant le nom d'une des quatre nouvelles tâches ;
- **aucune** ligne concernant une tâche préexistante n'a changé ;
- le `PLAY RECAP` affiche les mêmes compteurs `changed=` et `failed=` qu'avant, seul `skipped=` augmente.

Si un `changed=` ou un `failed=` bouge, arrêter : une garde Darwin a été touchée, ce que les contraintes globales interdisent.

- [ ] **Step 6: Lint et commit**

```bash
make lint
git add roles/sshd_hardening/
git commit -m "feat(sshd): rend le rôle sshd_hardening applicable aux hôtes Linux

Les deux handlers étaient gardés sur Darwin : sur Debian, le drop-in
était déposé, le notify déclenché, le handler skippé — sshd n'était
jamais rechargé et le run restait vert sur un hôte non durci.

Ajoute un handler Linux qui recharge la bonne unité (ssh.socket est
activé par défaut sur Debian 13, dont dérive PVE 9), et un assert sur
la présence de l'Include de sshd_config.d, sans lequel le fichier
déposé ne serait jamais lu.

Les gardes Darwin existantes ne sont pas touchées : le chemin des Macs
est inchangé par construction."
```

---

### Task 7: Playbook Optiplex, Makefile, README, premier run

**Files:**

- Create: `Ansible/main_optiplex_playbook.yml`
- Modify: `Ansible/Makefile`
- Modify: `Ansible/README.md`

**Interfaces:**

- Consumes: `proxmox_repos` (tâche 3), `proxmox_host_maintenance` (tâches 2 et 5), `sshd_hardening` (tâche 6), l'hôte `optiplex-proxmox` (tâche 4).
- Produces: les cibles `make optiplex` et `make check-optiplex`, et les tags `repos`, `maintenance`, `zfs`, `sshd`.

- [ ] **Step 1: Créer le playbook**

Créer `Ansible/main_optiplex_playbook.yml` :

```yaml
---
# Socle de l'hôte Proxmox « Optiplex » (Dell OptiPlex 7090 Micro) — nœud de
# runtime de la maison (Immich, vinted-bot, pokemon-monitor à venir), le NAS
# Synology restant le stockage de masse.
#
# Trois rôles : dépôts APT sains, hygiène de l'hôte (fstrim des CT, alerte
# disque, journald, plafond ARC ZFS), puis durcissement SSH.
#
# sshd_hardening est VOLONTAIREMENT en dernier : si le durcissement se révélait
# verrouillant, les briques utiles du socle sont déjà appliquées.
#
# Le rattachement au tailnet vit dans main_headscale_playbook.yml : il a besoin
# de la preauthkey produite par le play headscale.
#
# make optiplex                            → socle complet
# make check-optiplex                      → dry-run (--check --diff)
# make optiplex ARGS='--skip-tags sshd'    → tout sauf le durcissement SSH
# make optiplex ARGS='--tags zfs'          → plafond ARC seul
# make optiplex ARGS='--tags sshd'         → durcissement SSH seul

- name: Socle de l'hôte Proxmox Optiplex
  hosts: proxmox_optiplex
  gather_facts: true
  roles:
    - role: proxmox_repos
      tags: [repos]
    - role: proxmox_host_maintenance
      tags: [maintenance]
    - role: sshd_hardening
      tags: [sshd]
```

Pas de `become:` au niveau du play — la connexion est déjà root.

- [ ] **Step 2: Ajouter les cibles au Makefile**

Dans `Ansible/Makefile`, ajouter `optiplex` et `check-optiplex` à la ligne `.PHONY`, puis les deux cibles juste après `check-claude-code` :

```make
optiplex:
	./scripts/run.sh ansible-playbook main_optiplex_playbook.yml $(ARGS)

check-optiplex:
	./scripts/run.sh ansible-playbook main_optiplex_playbook.yml --check --diff $(ARGS)
```

Et dans la cible `help`, après la ligne `check-claude-code` :

```make
	@echo "  make optiplex         — Socle de l'hôte Proxmox Optiplex (dépôts, hygiène, ZFS, SSH)"
	@echo "  make check-optiplex   — Dry-run socle Optiplex (--check --diff)"
```

- [ ] **Step 3: Documenter dans le README**

Dans `Ansible/README.md`, section « Arborescence », ajouter après la ligne `main_remove_softwares.yml` :

```
├── main_optiplex_playbook.yml           # → proxmox_repos + proxmox_host_maintenance + sshd_hardening
```

et dans le bloc `roles/`, après `linux_laptop/` :

```
    ├── proxmox_repos/                    # dépôts APT d'un hôte Proxmox (no-subscription)
    └── proxmox_host_maintenance/         # hygiène hôte : fstrim CT, alerte disque, journald, ARC ZFS
```

Dans le bloc `host_vars/<host>/`, ajouter :

```
        ├── optiplex-proxmox/             # hyperviseur runtime (Immich, vinted-bot…)
```

- [ ] **Step 4: Dry-run**

```bash
cd Ansible/
make check-optiplex
```

Attendu : le play tourne sans erreur fatale. Les tâches `ansible.builtin.shell` de `proxmox_repos` et de `zfs_arc.yml` apparaissent en `skipping` — le mode check ne les simule pas. L'`assert` final de `sshd_hardening` est lui aussi sauté (`when: not ansible_check_mode`). **Un dry-run vert ne prouve donc rien sur l'effectivité du durcissement.**

- [ ] **Step 5: Premier run réel, sans le durcissement SSH**

```bash
make optiplex ARGS='--skip-tags sshd'
```

Attendu : `PLAY RECAP` sans `failed`. Le fichier `99-zfs.conf` sera probablement réécrit (il a été posé à la main) et l'initramfs régénéré — c'est prévu, pas une anomalie.

- [ ] **Step 6: Vérifier l'idempotence**

```bash
make optiplex ARGS='--skip-tags sshd'
```

Attendu : `changed=0`. Si une tâche reste `changed` au second passage, elle n'est pas idempotente — la corriger avant de continuer, sans quoi chaque run futur régénérera l'initramfs pour rien.

- [ ] **Step 7: Vérifier le résultat sur l'hôte**

```bash
./scripts/run.sh ansible optiplex-proxmox -m ansible.builtin.command -a 'cat /sys/module/zfs/parameters/zfs_arc_max'
./scripts/run.sh ansible optiplex-proxmox -m ansible.builtin.command -a 'ls -l /etc/cron.weekly/pct-fstrim /etc/cron.hourly/disk-alert'
```

Attendu : `4294967296`, et les deux scripts présents en mode `0755`.

- [ ] **Step 8: Lint et commit**

```bash
make lint
git add main_optiplex_playbook.yml Makefile README.md
git commit -m "feat(optiplex): playbook du socle + cibles make

make optiplex / make check-optiplex, sur le modèle des cibles wyse.
sshd_hardening est placé en dernier dans la liste des rôles pour que le
socle utile soit appliqué même si le durcissement pose problème.

Run réel validé sans le tag sshd, idempotent au second passage."
```

---

### Task 8: Appliquer le durcissement SSH

C'est la tâche la plus risquée du plan : une erreur ici coupe l'accès à la machine et impose une intervention physique. La procédure anti-verrouillage n'est pas optionnelle.

**Files:** aucun fichier modifié — application seule.

**Interfaces:**

- Consumes: le rôle étendu (tâche 6), les variables `sshd_allowed_users` et `sshd_permit_root_login` (tâche 4), le playbook (tâche 7).

- [ ] **Step 1: Ouvrir une session SSH de secours et la garder ouverte**

Dans un terminal **séparé**, qui restera ouvert jusqu'à la fin de la tâche :

```bash
ssh -p 2125 root@192.168.1.100
```

Ne pas fermer ce terminal. Une session déjà établie survit à un rechargement de sshd ; c'est le seul filet si la nouvelle configuration refuse les connexions.

- [ ] **Step 2: Relever la configuration effective avant durcissement**

Dans la session de secours :

```bash
sshd -G | grep -E '^(passwordauthentication|permitrootlogin|kbdinteractiveauthentication|allowusers|port) '
```

Noter la sortie : elle sert de point de comparaison.

- [ ] **Step 3: Appliquer le durcissement**

Depuis le contrôleur :

```bash
cd Ansible/
make optiplex ARGS='--tags sshd'
```

Attendu : `PLAY RECAP` sans `failed`, l'`assert` final affichant `Durcissement SSH effectif confirmé.`

Si le run échoue sur l'assert de l'`Include` : ajouter `Include /etc/ssh/sshd_config.d/*.conf` **en tête** de `/etc/ssh/sshd_config` sur l'hôte, puis relancer. La position compte — sshd retient la première occurrence de chaque directive.

- [ ] **Step 4: Vérifier la configuration effective**

Dans la session de secours :

```bash
sshd -G | grep -E '^(passwordauthentication|permitrootlogin|kbdinteractiveauthentication|allowusers|port) '
```

Attendu : `passwordauthentication no`, `permitrootlogin prohibit-password`, `kbdinteractiveauthentication no`, `allowusers root`, et `port 2125` **inchangé**.

- [ ] **Step 5: Valider une NOUVELLE connexion avant de fermer l'ancienne**

Dans un troisième terminal :

```bash
ssh -p 2125 root@192.168.1.100 'echo NOUVELLE SESSION OK'
```

Attendu : `NOUVELLE SESSION OK`.

**Tant que cette commande n'a pas réussi, ne pas fermer la session de secours.** En cas d'échec, corriger depuis la session de secours (typiquement en retirant `/etc/ssh/sshd_config.d/010-runon-hardening.conf` puis en rechargeant sshd), puis diagnostiquer.

- [ ] **Step 6: Vérifier l'idempotence**

```bash
make optiplex ARGS='--tags sshd'
```

Attendu : `changed=0`, donc aucun rechargement de sshd.

- [ ] **Step 7: Fermer la session de secours et commiter la validation**

Il n'y a pas de fichier à commiter dans cette tâche. Cocher les étapes du plan et poursuivre.

---

### Task 9: Rattacher l'Optiplex au tailnet

**Files:**

- Modify: `Ansible/main_headscale_playbook.yml`

**Interfaces:**

- Consumes: `hostvars['headscale'].hs_preauthkey`, produit par `roles/headscale/tasks/main.yml:145` lors du play `headscale`.

- [ ] **Step 1: Ajouter le play en fin de `main_headscale_playbook.yml`**

Ajouter à la fin du fichier :

```yaml
# L'Optiplex est sur le LAN de la maison, donc joignable directement par le
# contrôleur — le tailnet sert à l'atteindre depuis l'extérieur (WebUI 8006) et
# depuis les autres nœuds. Play distinct de celui du Wyse : le Wyse porte
# `become: true` (utilisateur aurel) alors que l'Optiplex se connecte en root, et
# sudo n'est pas garanti présent sur une installation PVE nue.
- name: Rattacher l'hôte Proxmox (Optiplex) au tailnet (client tailscale)
  hosts: proxmox_optiplex
  gather_facts: true
  roles:
    - role: proxmox_repos
    - role: tailscale_client
```

- [ ] **Step 2: Documenter la contrainte d'invocation dans l'en-tête**

Dans le bloc de commentaires en tête de `main_headscale_playbook.yml`, ajouter :

```yaml
# ⚠️ La preauthkey vient du play headscale (hostvars['headscale'].hs_preauthkey).
#    Un `--limit proxmox_optiplex` SEUL échoue sur variable indéfinie : le play
#    headscale doit être dans le périmètre. Invocation correcte :
#      make headscale ARGS='--limit headscale,optiplex-proxmox'
```

- [ ] **Step 3: Vérifier le ciblage**

```bash
cd Ansible/
./scripts/run.sh ansible-playbook main_headscale_playbook.yml --list-hosts
```

Attendu : le nouveau play liste `optiplex-proxmox`, et **aucun** des plays Wyse ne le liste.

- [ ] **Step 4: Appliquer**

```bash
make headscale ARGS='--limit headscale,optiplex-proxmox'
```

Attendu : `PLAY RECAP` sans `failed`.

Si le run échoue sur `hs_preauthkey is undefined`, c'est que le play `headscale` n'était pas dans le périmètre — vérifier le `--limit`.

- [ ] **Step 5: Vérifier le rattachement**

```bash
./scripts/run.sh ansible optiplex-proxmox -m ansible.builtin.command -a 'tailscale status'
```

Attendu : l'hôte apparaît avec une IP `100.64.0.x`, et les autres nœuds du tailnet sont listés.

- [ ] **Step 6: Vérifier l'idempotence**

```bash
make headscale ARGS='--limit headscale,optiplex-proxmox'
```

Attendu : `changed=0` sur `optiplex-proxmox`.

- [ ] **Step 7: Lint et commit**

```bash
make lint
git add main_headscale_playbook.yml
git commit -m "feat(optiplex): rattache l'hôte au tailnet headscale

Play distinct de celui du Wyse : become true côté Wyse (utilisateur
aurel) contre root direct côté Optiplex, sudo n'étant pas garanti sur
une install PVE nue. Mutualiser aurait imposé de déplacer le become
dans l'inventaire, donc de toucher au chemin d'exécution d'un hôte
distant et peu accessible.

La contrainte d'invocation (--limit headscale,optiplex-proxmox) est
documentée en tête de playbook : la preauthkey vient du play headscale."
```

---

## Vérification finale

Une fois les neuf tâches faites, dérouler la procédure complète de la spec §7 :

- [ ] `make check-wyse` et `make check-headscale` — comparés à l'état d'avant le plan, aucune régression sur le Wyse
- [ ] `make check-macos` — aucun changement autre que des `skipping` sur les tâches Linux ajoutées
- [ ] `make lint` — vert
- [ ] `make optiplex` **complet** (sans `--skip-tags`), puis relance : `changed=0`
- [ ] `./scripts/run.sh ansible proxmox_hosts -m ansible.builtin.ping` — les deux hyperviseurs répondent

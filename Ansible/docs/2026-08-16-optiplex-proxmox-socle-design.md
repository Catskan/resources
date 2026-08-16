# Socle Ansible de l'hôte Proxmox « Optiplex »

**Date** : 2026-08-16
**Statut** : design validé, prêt pour plan d'implémentation
**Périmètre** : socle de l'hôte uniquement — aucun conteneur applicatif

## Contexte

Un Dell OptiPlex 7090 Micro (16 Go de RAM, SSD NVMe 512 Go, Proxmox VE sur ZFS
RAID0 mono-disque) a été installé le 2026-08-16 pour héberger les runtimes de la
maison — Immich, vinted-bot, pokemon-monitor — aujourd'hui portés par le NAS
Synology. Le NAS reste le stockage de masse ; l'Optiplex devient le nœud de calcul.

Le repo Ansible connaît déjà un hôte Proxmox : `wyse-proxmox`, un Wyse 5070 situé
chez la mère d'Aurélien, joint par IP publique et port forwardé. Cet hôte porte
deux conteneurs (`claude-code`, `headscale`) créés par les rôles
`proxmox_claude_lxc` et `proxmox_headscale_lxc`.

L'Optiplex doit rejoindre l'inventaire **sans hériter des plays du Wyse** : le
groupe `proxmox_hosts` étant ciblé directement par `main_wyse_playbook.yml` et
`main_headscale_playbook.yml`, y ajouter l'Optiplex tel quel ferait tenter la
création du CT `claude-code` sur la mauvaise machine.

## Objectif

Permettre à Ansible de provisionner et maintenir l'hôte Optiplex de façon
idempotente et reproductible après une réinstallation, en partageant avec le Wyse
tout ce qui relève de l'hygiène d'un hyperviseur Proxmox.

## Périmètre

**Inclus**

- Entrée d'inventaire, restructuration des groupes Proxmox, connexion SSH
- Dépôts APT sains (désactivation enterprise, activation no-subscription)
- Hygiène disque de l'hôte : `pct fstrim` hebdomadaire, alerte de saturation,
  plafond des journaux systemd
- Réglage du plafond ARC de ZFS, conditionné à la présence effective de ZFS
- Rattachement au tailnet Headscale
- Durcissement SSH de l'hôte, ce qui impose d'étendre à Linux le rôle
  `sshd_hardening` aujourd'hui utilisable sur macOS uniquement
- Cibles Makefile, documentation, procédure de vérification

**Exclu — décidé explicitement**

- **Création de la partition de swap.** `sgdisk` sur le disque système est
  destructif et ne s'exécute qu'une fois dans la vie de la machine. Le codifier en
  tâche idempotente exigerait des gardes fragiles pour un gain nul. Cela reste du
  runbook d'installation.
- **Tout conteneur applicatif** (Immich, vinted-bot, pokemon-monitor) et toute
  migration de données depuis le NAS. Chacun fera l'objet de son propre cycle
  design → plan → implémentation.
- **Gestion du port SSH (2125) par Ansible.** Le rôle `sshd_hardening` ne sait
  régler le port que sur macOS (`/etc/services` + rebind launchd) et son template
  n'émet aucune directive `Port`. Le port reste donc configuré à la main sur
  l'Optiplex — voir §4.

## Décision structurante

Trois options ont été pesées :

| Option | Description                                                                                    | Verdict     |
| ------ | ---------------------------------------------------------------------------------------------- | ----------- |
| A      | Groupe parent `proxmox_hosts` avec deux enfants ; extraction de l'hygiène dans un rôle partagé | **retenue** |
| B      | Groupe `optiplex_hosts` séparé, rôle dédié, aucun partage                                      | rejetée     |
| C      | Restructuration de l'inventaire sans mutualiser les rôles                                      | rejetée     |

**A est retenue.** B et C laissent deux copies des scripts `disk-alert` et
`pct-fstrim` diverger : c'est la dette qui se paie le jour où un seul des deux
hyperviseurs reçoit un correctif. A impose en contrepartie de modifier des
playbooks qui fonctionnent aujourd'hui sur un hôte distant et peu accessible — le
risque est contenu par la procédure de vérification (§7), qui compare les dry-runs
du Wyse avant et après modification.

Effet de bord recherché : le rôle `roles/proxmox_repos/`, présent sur le working
tree mais **jamais commité ni référencé**, trouve enfin son emploi, et le bricolage
`pre_tasks` inline de `main_headscale_playbook.yml` qui refait le même travail
disparaît.

## §1 — Inventaire

### Groupes

`inventory/hosts.yaml` — `proxmox_hosts` devient un groupe parent :

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

Le nom d'hôte `optiplex-proxmox` reprend la convention de `wyse-proxmox` : il
désigne la **machine**, pas son rôle applicatif. Les services vivront dans des
conteneurs nommés séparément.

### Connexion

Nouveau fichier `inventory/host_vars/optiplex-proxmox/connection.yml` :

```yaml
# Hôte Proxmox VE (OptiPlex 7090 Micro) — LAN de la maison, accès direct.
# Root en direct : c'est le mode natif d'un hyperviseur Proxmox, et ça évite
# d'avoir à stocker un mot de passe sudo.
# ⚠️ ansible_port EXPLICITE : sshd écoute sur 2125, et le contrôleur (l'Air)
#    remappe par ailleurs `ssh`->2122 dans /etc/services — aucun défaut n'est bon.
ansible_connection: ssh
ansible_host: 192.168.1.100
ansible_port: 2125
ansible_user: root
ansible_ssh_common_args: -o StrictHostKeyChecking=accept-new
```

Aucun fichier `secrets.yml` pour cet hôte : root en direct, pas de `become`, donc
aucun secret à résoudre. `playbooks/test_keepass.yml` n'est pas modifié.

**Prérequis d'amorçage** (hors Ansible, à faire une fois) : la clé publique du
contrôleur doit être présente dans `/root/.ssh/authorized_keys` de l'Optiplex.

### Variables d'hôte

Nouveau fichier `inventory/host_vars/optiplex-proxmox/main.yml` :

```yaml
# Plafond ARC de ZFS. 4 GiB max / 1 GiB min sur 16 Go de RAM : laisse la mémoire
# aux conteneurs applicatifs. Valeur propre à CETTE machine — voir §3.
pve_zfs_arc_max_bytes: 4294967296
pve_zfs_arc_min_bytes: 1073741824

# Durcissement SSH (rôle sshd_hardening) — voir §4.
# root par clé uniquement : c'est le modèle de connexion retenu ci-dessus, sudo
# n'étant pas garanti présent sur une installation PVE nue. La liste AllowUsers
# est le point d'extension prévu si un compte de service apparaît un jour.
sshd_allowed_users:
  - root
sshd_permit_root_login: "prohibit-password"
```

`sshd_password_authentication` et `sshd_kbdinteractive_authentication` restent aux
défauts du rôle (`"no"`), qui sont déjà les bonnes valeurs.

`sshd_port` n'est **volontairement pas défini** pour cet hôte : la tâche qui le
consomme est gardée sur macOS, la déclarer ici laisserait croire qu'Ansible gère le
2125 alors qu'il n'en est rien.

## §2 — Rôles

Trois rôles à but unique, **composés dans le playbook** plutôt qu'imbriqués par
`meta/dependencies` : la composition reste visible et chaque brique reste taggable
indépendamment. Deux sont nouveaux ou nouvellement commités, le troisième
(`sshd_hardening`) est étendu — voir §4.

### `roles/proxmox_repos/` — commité tel quel

Le rôle existe déjà sur le working tree et fait exactement le bon travail :
désactivation des dépôts enterprise aux deux formats (`.list` legacy et DEB822 de
PVE 9), activation de `pve-no-subscription`, rafraîchissement du cache APT. Il est
commité **sans modification**.

### `roles/proxmox_host_maintenance/` — nouveau, par extraction

Alimenté par déplacement depuis `proxmox_claude_lxc`, dont le métier est de créer
un conteneur et qui n'a rien à faire de l'hygiène de l'hyperviseur.

| Fichier             | Origine                                                   |
| ------------------- | --------------------------------------------------------- |
| `tasks/main.yml`    | `proxmox_claude_lxc/tasks/maintenance.yml` (déplacé)      |
| `tasks/zfs_arc.yml` | nouveau — voir §3                                         |
| `files/pct-fstrim`  | `git mv` depuis `proxmox_claude_lxc/files/`               |
| `files/disk-alert`  | `git mv` depuis `proxmox_claude_lxc/files/`               |
| `handlers/main.yml` | handler `Redémarrer systemd-journald` + handlers ZFS (§3) |
| `defaults/main.yml` | `pve_journal_max_use: 200M`, valeurs ARC vides            |
| `meta/main.yml`     | sur le modèle de `proxmox_repos/meta/main.yml`            |

`tasks/main.yml` importe `zfs_arc.yml` avec le tag `zfs`.

Côté `proxmox_claude_lxc`, l'`import_tasks: maintenance.yml` (ligne 89 de
`tasks/main.yml`) et son tag `maintenance` sont retirés ; c'est désormais
`main_wyse_playbook.yml` qui appelle le rôle.

Les en-têtes des deux scripts portent la mention « Déposé par Ansible — rôle
proxmox_claude_lxc » : elle est corrigée en `proxmox_host_maintenance`, sinon elle
ment sur la provenance du fichier.

**Aucune adaptation des scripts n'est nécessaire** : `disk-alert` teste `df /`,
vrai sur LVM-thin comme sur ZFS ; `pct-fstrim` itère sur `pct list`.

## §3 — Réglage ARC de ZFS

Fichier `roles/proxmox_host_maintenance/tasks/zfs_arc.yml`, tag `zfs`.

### Double garde

Le réglage ne s'applique **jamais par accident** :

1. **Présence de ZFS** — `stat /sys/module/zfs`. Si le module n'est pas chargé,
   tout le bloc est sauté. C'est le cas du Wyse, qui est sur LVM-thin : aucun
   fichier `modprobe.d` orphelin n'y sera déposé.
2. **Valeur définie pour l'hôte** — `pve_zfs_arc_max_bytes` est vide dans les
   `defaults` du rôle. Elle n'existe que dans `host_vars/optiplex-proxmox/main.yml`.
   Un futur hôte ZFS ne subit donc pas la valeur d'une autre machine : le bon
   plafond dépend de sa RAM.

### Tâches

1. `stat` sur `/sys/module/zfs` → registre la présence du module.
2. Écriture de `/etc/modprobe.d/99-zfs.conf` (`options zfs zfs_arc_max=… zfs_arc_min=…`),
   `owner: root`, `mode: 0644`, avec un en-tête « géré par Ansible ».
   **Notifie** les handlers de régénération.
3. Application **à chaud** dans `/sys/module/zfs/parameters/zfs_arc_max` et
   `zfs_arc_min`, pour que le plafond soit effectif sans reboot. Tâche idempotente :
   elle ne s'exécute que si la valeur courante diffère de la cible.

### Handlers

- `update-initramfs -u -k all`
- puis `proxmox-boot-tool refresh`, **conditionné à l'existence de
  `/etc/kernel/proxmox-boot-uuids`** — hors installation ZFS-root gérée par
  proxmox-boot-tool, la commande n'a rien à synchroniser.

Les handlers ne se déclenchent que si `99-zfs.conf` a changé : pas de régénération
d'initramfs à chaque run.

### Sémantique du réglage — à ne pas se tromper

Depuis PVE 8.1, l'installeur pose déjà une limite ARC à **10 % de la RAM**, soit
environ 1,6 GiB sur cette machine. Le problème que ce réglage corrige est donc que
la limite est **trop basse**, pas trop haute. L'ancien défaut « 50 % de la RAM » ne
concerne que les installations antérieures ou les pools ajoutés après coup.

### Limite connue

Le fichier existe déjà sur l'Optiplex, posé à la main. Si sa mise en forme diffère
de celle du template (ordre des options, commentaires), le **premier** run le
réécrira et régénérera l'initramfs. Le résultat est identique, mais ce ne sera pas
un `changed=0`. L'idempotence est vérifiable à partir du deuxième run.

L'application à chaud ne vide pas l'ARC déjà rempli : il redescend sous pression
mémoire. Seul le plafond est immédiat.

## §4 — Durcissement SSH

### Constat : le rôle existant ne fonctionne que sur macOS

`roles/sshd_hardening/` est écrit pour les Macs. Trois blocages, vérifiés par
lecture du rôle, interdisent de l'appliquer tel quel à un hôte Debian/Proxmox.

1. **Les deux handlers sont gardés sur Darwin.** `handlers/main.yml` porte
   `when: ansible_os_family == "Darwin"` sur `Recharger sshd` comme sur
   `Rebinder le socket ssh launchd`. Sur Linux, le drop-in serait écrit, le
   `notify` déclenché, et le handler _skippé_ : sshd ne rechargerait jamais. Le
   durcissement resterait inerte jusqu'au prochain redémarrage, en affichant un
   run vert. C'est le blocage le plus insidieux des trois.
2. **Le port n'est pas gérable.** La tâche de réglage du port passe par
   `/etc/services` et un rebind launchd, gardée sur Darwin ; le template
   `010-runon-hardening.conf.j2` n'émet aucune directive `Port`.
3. **Le défaut du rôle verrouillerait l'hôte.** `sshd_permit_root_login` vaut
   `"no"` par défaut et l'Optiplex se connecte en root. L'`assert` anti-lockout en
   tête de rôle ne contrôle que `AllowUsers` contre `ansible_user` — il ne regarde
   pas `PermitRootLogin` et n'aurait donc rien empêché.

### Décision : étendre le rôle, ne pas en créer un second

Les gardes Darwin existantes sont conservées **à l'identique** ; on n'ajoute que des
branches `when: ansible_os_family != "Darwin"`. Le chemin d'exécution des Macs est
donc inchangé par construction — ce qui compte, puisque c'est par SSH sur ces mêmes
Macs que passe `run-on`. La non-régression est tout de même vérifiée (§7).

L'alternative — un rôle `sshd_hardening_linux` distinct — dupliquerait le template
et les asserts pour la même raison que B/C ont été écartées dans la décision
structurante.

### Tâches et handlers ajoutés

- **Vérifier que le drop-in est lu.** `assert` sur la présence de
  `Include /etc/ssh/sshd_config.d/*.conf` dans `/etc/ssh/sshd_config`. Debian le
  pose en tête de fichier (donc nos valeurs gagnent, sshd retenant la première
  occurrence d'une directive), mais si Proxmox l'a retirée de sa propre config, le
  fichier déposé serait purement décoratif et le run vert mensonger.
- **Détecter l'activation par socket.** Debian 13 — dont dérive PVE 9 — active
  `ssh.socket` par défaut. `systemctl is-enabled ssh.socket` décide de la cible du
  handler : `ssh.socket` si actif, `ssh.service` sinon.
- **Handler `Recharger sshd (Linux)`**, gardé `when: ansible_os_family != "Darwin"`,
  qui recharge l'unité déterminée ci-dessus.

Le contrôle final déjà présent dans le rôle — parsing de `sshd -G` puis `assert` sur
`passwordauthentication`, `permitrootlogin` et `kbdinteractiveauthentication` —
fonctionne tel quel sur Linux et devient la preuve que le durcissement est
réellement effectif, et pas seulement écrit sur disque.

### Ce que le durcissement change concrètement

`PasswordAuthentication no`, `KbdInteractiveAuthentication no`,
`PubkeyAuthentication yes`, `PermitRootLogin prohibit-password`, `AllowUsers root`.
Autrement dit : root reste joignable, mais **par clé uniquement**, et aucun autre
compte ne peut ouvrir de session SSH.

Le port reste 2125, géré à la main (voir Périmètre). Ansible ne le touche pas, donc
aucun risque de rebind qui couperait la session en cours — contrairement au cas
macOS, où le handler de rebind coupe explicitement la connexion.

## §5 — Playbooks

### Nouveau : `main_optiplex_playbook.yml`

```yaml
---
# Socle de l'hôte Proxmox « Optiplex » (Dell OptiPlex 7090 Micro) — nœud de
# runtime de la maison (Immich, vinted-bot, pokemon-monitor à venir), le NAS
# Synology restant le stockage de masse.
#
# Trois rôles : dépôts APT sains, hygiène de l'hôte (fstrim, alerte disque,
# journald, plafond ARC ZFS), puis durcissement SSH.
#
# Le rattachement au tailnet vit dans main_headscale_playbook.yml : il a besoin
# de la preauthkey produite par le play headscale.
#
# make optiplex                        → socle complet
# make check-optiplex                  → dry-run (--check --diff)
# make optiplex ARGS='--tags zfs'      → réglage ARC seul
# make optiplex ARGS='--tags sshd'     → durcissement SSH seul

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

`sshd_hardening` est placé **en dernier** : si le durcissement se révélait
verrouillant, les briques utiles du socle sont déjà appliquées, et l'on ne perd pas
un run entier.

Pas de `become:` — la connexion est déjà root.

### Modifié : `main_wyse_playbook.yml`

- Play 1 : `hosts: proxmox_hosts` → `hosts: proxmox_wyse`.
- Play 1 : ajout de `proxmox_host_maintenance` en second rôle, avec
  `tags: [maintenance]`, pour compenser l'`import_tasks` retiré de
  `proxmox_claude_lxc`. Le tag `maintenance` conserve donc son comportement
  d'origine côté Wyse.
- Play 2 (`claude_code_hosts`) : inchangé.

### Modifié : `main_headscale_playbook.yml`

- Plays 1 et 3 (création du CT headscale, ajout du device `tun` au CT
  claude-code) : `hosts: proxmox_hosts` → `hosts: proxmox_wyse`.
- Play 4 (client tailscale sur l'hyperviseur Wyse) : ses `pre_tasks` inline de
  désactivation des dépôts enterprise sont remplacés par `role: proxmox_repos`,
  placé avant `tailscale_client`.
- **Nouveau play 5** : rattachement de l'Optiplex au tailnet, sur
  `hosts: proxmox_optiplex`, avec `role: proxmox_repos` puis
  `role: tailscale_client`, et **sans `become`**.

**Pourquoi un play distinct plutôt qu'un play unique sur le groupe parent.** Le
play du Wyse porte `become: true` (utilisateur `aurel`) ; l'Optiplex se connecte en
root et `sudo` n'est pas garanti présent sur une installation PVE nue. Mutualiser
imposerait de déplacer le `become` dans l'inventaire — plus élégant, mais cela
modifierait le chemin d'exécution d'un hôte distant et peu accessible pour
économiser six lignes. Le choix va à l'option la moins maligne.

**Contrainte d'invocation à documenter dans l'en-tête du playbook.** La preauthkey
est exposée par `roles/headscale/tasks/main.yml:145` sous
`hostvars['headscale'].hs_preauthkey`, et `tailscale_client` l'attend par défaut.
Un `make headscale ARGS='--limit proxmox_optiplex'` échouerait donc sur variable
indéfinie : le play `headscale` doit être dans le périmètre. L'invocation correcte
pour ne rattacher que l'Optiplex est :

```
make headscale ARGS='--limit headscale,optiplex-proxmox'
```

## §6 — Makefile et documentation

`Makefile` — deux cibles calquées sur `wyse` / `check-wyse` :

```make
optiplex:
	./scripts/run.sh ansible-playbook main_optiplex_playbook.yml $(ARGS)

check-optiplex:
	./scripts/run.sh ansible-playbook main_optiplex_playbook.yml --check --diff $(ARGS)
```

Plus l'ajout de `optiplex` et `check-optiplex` à `.PHONY`, et deux lignes dans la
cible `help`.

`README.md` — entrée dans la section « Arborescence » (nouveau playbook, deux
nouveaux rôles) et dans « Lancer un run ».

## §7 — Vérification

Dans cet ordre : la non-régression des hôtes existants **d'abord**, avant toute
exécution réelle.

1. `make check-wyse` et `make check-headscale`, **avant puis après** modification.
   Les sorties doivent être équivalentes : cela prouve que le recâblage des groupes
   ne change pas ce qui est planifié sur le Wyse.
2. `make check-macos`, **avant puis après** l'extension de `sshd_hardening`. Les
   branches ajoutées sont gardées sur non-Darwin, donc les sorties doivent être
   strictement identiques. C'est la vérification qui protège l'accès `run-on` aux
   Macs.
3. `make lint` — le glob `main_*.yml` d'`ansible-lint` couvre le nouveau playbook.
4. `./scripts/run.sh ansible proxmox_optiplex -m ping` — valide IP, port 2125 et clé.
5. `make check-optiplex` en dry-run.
6. `make optiplex ARGS='--skip-tags sshd'` — tout le socle sauf le durcissement,
   puis **relance immédiate** : le second run doit afficher `changed=0`, à
   l'exception documentée en §3 sur le premier passage.
7. `make optiplex ARGS='--tags sshd'` — le durcissement, **en gardant la session SSH
   courante ouverte**. Puis, depuis un second terminal, ouvrir une nouvelle
   connexion `ssh -p 2125 root@192.168.1.100` et la confirmer **avant** de fermer la
   première. C'est la seule protection réelle contre un verrouillage : une session
   déjà établie survit à un rechargement de sshd, une nouvelle non.
8. `make headscale ARGS='--limit headscale,optiplex-proxmox'`, puis
   `tailscale status` sur l'Optiplex pour confirmer le rattachement.

**Limite de la vérification en `--check`.** Les tâches `ansible.builtin.shell` de
`proxmox_repos` sont _skippées_ en mode check, pas simulées. Le dry-run prouve le
ciblage, le parsing et la résolution des variables — pas le comportement complet
des tâches shell. De même, l'`assert` final de `sshd_hardening` est explicitement
désactivé en check mode (`when: not ansible_check_mode`) : un `make check-optiplex`
vert ne prouve rien sur l'effectivité du durcissement.

## §8 — Risques

| Risque                                                         | Portée                                      | Atténuation                                                                                                                                                                        |
| -------------------------------------------------------------- | ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Le recâblage de groupes casse un play du Wyse                  | Hôte distant, peu accessible                | Dry-runs comparés avant/après (§7.1) ; aucune modification de la logique des rôles, uniquement du ciblage                                                                          |
| `99-zfs.conf` réécrit au premier run → initramfs régénéré      | Optiplex                                    | Sans conséquence fonctionnelle ; idempotence vérifiée au second run                                                                                                                |
| Clé SSH du contrôleur absente de l'Optiplex                    | Bloque tout                                 | Prérequis d'amorçage explicite (§1) ; détecté par `ansible -m ping` (§7.4)                                                                                                         |
| `--limit proxmox_optiplex` seul sur le playbook headscale      | Échec sur variable indéfinie                | Invocation correcte documentée dans l'en-tête du playbook (§5)                                                                                                                     |
| **Verrouillage SSH de l'Optiplex**                             | Perte totale d'accès, intervention physique | `PermitRootLogin prohibit-password` + `AllowUsers root` explicites (§1) ; session courante gardée ouverte pendant le test d'une nouvelle connexion (§7.7) ; `assert` sur `sshd -G` |
| Durcissement écrit mais jamais appliqué (handler Darwin-only)  | Faux positif : run vert, hôte non durci     | Handler Linux ajouté (§4) ; `assert` sur la config effective, actif hors check mode                                                                                                |
| Drop-in `sshd_config.d` ignoré si Proxmox a retiré l'`Include` | Faux positif identique                      | `assert` sur la présence de la ligne `Include` avant tout dépôt (§4)                                                                                                               |
| L'extension de `sshd_hardening` casse l'accès SSH aux Macs     | `run-on` et donc tout le poste de travail   | Branches ajoutées gardées `!= "Darwin"`, gardes existantes intactes ; `make check-macos` comparé avant/après (§7.2)                                                                |

## §9 — Suites hors périmètre

À traiter chacune par son propre cycle design → plan → implémentation :

- Conteneur Immich sur l'Optiplex et migration depuis le NAS, incluant la bascule
  du routage SNI de `photos.eonelia.fr` dans le rôle `immich_proxy`. Contrainte
  déjà connue : base PostgreSQL et cache de vignettes sur le pool local, seuls les
  originaux (`UPLOAD_LOCATION`) sur le NAS.
- Conteneurs vinted-bot et pokemon-monitor.
- Automatisation de la partition de swap, si elle devient un besoin réel lors d'une
  réinstallation.
- Gestion du port SSH par Ansible sur Linux (directive `Port` dans le drop-in, ou
  unité `ssh.socket`), si le besoin de le changer se présente.

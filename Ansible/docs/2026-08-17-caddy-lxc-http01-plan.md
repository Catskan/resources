# Plan d'implémentation — CT Caddy sur l'Optiplex, certificats ACME HTTP-01

> **Pour les exécutants agentiques :** SOUS-COMPÉTENCE REQUISE — utiliser
> `superpowers:subagent-driven-development` (recommandé) ou
> `superpowers:executing-plans` pour dérouler ce plan tâche par tâche. Les étapes
> utilisent la syntaxe case à cocher (`- [ ]`).

**Objectif :** déplacer le reverse-proxy dans un conteneur LXC dédié de l'Optiplex, où
les ports 80 et 443 sont libres, afin que Caddy émette et renouvelle seul ses
certificats par challenge HTTP-01.

**Architecture :** un CT Debian non privilégié à IP statique, provisionné par
`proxmox_caddy_lxc` sur le modèle de `proxmox_headscale_lxc` (`pveam` → `pct create` →
bootstrap SSH par `pct exec`), puis configuré par `caddy_proxy` comme un hôte Ansible
ordinaire. Les vhosts sont des données, pas du template figé. Le Caddy du NAS reste
installé et inactif pendant toute la période de rollback.

**Pile technique :** Proxmox VE 9 (`pct`, `pveam`), Debian 13 en LXC, Caddy 2 (paquet
officiel), Ansible avec modules standards — le CT ayant un Python moderne, la contrainte
`raw` du NAS disparaît.

**Spec :** `Ansible/docs/2026-08-17-caddy-universel-split-dns-design.md`

## Contraintes globales

Ces règles s'appliquent à **toutes** les tâches, sans être répétées.

- **Échéance dure : 25 août 2026.** Le wildcard `*.eonelia.fr` expire ce jour-là. Sous
  HSTS `max-age=31536000`, son expiration coupe `photos.eonelia.fr`, `nas.eonelia.fr` et
  `mom.eonelia.fr` sans recours navigateur. La tâche 0 est un filet à dérouler même si
  le reste avance bien.
- **L'exécution passe par la machine hôte.** Le dépôt est monté en SSHFS depuis un
  conteneur sans toolchain : tout ce qui lance Ansible, git réseau ou un binaire natif
  passe par `run-on auto <cmd>`. Lecture et édition de fichiers se font directement.
- **Les cibles `make` demandent le mot de passe maître KeePass** au clavier
  (`scripts/run.sh`). Un agent ne peut pas les lancer : ces étapes sont explicitement
  marquées « à lancer par l'humain ». Le partage `home` du NAS doit être monté, ou
  `KEEPASS_LOCATION=/Users/aurel/Vault/Aurel-vault.kdbx` passé en variable.
- **IP du CT : `192.168.1.210/24`, passerelle `192.168.1.254`.** La plage DHCP de la
  Freebox va de `.2` à `.200` : toute adresse en dessous de `.201` serait attribuable à
  une autre machine.
- **Préfixe des variables : le domaine, pas le nom du rôle** (`caddy_*`). C'est la
  convention du dépôt, et `var-naming[no-role-prefix]` est désactivée pour cette raison
  (voir `Ansible/.ansible-lint`).
- **Toute tâche `ansible.builtin.systemd_service` porte `not ansible_check_mode`.** En
  `--check` l'unité n'est pas écrite, systemd ne la connaît pas, et le module échoue sur
  « Could not find the requested service », cassant le dry-run.
- **Le test, ici, c'est le dry-run puis l'idempotence.** Il n'y a pas de suite de tests
  unitaires dans ce dépôt. Chaque tâche se valide par : `--check --diff` qui montre les
  changements attendus, run réel qui aboutit, **second passage à `changed=0`**, puis une
  sonde fonctionnelle (`curl`, `systemctl`, `caddy validate`).
- **Ne jamais basculer la redirection `443` avant que les certificats de production
  soient obtenus et vérifiés.** HTTP-01 ne valide que sur le port 80 : les certificats
  s'acquièrent pendant que le 443 sert encore depuis le NAS. C'est ce qui rend la
  séquence réversible sans coupure.

---

## Tâche 0 : Sécuriser l'échéance du wildcard — filet

**Pourquoi d'abord :** si les tâches 1 à 5 dérapent de quelques jours, le 26 août coupe
l'accès photo de deux utilisatrices non techniques et l'enrôlement du tailnet. Cette
tâche est indépendante du reste et ne coûte que quelques minutes.

**Fichiers :** aucun. Action d'exploitation.

**Note du 2026-08-18 :** cette tâche part de la prémisse que le cycle de renouvellement
du wildcard est de 45 jours (« toutes les six semaines »). Cette prémisse était une
extrapolation à tort depuis un seul échantillon — voir la correction dans D1 et l'annexe
des faits mesurés du design doc. Le cycle réel constaté est d'environ 189 jours. Cette
tâche a déjà été exécutée sur cette base ; un futur lecteur qui la rejouerait ne doit pas
s'attendre à revenir tous les six semaines.

- [ ] **Étape 1 : vérifier l'état du certificat en service**

```bash
echo | openssl s_client -servername photos.eonelia.fr -connect photos.eonelia.fr:443 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

Attendu : `subject=CN = *.eonelia.fr`, `issuer=… Sectigo …`, `notAfter=Aug 25 …`.

- [ ] **Étape 2 : vérifier chez IONOS si le renouvellement est automatique**

Espace client IONOS → certificats SSL. Sa durée de 45 jours suggère un renouvellement
automatique. Noter si un nouveau certificat est déjà disponible.

- [ ] **Étape 3 : rafraîchir l'entrée KeePass**

Déposer les quatre fichiers dans l'entrée `Certificate *.eonelia.fr` en conservant
**exactement** les noms d'attachments attendus par les rôles :
`eonelia.fr_ssl_certificate.cer`, `intermediate1.cer`, `intermediate2.cer`,
`*.eonelia.fr_private_key.key`.

- [ ] **Étape 4 : redéployer les deux consommateurs** _(à lancer par l'humain)_

```bash
cd ~/git/resources/Ansible
make immich
make headscale
```

Les deux, pas un seul : `mom.eonelia.fr` (headscale, chez la mère d'Aurélien) sert le
même wildcard et tomberait aussi.

- [ ] **Étape 5 : vérifier les trois noms**

```bash
for n in photos.eonelia.fr nas.eonelia.fr; do
  echo | openssl s_client -servername "$n" -connect "$n:443" 2>/dev/null \
    | openssl x509 -noout -enddate
done
echo | openssl s_client -servername mom.eonelia.fr -connect mom.eonelia.fr:34443 2>/dev/null \
  | openssl x509 -noout -enddate
```

Attendu : les trois `notAfter` repoussés d'environ 45 jours.

---

## Tâche 1 : CT Caddy provisionné et joignable en SSH

**Fichiers :**

- Créer : `Ansible/roles/proxmox_caddy_lxc/defaults/main.yml`
- Créer : `Ansible/roles/proxmox_caddy_lxc/tasks/main.yml`
- Créer : `Ansible/main_caddy_playbook.yml`
- Créer : `Ansible/inventory/host_vars/caddy/connection.yml`
- Modifier : `Ansible/inventory/hosts.yaml` (ajouter le groupe `caddy_hosts`)
- Modifier : `Ansible/Makefile` (cibles `caddy` et `check-caddy`, et la ligne `.PHONY`)

**Interfaces :**

- Consomme : rien d'antérieur. S'appuie sur le groupe `proxmox_optiplex` existant.
- Produit : un hôte Ansible nommé `caddy`, joignable en `root@192.168.1.210` par la clé
  du contrôleur, consommé par la tâche 2. Variables publiées :
  `caddy_ct_vmid` (102), `caddy_ct_ip` (`192.168.1.210`).

- [ ] **Étape 1 : vérifier que le VMID 102 est libre et que le template existe**

```bash
run-on auto ssh -p 2125 root@192.168.1.100 'pct list; qm list; pveam list local | head -5'
```

Attendu : `qm list` montre 100 et 101, `pct list` est vide, donc **102 est libre**. Noter
si `pveam list local` contient déjà une image `debian-13-standard` — sinon le rôle la
téléchargera.

- [ ] **Étape 2 : écrire les defaults du rôle**

Fichier `Ansible/roles/proxmox_caddy_lxc/defaults/main.yml` :

```yaml
---
# CT Caddy sur l'Optiplex — reverse-proxy public de la maison.
# Aligné sur proxmox_headscale_lxc : création via pct, idempotente, sans token API.

caddy_ct_vmid: 102
caddy_ct_hostname: caddy
caddy_ct_template_storage: local
caddy_ct_template: debian-13-standard_13.1-2_amd64.tar.zst
caddy_ct_unprivileged: 1
# Aucune fonctionnalité spéciale : Caddy est installé en paquet natif, donc ni
# nesting (pas de Docker) ni FUSE.
caddy_ct_features: ""
caddy_ct_cores: 1
# 512 Mo suffisent largement : Caddy consomme 50 à 80 Mo pour ce nombre de vhosts.
# L'hôte n'a qu'environ 1,4 Go de marge, mais un LXC ne préalloue rien — c'est un
# plafond cgroup, pas une réservation.
caddy_ct_memory: 512
caddy_ct_swap: 512
# rootfs sur local-zfs et NON sur local : sur cet hôte ZFS est le pool principal,
# ce qui donne les snapshots avant montée de version de Caddy. Le choix « local »
# du Wyse était motivé par son pool thin, absent ici.
caddy_ct_rootfs: local-zfs:4
caddy_ct_bridge: vmbr0

# IP STATIQUE obligatoire : la porte d'entrée publique ne peut pas dépendre d'un bail.
# .210 est au-delà de la plage DHCP de la Freebox (.2 à .200).
caddy_ct_ip: "192.168.1.210"
caddy_ct_cidr: 24
caddy_ct_gateway: "192.168.1.254"
caddy_ct_nameserver: "192.168.1.254"

caddy_ct_onboot: 1
# Clé publique du contrôleur (le MacBook Air), injectée à la création.
caddy_ct_controller_pubkey_path: "~/.ssh/id_ed25519.pub"
```

- [ ] **Étape 3 : écrire les tâches du rôle**

Fichier `Ansible/roles/proxmox_caddy_lxc/tasks/main.yml` :

```yaml
---
# Création idempotente du CT Caddy via pct/pveam (sans token API), sur l'hôte Proxmox.
# Même logique que proxmox_headscale_lxc : CT créé, démarré, JOIGNABLE EN SSH (clé du
# contrôleur injectée + sshd) → devient ensuite un hôte Ansible dédié (rôle caddy_proxy).
# pct exec n'est utilisé QUE pour le bootstrap SSH.
#
# Différence assumée avec le CT headscale : IP STATIQUE et non dhcp. La porte d'entrée
# publique de la maison ne peut pas changer d'adresse au gré d'un bail, et la redirection
# de ports de la Freebox pointe une IP fixe.

- name: Lister les templates LXC présents
  ansible.builtin.command: "pveam list {{ caddy_ct_template_storage }}"
  register: caddy_pveam_list
  changed_when: false
  check_mode: false

- name: Rafraîchir le catalogue des templates si le nôtre est absent
  ansible.builtin.command: pveam update
  when: caddy_ct_template not in caddy_pveam_list.stdout
  changed_when: true

- name: Télécharger le template Debian si absent
  ansible.builtin.command: "pveam download {{ caddy_ct_template_storage }} {{ caddy_ct_template }}"
  when: caddy_ct_template not in caddy_pveam_list.stdout
  changed_when: true

- name: "Vérifier l'existence du CT {{ caddy_ct_vmid }}"
  ansible.builtin.command: "pct status {{ caddy_ct_vmid }}"
  register: caddy_pct_status
  changed_when: false
  failed_when: false
  check_mode: false

- name: Déposer la clé publique du contrôleur sur l'hôte Proxmox
  ansible.builtin.copy:
    content: "{{ lookup('file', caddy_ct_controller_pubkey_path) }}\n"
    dest: /root/caddy-controller.pub
    owner: root
    group: root
    mode: "0600"
  when: caddy_pct_status.rc != 0

- name: "Créer le CT {{ caddy_ct_vmid }} (caddy)"
  ansible.builtin.command: >-
    pct create {{ caddy_ct_vmid }}
    {{ caddy_ct_template_storage }}:vztmpl/{{ caddy_ct_template }}
    --hostname {{ caddy_ct_hostname }}
    --unprivileged {{ caddy_ct_unprivileged }}
    {% if caddy_ct_features %}--features {{ caddy_ct_features }}{% endif %}
    --cores {{ caddy_ct_cores }}
    --memory {{ caddy_ct_memory }}
    --swap {{ caddy_ct_swap }}
    --rootfs {{ caddy_ct_rootfs }}
    --net0 name=eth0,bridge={{ caddy_ct_bridge }},ip={{ caddy_ct_ip }}/{{ caddy_ct_cidr }},gw={{ caddy_ct_gateway }}
    --nameserver {{ caddy_ct_nameserver }}
    --onboot {{ caddy_ct_onboot }}
    --ssh-public-keys /root/caddy-controller.pub
  when: caddy_pct_status.rc != 0
  changed_when: true

- name: "Démarrer le CT {{ caddy_ct_vmid }}"
  ansible.builtin.command: "pct start {{ caddy_ct_vmid }}"
  when: "'status: running' not in (caddy_pct_status.stdout | default(''))"
  changed_when: true

- name: Bootstrap SSH dans le CT (openssh-server + activation)
  ansible.builtin.command: >-
    pct exec {{ caddy_ct_vmid }} -- bash -lc
    'apt-get update && apt-get install -y openssh-server && systemctl enable --now ssh'
  register: caddy_ct_sshd
  changed_when: "'Setting up openssh-server' in caddy_ct_sshd.stdout"

- name: Vérifier que le CT porte bien l'IP statique attendue
  ansible.builtin.command: "pct exec {{ caddy_ct_vmid }} -- ip -4 -o addr show eth0"
  register: caddy_ct_addr
  changed_when: false
  check_mode: false
  failed_when: caddy_ct_ip not in caddy_ct_addr.stdout
```

- [ ] **Étape 4 : déclarer l'hôte dans l'inventaire**

Dans `Ansible/inventory/hosts.yaml`, ajouter sous `all.children`, après le bloc
`proxmox_hosts` :

```yaml
caddy_hosts:
  hosts:
    caddy:
```

Créer `Ansible/inventory/host_vars/caddy/connection.yml` :

```yaml
ansible_connection: ssh
ansible_host: 192.168.1.210
ansible_user: root
ansible_ssh_common_args: -o StrictHostKeyChecking=accept-new
```

- [ ] **Étape 5 : écrire le playbook**

Fichier `Ansible/main_caddy_playbook.yml` :

```yaml
---
# Reverse-proxy public de la maison, dans un CT dédié de l'Optiplex.
#
# Deux plays, et l'ordre est significatif : le premier crée le CT depuis l'hôte
# Proxmox, le second le configure comme un hôte Ansible à part entière. Le CT ayant
# un Python moderne, la contrainte « uniquement raw » du NAS ne s'applique pas ici.
#
# make caddy         → CT + configuration
# make check-caddy   → dry-run (--check --diff)

- name: Création du CT Caddy sur l'hôte Proxmox
  hosts: proxmox_optiplex
  gather_facts: true
  roles:
    - role: proxmox_caddy_lxc
      tags: [ct]

- name: Configuration du reverse-proxy Caddy
  hosts: caddy_hosts
  gather_facts: true
  roles:
    - role: caddy_proxy
      tags: [proxy]
```

- [ ] **Étape 6 : ajouter les cibles Makefile**

Dans `Ansible/Makefile`, ajouter `caddy check-caddy` à la ligne `.PHONY`, deux lignes
d'aide dans la cible `help` à la suite de `check-optiplex`, et les recettes :

```make
caddy:
	./scripts/run.sh ansible-playbook main_caddy_playbook.yml $(ARGS)

check-caddy:
	./scripts/run.sh ansible-playbook main_caddy_playbook.yml --check --diff $(ARGS)
```

- [ ] **Étape 7 : dry-run de la création du CT seule**

Le second play échouera au dry-run puisque le rôle `caddy_proxy` n'existe pas encore :
on limite au premier.

```bash
run-on auto 'cd /Users/aurel/git/resources/Ansible && \
  OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES ansible-playbook main_caddy_playbook.yml \
  --tags ct --check --diff'
```

Attendu : `failed=0`, et la tâche de création annoncée en `changed` (ou sautée si un CT
102 existait déjà, ce que l'étape 1 a exclu). Aucun secret KeePass n'est requis : la
connexion à l'hôte Proxmox se fait par clé.

- [ ] **Étape 8 : créer le CT pour de vrai**

```bash
run-on auto 'cd /Users/aurel/git/resources/Ansible && \
  OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES ansible-playbook main_caddy_playbook.yml --tags ct'
```

Attendu : `failed=0`. La dernière tâche échoue si le CT n'a pas pris `192.168.1.210` —
c'est voulu, une IP fausse doit arrêter le play plutôt que produire un proxy injoignable.

- [ ] **Étape 9 : vérifier l'idempotence et l'accès SSH**

```bash
run-on auto 'cd /Users/aurel/git/resources/Ansible && \
  OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES ansible-playbook main_caddy_playbook.yml --tags ct' \
  | tail -3
run-on auto ssh -o StrictHostKeyChecking=accept-new root@192.168.1.210 'hostname; ip -4 -o addr show eth0; free -m | head -2'
```

Attendu : `changed=0` au second passage, `hostname` = `caddy`, l'IP `192.168.1.210`.

⚠️ **Piège :** la config SSH de ce Mac impose `Port 3434` à tous les hôtes. Si la
connexion échoue en `Connection refused`, forcer le port 22 :
`run-on auto ssh -p 22 root@192.168.1.210 hostname`.

- [ ] **Étape 10 : commit**

```bash
git add Ansible/roles/proxmox_caddy_lxc Ansible/main_caddy_playbook.yml \
        Ansible/inventory/hosts.yaml Ansible/inventory/host_vars/caddy Ansible/Makefile
git commit -m "feat(caddy): CT dédié sur l'Optiplex pour le reverse-proxy"
```

---

## Tâche 2 : Caddy installé, certificat de staging obtenu

**Pourquoi le staging d'abord :** l'en-tête HSTS `max-age=31536000` est déjà mémorisé par
les navigateurs pour ces noms. Un certificat de production invalide ne pourrait pas être
contourné. Le staging valide toute la chaîne — redirection Freebox du 80, résolution
publique, accessibilité du challenge — sans consommer les quotas de production.

**Fichiers :**

- Créer : `Ansible/roles/caddy_proxy/defaults/main.yml`
- Créer : `Ansible/roles/caddy_proxy/tasks/main.yml`
- Créer : `Ansible/roles/caddy_proxy/templates/Caddyfile.j2`
- Créer : `Ansible/roles/caddy_proxy/handlers/main.yml`
- Créer : `Ansible/inventory/host_vars/caddy/main.yml`

**Interfaces :**

- Consomme : l'hôte `caddy` de la tâche 1.
- Produit : `caddy_vhosts` (liste consommée par la tâche 3), `caddy_acme_staging`
  (booléen basculé par la tâche 4), un service `caddy` actif.

- [ ] **Étape 1 : ouvrir le port 80 sur la Freebox** _(action humaine, prérequis)_

Freebox OS → Gestion des ports → nouvelle redirection : `TCP`, `WAN 80` → `LAN 80`,
destination `192.168.1.210`, IP source « Toutes », commentaire « Caddy ACME ».

**Ne pas toucher au 443**, qui doit continuer de pointer `NAS:8443`. C'est cette
asymétrie qui permet d'obtenir les certificats sans interrompre le service.

- [ ] **Étape 2 : vérifier que le 80 arrive bien sur le CT**

```bash
run-on auto ssh root@192.168.1.210 'apt-get install -y netcat-openbsd >/dev/null 2>&1; nc -l -p 80 &
sleep 1; echo pret'
curl -sS -m 8 -o /dev/null -w "%{http_code}\n" http://82.67.69.38/ 2>&1 | tail -1
```

Attendu : la connexion aboutit (n'importe quel code, ou une erreur de protocole) et non
un timeout. Un timeout signifie que la redirection n'est pas active — inutile d'aller
plus loin, ACME échouerait.

- [ ] **Étape 3 : écrire les defaults du rôle**

Fichier `Ansible/roles/caddy_proxy/defaults/main.yml` :

```yaml
---
# Reverse-proxy Caddy du CT. Contrairement au rôle immich_proxy qu'il remplace, la
# cible est un Debian ordinaire : modules Ansible standards, pas de contrainte `raw`.

# Adresse de contact ACME. Let's Encrypt s'en sert pour les avis d'expiration —
# donc l'unique alerte si le renouvellement automatique cessait de fonctionner.
# ⚠️ À CONFIRMER avant le premier run : la seule adresse connue de ce dépôt est
# l'adresse professionnelle. Une adresse personnelle est probablement préférable
# pour de l'infrastructure domestique.
caddy_acme_email: "aurelien.busutil@majelanx.com"

# Staging par défaut. La bascule en production est un choix EXPLICITE (tâche 4) :
# HSTS interdit tout repli si le certificat de production est mauvais.
caddy_acme_staging: true
caddy_acme_staging_ca: "https://acme-staging-v02.api.letsencrypt.org/directory"

# HSTS : un an. Mettre 0 pour désactiver l'en-tête pendant une investigation — un
# navigateur ayant mémorisé HSTS refusera tout repli en HTTP sur ce domaine.
caddy_hsts_max_age: 31536000

# Liste VOLONTAIREMENT VIDE : les vhosts sont propres à l'installation et se
# définissent dans inventory/host_vars/caddy/main.yml.
caddy_vhosts: []
```

- [ ] **Étape 4 : écrire le template du Caddyfile**

Fichier `Ansible/roles/caddy_proxy/templates/Caddyfile.j2` :

```jinja
{#
  Géré par Ansible — rôle caddy_proxy. Ne pas éditer à la main sur le CT.
#}
# Reverse proxy public de la maison — généré par Ansible (roles/caddy_proxy).
# Le CT détient 80 et 443 : Caddy fonctionne en mode nominal, redirection HTTP→HTTPS
# et émission ACME incluses. C'est tout l'intérêt du déménagement depuis le NAS, où
# nginx/DSM occupait les deux ports et imposait le 8443 plus un certificat manuel.

{
	# Pas d'API d'administration : le rôle recharge par systemctl.
	admin off
	email {{ caddy_acme_email }}
{% if caddy_acme_staging %}
	# ⚠️ STAGING : les certificats émis ne sont PAS reconnus par les navigateurs.
	# Basculer en production en passant caddy_acme_staging à false.
	acme_ca {{ caddy_acme_staging_ca }}
{% endif %}
}

(secure_headers) {
	header {
{% if caddy_hsts_max_age | int > 0 %}
		Strict-Transport-Security "max-age={{ caddy_hsts_max_age }}; includeSubDomains"
{% endif %}
		X-Content-Type-Options "nosniff"
		Referrer-Policy "strict-origin-when-cross-origin"
		-Server
	}
}

{% for vhost in caddy_vhosts %}
# --- {{ vhost.name }} {{ '(privé, filtré)' if vhost.allow_networks is defined else '(public)' }}
https://{{ vhost.name }} {
	import secure_headers

	# Le matcher de réponse par défaut d'`encode` ne cible que text/*, JSON, JS, wasm,
	# SVG et polices : les JPEG, HEIC et vidéos, déjà compressés, sont exclus d'office.
	encode zstd gzip

{% if vhost.allow_networks is defined %}
	# Vhost privé : Caddy écoute pour tout le monde — il le faut pour le challenge
	# ACME — mais ne répond qu'aux origines déclarées.
	@allowed remote_ip {{ vhost.allow_networks | join(' ') }}
	handle @allowed {
{% if vhost.upstream_tls | default(false) %}
		reverse_proxy https://{{ vhost.backend }} {
			header_up Host {{ vhost.name }}
			transport http {
{% if vhost.upstream_insecure | default(false) %}
				# Amont à certificat auto-signé (Proxmox, DSM avant déclaration du
				# nom) : on saute la vérification. Acceptable UNIQUEMENT parce que le
				# saut se fait sur le LAN, entre le CT et une machine de la maison —
				# jamais sur un amont traversant Internet.
				tls
				tls_insecure_skip_verify
{% else %}
				tls
				tls_server_name {{ vhost.name }}
{% endif %}
			}
		}
{% else %}
		reverse_proxy {{ vhost.backend }}
{% endif %}
	}
	handle {
		respond "Not found" 404
	}
{% else %}
{% if vhost.upstream_tls | default(false) %}
	# `header_up Host` est INDISPENSABLE devant DSM. Sans lui, nginx reçoit
	# `Host: <ip>:<port>`, ne trouve aucun server_name correspondant et retombe sur son
	# default_server — Web Station, pas DSM — qui répond 403 (« directory index of
	# /var/services/web/ is forbidden »). Avec l'ancien backend 5001 le default_server
	# servait DSM, d'où un 200 trompeur : mais DSM bâtissait ses redirections sur ce
	# Host et renvoyait le navigateur vers https://127.0.0.1:5001, lui faisant perdre
	# son cookie de session → « Your login is invalid. Please sign-in again ».
	reverse_proxy https://{{ vhost.backend }} {
		header_up Host {{ vhost.name }}
		transport http {
{% if vhost.upstream_insecure | default(false) %}
			# Amont à certificat auto-signé. Même traitement que pour les vhosts
			# privés, pour que l'option se comporte identiquement dans les deux cas.
			tls
			tls_insecure_skip_verify
{% else %}
			# Le vhost 443 de DSM présente le certificat system_FQDN : on force le SNI
			# plutôt que de désactiver la vérification.
			tls
			tls_server_name {{ vhost.name }}
{% endif %}
		}
	}
{% else %}
	# X-Forwarded-{For,Proto,Host} et les WebSockets sont gérés nativement. Caddy
	# n'impose ni limite de taille de corps ni timeout de lecture : les envois vidéo
	# de l'app mobile passent sans réglage.
	reverse_proxy {{ vhost.backend }}
{% endif %}
{% endif %}
}

{% endfor %}
```

- [ ] **Étape 5 : écrire les tâches et le handler**

Fichier `Ansible/roles/caddy_proxy/tasks/main.yml` :

```yaml
---
# Installe Caddy en paquet natif dans le CT et y déploie le Caddyfile généré.
#
# Paquet natif et non Docker : évite `nesting=1` sur un CT non privilégié, une couche
# d'images, et un healthcheck de contournement. Caddy est un binaire unique avec une
# unité systemd — le conteneur n'a rien d'autre à faire tourner.
#
# ⚠️ Le Caddyfile est VALIDÉ avant rechargement. Un fichier invalide déployé sur la
# porte d'entrée publique la casserait, et le rollback exigerait un accès au CT.

- name: Dépendances du dépôt Caddy
  ansible.builtin.apt:
    name:
      - debian-keyring
      - debian-archive-keyring
      - apt-transport-https
      - curl
    state: present
    update_cache: true

- name: Clé du dépôt Caddy
  ansible.builtin.get_url:
    url: https://dl.cloudsmith.io/public/caddy/stable/gpg.key
    dest: /etc/apt/keyrings/caddy-stable.asc
    mode: "0644"

- name: Dépôt Caddy
  ansible.builtin.apt_repository:
    repo: "deb [signed-by=/etc/apt/keyrings/caddy-stable.asc] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main"
    filename: caddy-stable
    state: present

- name: Paquet Caddy
  ansible.builtin.apt:
    name: caddy
    state: present
    update_cache: true

- name: Déposer le Caddyfile pour validation
  ansible.builtin.template:
    src: Caddyfile.j2
    dest: /etc/caddy/Caddyfile.new
    owner: root
    group: root
    mode: "0644"
  register: caddy_file_new

- name: Valider le Caddyfile avant de l'activer
  ansible.builtin.command: caddy validate --config /etc/caddy/Caddyfile.new
  when: caddy_file_new.changed
  changed_when: false

- name: Activer le Caddyfile validé
  ansible.builtin.copy:
    src: /etc/caddy/Caddyfile.new
    dest: /etc/caddy/Caddyfile
    remote_src: true
    owner: root
    group: root
    mode: "0644"
  when: caddy_file_new.changed
  notify: Recharger Caddy

- name: Service Caddy actif au démarrage
  ansible.builtin.systemd_service:
    name: caddy
    enabled: true
    state: started
  when: not ansible_check_mode
```

Fichier `Ansible/roles/caddy_proxy/handlers/main.yml` :

```yaml
---
# `reload` et non `restart` : Caddy recharge sa configuration sans fermer les
# connexions en cours, ce qui évite de couper un envoi vidéo en plein transfert.
- name: Recharger Caddy
  ansible.builtin.systemd_service:
    name: caddy
    state: reloaded
  when: not ansible_check_mode
```

- [ ] **Étape 6 : déclarer un seul vhost pour ce premier essai**

Fichier `Ansible/inventory/host_vars/caddy/main.yml` :

```yaml
---
# Vhosts servis par le CT. Un seul pour le premier essai : on valide la chaîne ACME
# avant d'y mettre le service dont dépendent deux utilisatrices non techniques.
caddy_vhosts:
  - name: photos.eonelia.fr
    backend: 192.168.1.112:2283
```

- [ ] **Étape 7 : dry-run puis run**

```bash
run-on auto 'cd /Users/aurel/git/resources/Ansible && \
  OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES ansible-playbook main_caddy_playbook.yml --tags proxy --check --diff'
run-on auto 'cd /Users/aurel/git/resources/Ansible && \
  OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES ansible-playbook main_caddy_playbook.yml --tags proxy'
```

Attendu : `failed=0`. Le dry-run saute la tâche systemd (garde `ansible_check_mode`) et
ne peut pas valider le Caddyfile puisque le fichier n'est pas écrit — c'est normal.

- [ ] **Étape 8 : vérifier que le certificat de staging a bien été émis**

```bash
run-on auto ssh root@192.168.1.210 'systemctl is-active caddy; journalctl -u caddy -n 30 --no-pager | grep -iE "certificate obtained|error|challenge"'
```

Attendu : `active`, et une ligne « certificate obtained successfully » pour
`photos.eonelia.fr`. En cas d'échec du challenge, la cause est presque toujours la
redirection du 80 (étape 2) ou une résolution publique absente.

- [ ] **Étape 9 : vérifier le service à travers le proxy, sans basculer le 443**

```bash
curl -sS -m 10 -k --resolve photos.eonelia.fr:443:192.168.1.210 \
  https://photos.eonelia.fr/api/server/version
```

Attendu : le JSON de version d'Immich. `-k` est requis et **attendu** ici : le
certificat de staging n'est pas reconnu. C'est le seul endroit du plan où `-k` est
légitime.

- [ ] **Étape 10 : vérifier l'idempotence, puis commit**

```bash
run-on auto 'cd /Users/aurel/git/resources/Ansible && \
  OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES ansible-playbook main_caddy_playbook.yml --tags proxy' | tail -3
git add Ansible/roles/caddy_proxy Ansible/inventory/host_vars/caddy/main.yml
git commit -m "feat(caddy_proxy): Caddy natif dans le CT, certificats ACME en staging"
```

Attendu : `changed=0`.

---

## Tâche 3 : Les vhosts publics au complet

**Fichiers :**

- Modifier : `Ansible/inventory/host_vars/caddy/main.yml`

**Interfaces :**

- Consomme : `caddy_vhosts` et le template de la tâche 2.
- Produit : les deux vhosts publics servis par le CT, prêts pour la bascule du 443.

- [ ] **Étape 1 : ajouter le vhost DSM**

Remplacer le contenu de `Ansible/inventory/host_vars/caddy/main.yml` par :

```yaml
---
# Vhosts servis par le CT.
#
# DSM reste sur le NAS : ce vhost traverse donc le LAN vers 192.168.1.7, là où
# l'ancien proxy visait son propre loopback. `upstream_tls: true` suffit : le template
# émet `header_up Host` automatiquement dès qu'il est vrai (il n'existe pas de clé
# `header_up_host` séparée) — voir son commentaire, qui documente le 403 Web Station
# et le « Your login is invalid » que l'absence de ce header provoque.
caddy_vhosts:
  - name: photos.eonelia.fr
    backend: 192.168.1.112:2283
  - name: nas.eonelia.fr
    backend: 192.168.1.7:443
    upstream_tls: true
```

- [ ] **Étape 2 : appliquer**

```bash
run-on auto 'cd /Users/aurel/git/resources/Ansible && \
  OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES ansible-playbook main_caddy_playbook.yml --tags proxy'
```

Attendu : `changed=2` (Caddyfile réécrit + handler de rechargement).

- [ ] **Étape 3 : vérifier les deux vhosts, DSM par un vrai login**

```bash
curl -sS -m 10 -k --resolve photos.eonelia.fr:443:192.168.1.210 \
  -o /dev/null -w "photos: %{http_code}\n" https://photos.eonelia.fr/
curl -sS -m 10 -k --resolve nas.eonelia.fr:443:192.168.1.210 \
  -o /dev/null -w "nas: %{http_code}\n" https://nas.eonelia.fr/
```

Attendu : `200` pour les deux.

⚠️ **`200` sur `nas.eonelia.fr` ne suffit PAS.** C'est exactement ce que le piège
historique laissait passer : DSM répondait 200 tout en construisant ses redirections sur
un mauvais `Host`, faisant perdre le cookie de session. **Ouvrir un navigateur, forcer
la résolution vers `192.168.1.210` (fichier `hosts` local), et se connecter réellement
à DSM.** Sans cette vérification manuelle, ne pas passer à la tâche suivante.

- [ ] **Étape 4 : commit**

```bash
git add Ansible/inventory/host_vars/caddy/main.yml
git commit -m "feat(caddy_proxy): ajoute le vhost DSM, backend sur le NAS"
```

---

## Tâche 4 : Passage en production Let's Encrypt

**Fichiers :**

- Modifier : `Ansible/inventory/host_vars/caddy/main.yml`

**Interfaces :**

- Consomme : les vhosts validés en staging.
- Produit : des certificats reconnus publiquement, condition de la bascule du 443.

- [ ] **Étape 1 : basculer le drapeau**

Ajouter en tête de `Ansible/inventory/host_vars/caddy/main.yml` :

```yaml
# Staging validé : certificats émis, challenge HTTP-01 fonctionnel sur les deux noms,
# DSM vérifié par un login réel et non par un simple code 200. On passe en production.
caddy_acme_staging: false
```

- [ ] **Étape 2 : appliquer et purger les certificats de staging**

Caddy conserve les certificats de staging dans son répertoire de données ; il faut les
retirer pour qu'il en demande de nouveaux à la production.

```bash
run-on auto ssh root@192.168.1.210 'systemctl stop caddy && rm -rf /var/lib/caddy/.local/share/caddy/certificates && systemctl start caddy'
run-on auto 'cd /Users/aurel/git/resources/Ansible && \
  OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES ansible-playbook main_caddy_playbook.yml --tags proxy'
```

- [ ] **Étape 3 : vérifier que les certificats sont reconnus, SANS `-k`**

```bash
for n in photos.eonelia.fr nas.eonelia.fr; do
  curl -sS -m 10 --resolve "$n:443:192.168.1.210" -o /dev/null \
    -w "$n : http=%{http_code} verif_tls=%{ssl_verify_result}\n" "https://$n/"
done
```

Attendu : `http=200` et **`verif_tls=0`** pour les deux. L'absence de `-k` est le test :
si le certificat n'était pas reconnu, `curl` échouerait.

- [ ] **Étape 4 : confirmer l'émetteur**

`caddy list-certificates` n'existe pas dans la version de Caddy déployée
(`Error: unknown command "list-certificates"`, constaté à l'exécution de cette étape —
voir `task-4-report.md`). Lire directement l'émetteur et l'échéance des `.crt` sur disque :

```bash
run-on auto ssh root@192.168.1.210 'for f in /var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/*/*.crt; do echo "== $f =="; openssl x509 -noout -issuer -dates -in "$f"; done'
```

Attendu : l'émetteur est Let's Encrypt (et non `acme-staging`), avec une échéance à
environ 90 jours.

- [ ] **Étape 5 : commit**

```bash
git add Ansible/inventory/host_vars/caddy/main.yml
git commit -m "feat(caddy_proxy): passe les certificats en production Let's Encrypt"
```

---

## Tâche 5 : Bascule de la porte d'entrée

**Fichiers :** aucun. Action d'exploitation, avec rollback en un clic.

- [ ] **Étape 1 : basculer le 443 dans la Freebox** _(action humaine)_

Freebox OS → Gestion des ports : modifier la redirection `WAN 443` pour qu'elle pointe
`192.168.1.210:443`. **Désactiver** l'ancienne règle `443 → NAS:8443` par son toggle,
sans la supprimer : c'est le rollback.

- [ ] **Étape 2 : vérifier depuis l'extérieur, pas depuis le LAN**

```bash
curl -sS -m 10 -o /dev/null -w "photos: http=%{http_code} verif_tls=%{ssl_verify_result}\n" https://photos.eonelia.fr/
curl -sS -m 10 -o /dev/null -w "nas:    http=%{http_code} verif_tls=%{ssl_verify_result}\n" https://nas.eonelia.fr/
```

À lancer **depuis un réseau mobile ou depuis ce conteneur** (qui sort par une autre IP
publique), et non depuis le LAN : le hairpin de la Freebox peut masquer une règle fausse
en servant la requête localement.

- [ ] **Étape 3 : vérifier ce que curl ne voit pas**

Depuis un téléphone, sur données mobiles : ouvrir l'app Immich, **envoyer une vidéo**, et
vérifier que la synchronisation temps réel fonctionne. C'est le cas qui révèle les
proxies mal réglés — les WebSockets et les corps de requête volumineux — et aucun `curl`
ne le remplace.

- [ ] **Étape 4 : rollback si l'un des trois échoue**

Réactiver la règle `443 → NAS:8443` et désactiver la nouvelle. Le Caddy du NAS est resté
installé et configuré : le service revient sans exécuter d'Ansible.

---

## Tâche 6 : Rattacher le CT au tailnet

**Pourquoi :** l'horizon tailnet du split-horizon DNS a besoin d'une IP `100.64.x` pour
le proxy. À noter que l'Optiplex lui-même n'est pas sur le tailnet — `tailscale status`
ne montre aucun nœud le concernant malgré le commit `a5625d4`.

**Fichiers :**

- Modifier : `Ansible/main_headscale_playbook.yml` (ajouter `caddy_hosts` au play qui
  applique `tailscale_client`)

- [ ] **Étape 1 : lire le play existant pour en suivre le modèle**

```bash
grep -n -B5 -A15 "tailscale_client" Ansible/main_headscale_playbook.yml
```

- [ ] **Étape 2 : ajouter `caddy_hosts` à la liste des hôtes du play `tailscale_client`**

Le play produit une preauthkey côté headscale puis l'utilise ; ajouter le nouvel hôte à
son `hosts:` suffit, sans dupliquer la logique.

- [ ] **Étape 3 : appliquer** _(à lancer par l'humain — KeePass requis)_

```bash
cd ~/git/resources/Ansible
make headscale
```

- [ ] **Étape 4 : vérifier l'enrôlement**

```bash
run-on auto 'tailscale status | grep -i caddy'
```

Attendu : une ligne avec une IP `100.64.x.x` pour le nœud `caddy`.

- [ ] **Étape 5 : commit**

```bash
git add Ansible/main_headscale_playbook.yml
git commit -m "feat(caddy): rattache le CT du proxy au tailnet"
```

---

## Tâche 7 : Vhosts privés — certificats valides sans port ouvert

**Fichiers :**

- Modifier : `Ansible/inventory/host_vars/caddy/main.yml`

**Prérequis DNS :** chaque nom privé a besoin d'un enregistrement A public chez IONOS
pointant vers `82.67.69.38`. HTTP-01 l'exige. Ce n'est pas une fuite d'information : les
certificats Let's Encrypt sont publiés dans les journaux Certificate Transparency, donc
ces noms seraient publics de toute façon. Le service, lui, reste fermé par `remote_ip`.

- [ ] **Étape 1 : créer les enregistrements A chez IONOS** _(action humaine)_

`ha.eonelia.fr`, `dsm.eonelia.fr`, `pve.eonelia.fr` → `82.67.69.38`.

- [ ] **Étape 2 : ajouter les trois vhosts privés**

Ajouter à `caddy_vhosts` dans `Ansible/inventory/host_vars/caddy/main.yml` :

```yaml
# Vhosts privés : filtrés par remote_ip au tailnet et au LAN. Ils obtiennent un
# certificat public (le challenge ACME arrive sur le 80, hors du filtre) mais ne
# répondent qu'aux origines déclarées — d'où un certificat valide pour ces
# interfaces sans ouvrir le moindre port de service.
#
# ⚠️ Ces entrées s'ajoutent À LA LISTE caddy_vhosts existante : les aligner sur
# l'indentation des vhosts déjà présents (deux espaces avant le tiret).
- name: ha.eonelia.fr
  backend: 192.168.1.6:8123
  allow_networks: ["100.64.0.0/10", "192.168.1.0/24"]
# Proxmox présente un certificat AUTO-SIGNÉ sur son interface 8006 : forcer le SNI
# ferait échouer la vérification de l'amont, d'où upstream_insecure. Le saut non
# vérifié reste sur le LAN, entre le CT et l'hyperviseur.
- name: pve.eonelia.fr
  backend: 192.168.1.100:8006
  upstream_tls: true
  upstream_insecure: true
  allow_networks: ["100.64.0.0/10", "192.168.1.0/24"]
```

`dsm.eonelia.fr` est volontairement omis : `nas.eonelia.fr` sert déjà DSM en public, et
en ajouter un doublon privé n'apporte rien.

- [ ] **Étape 3 : appliquer**

```bash
run-on auto 'cd /Users/aurel/git/resources/Ansible && \
  OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES ansible-playbook main_caddy_playbook.yml --tags proxy'
```

- [ ] **Étape 4 : vérifier que le filtrage fonctionne dans les deux sens**

```bash
# Depuis ce conteneur, HORS du LAN et hors tailnet du domicile → doit être refusé
curl -sS -m 10 -o /dev/null -w "depuis Internet: %{http_code} (attendu 404)\n" https://ha.eonelia.fr/
```

Puis, depuis le Mac (sur le LAN) :

```bash
run-on auto 'curl -sS -m 10 -o /dev/null -w "depuis le LAN: %{http_code} (attendu 200 ou 302)\n" https://ha.eonelia.fr/'
```

Attendu : `404` depuis Internet, `200` ou `302` depuis le LAN, **et un certificat valide
dans les deux cas** (aucune erreur TLS).

- [ ] **Étape 5 : commit**

```bash
git add Ansible/inventory/host_vars/caddy/main.yml
git commit -m "feat(caddy_proxy): vhosts privés HA et Proxmox, filtrés au tailnet et au LAN"
```

---

## Tâche 8 : Retirer le proxy du NAS

**À ne faire qu'après une période d'observation** — une semaine au moins, et au minimum
un renouvellement automatique de certificat observé.

**Fichiers :**

- Supprimer : `Ansible/roles/immich_proxy/` (tout le répertoire)
- Supprimer : `Ansible/main_immich_playbook.yml`
- Modifier : `Ansible/Makefile` (retirer `immich` et `check-immich`)
- Modifier : `Ansible/inventory/host_vars/nas.eonelia.fr/main.yml` (retirer
  `immich_proxy_backend`)
- Modifier : `Ansible/inventory/host_vars/nas.eonelia.fr/secrets.yml` (retirer les
  lookups du certificat, garder `ansible_become_password`)

- [ ] **Étape 1 : vérifier qu'un renouvellement automatique a eu lieu**

```bash
run-on auto ssh root@192.168.1.210 'journalctl -u caddy --since "-30 days" | grep -i "certificate obtained\|renewed" | tail -5'
```

Ne pas continuer sans au moins une ligne de renouvellement : c'est la seule preuve que
l'automatisation fonctionne réellement.

- [ ] **Étape 2 : arrêter le stack Caddy du NAS** _(nécessite le mot de passe sudo)_

```bash
ssh -p 3434 a.busutil@100.64.0.6 'sudo /usr/local/bin/docker compose -f /volume1/docker/immich-proxy/docker-compose.yml down'
```

- [ ] **Étape 3 : supprimer la redirection Freebox `443 → NAS:8443`** _(action humaine)_

Désactivée depuis la tâche 5 ; on peut désormais la supprimer.

- [ ] **Étape 4 : retirer le rôle du dépôt**

```bash
git rm -r Ansible/roles/immich_proxy Ansible/main_immich_playbook.yml
```

Puis éditer le Makefile et les deux fichiers de `host_vars` listés ci-dessus.

- [ ] **Étape 5 : vérifier que rien ne référence plus le rôle**

```bash
grep -rn "immich_proxy" Ansible/ | grep -v "^Ansible/docs/"
```

Attendu : aucune ligne hors documentation. Les mentions dans `Ansible/docs/` sont
historiques et doivent rester.

- [ ] **Étape 6 : lint et commit**

```bash
run-on auto 'cd /Users/aurel/git/resources/Ansible && make lint 2>&1 | tail -5'
git add -A Ansible/
git commit -m "chore(immich_proxy): retire le proxy du NAS, remplacé par le CT Caddy"
```

---

## Ce que ce plan ne couvre pas

Chacun de ces points a sa propre justification dans la spec et doit faire l'objet de son
cycle :

- **Le split-horizon DNS** (VM `dnsmasq` sur la Freebox). Indépendant : le proxy
  fonctionne sans lui, le hairpin de la Freebox continuant d'assurer l'accès depuis le
  domicile. Le plan doit être écrit après la tâche 5, l'IP du CT étant sa donnée
  d'entrée.
- **Le certificat de `headscale`** (`mom.eonelia.fr`, chez la mère d'Aurélien). Il reste
  sur le wildcard manuel. Le placer derrière ce Caddy est à écarter : cela ferait
  dépendre le plan de contrôle du tailnet de la connexion domestique. La voie propre est
  un ACME local sur le Wyse.
- **La fermeture des redirections `2283`, `4343`, `6690` et `7258`.** À traiter par
  toggle et 48 h d'observation, indépendamment du proxy.
- **Le désengorgement du NAS** (`synoelasticd` et ses 195 minutes de CPU).

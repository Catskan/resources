# Headscale + Tailscale (accès Mac cross-site) — déploiement Ansible

Control plane **Headscale** auto-hébergé (LXC dédié sur le Wyse) + clients **Tailscale**,
pour donner au Mac une **IP tailnet `100.x` stable** injectable dans `hosts.json` → `run-on`
joint le Mac quelle que soit l'interface (dock `.8` / Wi-Fi `.116`) ou le site.

## Fichiers livrés

- `roles/proxmox_headscale_lxc/` — crée le CT 102 « headscale » via `pct` (clone de `proxmox_claude_lxc`).
- `roles/headscale/` — install headscale, config TLS wildcard, preauthkey, updater DynDNS IONOS.
- `roles/tailscale_client/` — rattache un hôte au tailnet (appliqué au CT claude-code).
- `main_headscale_playbook.yml` — orchestrateur (4 plays : LXC → headscale → tun → client).
- `inventory/host_vars/headscale/{connection,secrets}.yml`.

## 1. Patch inventaire — `inventory/hosts.yaml`

Ajouter le groupe sous `all.children` :

```yaml
headscale_hosts:
  hosts:
    headscale:
```

## 2. Patch `Makefile`

Ajouter aux `.PHONY` `headscale check-headscale`, puis les cibles :

```make
headscale:
	./scripts/run.sh ansible-playbook main_headscale_playbook.yml $(ARGS)

check-headscale:
	./scripts/run.sh ansible-playbook main_headscale_playbook.yml --check --diff $(ARGS)
```

## 3. Entrée KeePass (déjà en place)

Entrée **`Certificate *.eonelia.fr`** (groupe racine) avec **4 attachments** :

| Attachment                       | Rôle                              |
| -------------------------------- | --------------------------------- |
| `eonelia.fr_ssl_certificate.cer` | certificat feuille `*.eonelia.fr` |
| `intermediate1.cer`              | intermédiaire 1                   |
| `intermediate2.cer`              | intermédiaire 2                   |
| `*.eonelia.fr_private_key.key`   | clé privée                        |

Le rôle copie ces 4 fichiers sur le CT, normalise les `.cer` en PEM (`openssl`, gère PEM et DER)
et assemble la fullchain `feuille + int1 + int2`. Rien à concaténer à la main.
Références dans `inventory/host_vars/headscale/secrets.yml` (lookups `viczem.keepass … attachments`).

## 4. Étapes manuelles (hors Ansible)

1. **IONOS** : enregistrement **A statique** `mom.eonelia.fr → 82.67.182.91` (IP publique fixe de la Freebox de la mère). Pas de DynDNS (IP fixe).
2. **Freebox de la mère** (`82.67.182.91`) : redirection **`TCP 34443 → 192.168.1.168:34443`**. headscale écoute sur **34443 pour des raisons historiques** : la ligne était en **IPv4 partagée**, qui ne donnait à cet abonné qu'une plage de ports > 32768 et interdisait toute redirection sous ce seuil (dont 443) — ce n'était ni une limitation de la box ni une réservation du port 443. Le passage en **IPv4 full-stack** (2026-08-18) a levé cette contrainte : une redirection `WAN:443` fonctionne désormais. ⚠️ **Ne pas migrer headscale vers 443 pour autant** : son `server_url` en `:34443` est inscrit dans la config de chaque nœud déjà enrôlé, changer de port les décrocherait tous.
3. **Mac** (à la maison) : installer Tailscale, puis
   `tailscale up --login-server=https://mom.eonelia.fr:34443 --authkey <preauthkey>`.
   Récupérer son IP : `tailscale ip -4` → **la mettre dans `hosts.json` `.public` = `abusutil@100.x.y.z:2022`**.

## 5. Ordre de déploiement

```bash
make headscale ARGS='--limit proxmox_hosts'    # crée le CT 102 → note son IP DHCP
# reporter l'IP dans inventory/host_vars/headscale/connection.yml (ansible_host)
# créer la réservation DHCP du CT 102 sur la Freebox mère + le port-forward 443
make headscale ARGS='--limit headscale_hosts'  # install+config serveur (TLS, DynDNS, user, preauthkey)
make headscale                                 # run complet : + tun CT101 + client tailscale sur claude-code
```

Puis rattacher le Mac (étape 4.3) et mettre son `100.x` dans `hosts.json`.

## 6. Mode TLS : `certfile` (défaut) vs `acme` (Let's Encrypt natif)

Le rôle sait poser TLS de deux façons, sélectionnées par `headscale_tls_mode`
(`roles/headscale/defaults/main.yml`) :

| Mode                    | Ce qu'il fait                                                         | Statut                |
| ----------------------- | --------------------------------------------------------------------- | --------------------- |
| `certfile` (**défaut**) | wildcard commercial `*.eonelia.fr` recopié depuis KeePass (section 3) | comportement actuel   |
| `acme`                  | headscale émet/renouvelle lui-même via Let's Encrypt (TLS-ALPN-01)    | préparé, PAS appliqué |

Les deux mécaniques coexistent dans le rôle : passer de l'un à l'autre est un
changement de variable + un run, jamais une réécriture de code.

### Pourquoi TLS-ALPN-01 (et pas HTTP-01)

- **TLS-ALPN-01** : le challenge est répondu directement sur le listener TLS que
  headscale a déjà ouvert (`headscale_listen_addr`). Aucun port 80 à exposer sur
  un réseau tiers (chez la mère), aucun service supplémentaire à faire tourner.
- **HTTP-01** aurait exigé un listener `:http` dédié (`tls_letsencrypt_listen`
  dans la config headscale) — donc un port 80 en plus du 34443/443 déjà en jeu.
  Pas retenu.

### Prérequis réseau — À FAIRE À LA MAIN avant de basculer en `acme`

1. **Redirection `WAN:443 → CT:34443` sur la Freebox de la mère.** Let's Encrypt
   se connecte systématiquement sur le port **443** de `mom.eonelia.fr` (fixe,
   non configurable côté protocole ACME) — **la redirection existante du 34443
   ne suffit pas**, elle ne couvre que le trafic tailnet normal, pas la
   validation ACME qui arrive sur 443.
   ⚠️ Ce même document et `defaults/main.yml` rappellent déjà que « la Freebox
   mère interdit les redirections sur port < 32768 (443 réservé à Freebox OS) » —
   c'est justement pourquoi headscale écoute sur 34443 aujourd'hui. **Vérifier
   concrètement, avant de committer sur ce mode, que l'interface de la Freebox
   accepte une règle avec 443 en port WAN.** Si ce n'est pas possible, le mode
   `acme` est bloqué par le matériel réseau, indépendamment de ce rôle.
2. **Réservation DHCP du CT headscale (VMID 102), pas encore posée.**
   `inventory/host_vars/headscale/connection.yml` documente déjà que
   `ansible_host: 192.168.1.168` est une IP **DHCP** et attend cette réservation.
   Rediriger le port 443 vers une IP qui peut bouger casse le **renouvellement**
   en silence : headscale continue de servir l'ancien certificat jusqu'à son
   expiration, puis la panne TLS apparaît **~60 jours plus tard**, sans lien
   apparent avec sa cause réelle. La réservation DHCP est un **prérequis** du
   mode `acme`, pas un confort.

### Variables (`roles/headscale/defaults/main.yml`)

```yaml
headscale_tls_mode: "certfile" # certfile | acme

headscale_acme_url: "https://acme-staging-v02.api.letsencrypt.org/directory" # staging par défaut
headscale_acme_email: "" # à renseigner avant de passer en acme
headscale_tls_letsencrypt_hostname: "mom.eonelia.fr"
headscale_tls_letsencrypt_cache_dir: "/var/lib/headscale/cache"
headscale_tls_letsencrypt_challenge_type: "TLS-ALPN-01"
```

Le **staging** Let's Encrypt (`acme-staging-v02`) est le défaut : une émission
ratée en **production** consomme un quota limité (échecs / certificats dupliqués
par semaine), et une boucle de tentatives le brûle pour plusieurs jours. Passer
en prod (`https://acme-v02.api.letsencrypt.org/directory`) est un choix
explicite — jamais automatique.

### Procédure d'application (quand les 2 prérequis réseau ci-dessus sont posés)

```bash
# 1. Poser la réservation DHCP + le port-forward WAN:443 → CT:34443 sur la Freebox mère.
# 2. Renseigner headscale_acme_email (host_vars/headscale ou defaults).
# 3. headscale_tls_mode: acme reste sur le staging LE par défaut → valider que le
#    certificat staging est bien émis et que headscale redémarre proprement :
make headscale ARGS='--limit headscale_hosts'
# 4. Une fois le staging validé, passer headscale_acme_url en prod et re-run :
#    headscale_acme_url: "https://acme-v02.api.letsencrypt.org/directory"
make headscale ARGS='--limit headscale_hosts'
```

### Repli vers `certfile`

Le mode `certfile` reste le chemin de repli — **rien n'a été supprimé** de la
mécanique existante (wildcard KeePass, section 3 ci-dessus). En cas de problème
avec l'émission ACME (quota épuisé, redirection Freebox impossible à poser,
renouvellement en échec) :

```yaml
headscale_tls_mode: "certfile" # dans defaults/main.yml ou en override host_vars
```

puis `make headscale ARGS='--limit headscale_hosts'`. Le rôle re-dépose le
wildcard KeePass (toujours utilisable — `secrets.yml` n'a pas été touché) et
retemplate `config.yaml` avec `tls_cert_path`/`tls_key_path`. Aucune étape
manuelle supplémentaire : c'est le but de garder les deux mécaniques en place.

## Prérequis / notes

- Collection **`viczem.keepass`** déjà utilisée par le repo (secrets).
- **DERP** : relais publics Tailscale par défaut (fallback chiffré). Pour du strict 100 % self-hosted, activer un DERP local (`derp.server.enabled: true` dans `config.yaml.j2`).
- Vérifier la dernière release Headscale (`headscale_version` dans `roles/headscale/defaults/main.yml`).
- Le CT claude-code (101) est **privilégié** → le play « tun » ajoute `/dev/net/tun` (kernel-mode) ; le conteneur Docker en `network_mode: host` hérite alors de `tailscale0` et des routes `100.x`.

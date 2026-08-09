# immich_proxy — reverse proxy TLS devant Immich (NAS Synology)

Déploie **Caddy** en frontal HTTPS sur le NAS, avec le wildcard `*.eonelia.fr` repris
des mêmes attachments KeePass que le CT `headscale`. Objectif : que la compagne et la
mère accèdent à Immich depuis n'importe où, **sans VPN**, sur une URL sans port —
condition pour que le backup photo automatique d'iOS fonctionne sans manipulation.

## Architecture

```
                       Freebox (IP publique fixe)
                        │
        WAN:443 ────────┼───────► 192.168.1.7:8443    (Caddy, network_mode: host)
                        │              ├─ photos.eonelia.fr ─► 127.0.0.1:2283  Immich
                        │              └─ nas.eonelia.fr    ─► 127.0.0.1:443   DSM
                        │
        WAN:4343 ───────┴───────► 192.168.1.7:5001    (DSM en direct — secours)
```

Le routage se fait **par nom d'hôte (SNI), pas par port** : tout arrive sur 8443, et
Caddy choisit le backend selon le domaine annoncé au handshake TLS. Un seul
certificat wildcard couvre les deux noms.

Deux adresses à ne pas confondre :

| Usage                               | Adresse                                                      |
| ----------------------------------- | ------------------------------------------------------------ |
| Ansible (inventaire `ansible_host`) | `100.64.0.6` — IP tailnet, joignable hors LAN                |
| Redirections Freebox                | `192.168.1.7` — IP LAN, la seule que le routeur sait joindre |

Pourquoi 8443 et pas 443 : **nginx/DSM occupe déjà 80 et 443** sur le NAS. Plutôt que
de déplacer DSM, Caddy prend un port haut et c'est la Freebox qui traduit. Les
utilisateurs tapent `https://photos.eonelia.fr`, sans port.

Pourquoi `network_mode: host` : Caddy joint ses backends en **loopback**, donc ce
stack ne dépend ni du réseau Docker du compose Immich, ni de son nom de projet.
**Le `docker-compose.yml` d'Immich n'est jamais touché.**

Pourquoi Caddy plutôt que le reverse proxy intégré de DSM : ce dernier hérite de la
limite nginx de taille de corps de requête (HTTP 413 sur les uploads vidéo), et le
correctif passe par des fichiers nginx que DSM réécrit à ses mises à jour. Caddy n'a
ni limite de corps ni timeout de lecture par défaut, et sa config est versionnée ici.

## ⚠ Contrainte structurante : pas de Python exploitable sur le NAS

DSM 7.3.2 ne fournit que **Python 3.7 et 3.8** (paquets `python3` et `python38`),
alors qu'**ansible-core ≥ 2.19 exige Python 3.9+ sur la cible**. Synology ne propose
pas d'interpréteur plus récent au catalogue. Toute tâche utilisant un module Python
échoue donc avec :

```
Ansible requires Python 3.9 or newer on the target. Current version: 3.8.15
```

Le rôle contourne cela **sans rien installer sur le NAS** :

- côté NAS, uniquement `ansible.builtin.raw` (n'a besoin d'aucun Python) ;
- côté contrôleur (`delegate_to: localhost`), tout ce qui demande Python : openssl
  pour normaliser les `.cer` et assembler la fullchain, et le rendu Jinja des deux
  templates ;
- transfert par **`scp -O`** — le mode legacy est obligatoire, le subsystem SFTP
  étant désactivé sur ce NAS (un scp moderne échoue en « subsystem request failed »).
  `ansible.posix.synchronize` n'est pas une option : macOS livre désormais
  _openrsync_, qui gère mal `-e`.

**Ne pas réintroduire `copy` / `template` / `file` / `wait_for` ciblant le NAS** — le
play casserait. Le play doit aussi rester en `gather_facts: false` (le module `setup`
exigerait Python).

Conséquence sur `make check-immich` : Ansible saute les tâches `raw` en `--check`, le
dry-run confirme donc surtout la joignabilité et la résolution KeePass, pas le diff
des fichiers.

## Ce que le rôle fait

1. vérifie Docker et détecte `docker compose` (v2) ou `docker-compose` ;
2. sonde `http://127.0.0.1:2283/api/server/ping` et avertit si Immich est absent ;
3. **sur le contrôleur** : normalise les `.cer` en PEM (gère PEM _et_ DER), assemble
   la fullchain `feuille + int1 + int2`, rend les templates, affiche l'expiration ;
4. transfère les 4 fichiers vers un staging `/tmp` sur le NAS ;
5. les installe (root, clé privée en `0600`) **seulement si le contenu diffère** —
   c'est ce qui rend le rôle idempotent et déclenche le handler ;
6. **valide le Caddyfile** (`caddy validate` en conteneur jetable) avant de toucher au
   conteneur en service — un Caddyfile invalide couperait aussi l'accès DSM externe ;
7. `compose up -d`, puis interroge la sonde de santé.

Certificats et Caddyfile étant montés en volume, un changement déclenche un simple
`docker restart` (coupure < 1 s), pas une recréation.

## Prérequis manuels (hors Ansible)

1. **IONOS** — ✅ déjà fait : `photos.eonelia.fr` et `nas.eonelia.fr` résolvent tous
   deux vers `82.67.69.38`, l'IP publique fixe de la Freebox maison (confirmée depuis
   le NAS lui-même, qui sort bien par ce site et non par celui de la mère).
2. **Freebox** — rediriger **`TCP 443 → 192.168.1.7:8443`**. C'est le seul changement
   obligatoire : l'ancienne règle `443 → 443` doit être remplacée.
3. **Freebox, optionnel mais recommandé** — `TCP 4343 → 192.168.1.7:5001` : accès DSM
   de secours indépendant de Caddy. Sans lui, si le conteneur tombe tu perds l'accès
   DSM _depuis l'extérieur_ (le LAN et le tailnet restent intacts).
4. **Pare-feu DSM** — si activé, autoriser le port `8443` en entrée.
5. **DSM → Portail de connexion → onglet DSM → « Nom de domaine » = `nas.eonelia.fr`**
   ⚠ obligatoire, et indissociable de `immich_dsm_backend: 127.0.0.1:443`.
   Déclarer ce nom fait générer à DSM un vhost `listen 443` portant
   `set $fqdn nas.eonelia.fr` : c'est le seul qui sert DSM **et** émet ses redirections
   vers le bon nom. Il n'est atteint que si Caddy envoie `Host: nas.eonelia.fr`, d'où le
   `header_up Host` du template — les deux réglages sont indissociables. Sans le
   `header_up`, nginx reçoit `Host: 127.0.0.1:<port>`, ne trouve aucun `server_name`
   correspondant et sert son `default_server` : Web Station sur 443 (403 « directory
   index forbidden »), ou DSM sur 5001 — qui répond 200 mais bâtit ses redirections sur
   ce Host et renvoie le navigateur vers `https://127.0.0.1:5001`, lui faisant perdre
   son cookie de session → « Your login is invalid. Please sign-in again ».
   Vérification en une commande, depuis n'importe quel nœud du tailnet :

   ```bash
   curl -skI --resolve nas.eonelia.fr:443:100.64.0.6 https://nas.eonelia.fr/webman/index.cgi
   # attendu : location: https://nas.eonelia.fr/      (et NON https://127.0.0.1:5001/)
   ```

6. **DSM → Sécurité → Général — « ignorer la vérification de l'adresse IP »** — recommandé,
   pour une raison distincte du point 5. Le nginx de DSM contient `set_real_ip_from
127.0.0.1` + `real_ip_header X-Forwarded-For` : il fait confiance à Caddy et
   substitue l'IP réelle du client. Avec `skip_checksrcip="no"` (défaut), DSM lie la
   session à cette IP et l'invalide dès qu'elle change — ce qui arrive en 4G.
   Ne PAS « corriger » cela en retirant `X-Forwarded-For` côté Caddy : le blocage
   automatique d'IP de DSM bannirait alors `127.0.0.1`, c'est-à-dire Caddy, coupant
   l'accès à tous les clients d'un coup.
7. **Immich** — son compose doit publier `2283` sur l'hôte (c'est le défaut). Une fois
   le proxy validé, tu peux restreindre cette publication à `127.0.0.1:2283:2283` pour
   que le HTTP en clair ne soit plus joignable depuis le LAN ni le tailnet.

## Sécurité — Immich devient public

- **Désactiver l'inscription publique** dans Immich (Administration → Paramètres) et
  créer les comptes à la main.
- **DSM** : activer la 2FA et le blocage automatique d'IP, puisque `nas.eonelia.fr`
  devient joignable publiquement.
- Immich publie régulièrement des correctifs de sécurité : prévoir une mise à jour
  mensuelle du stack.
- **Synology Drive Client** (synchro bureau) utilise le port **6690** en protocole
  propriétaire non-HTTP : Caddy ne peut pas le relayer, il lui faut sa propre
  redirection si tu l'utilises depuis l'extérieur.

## Renouvellement du certificat

Le wildcard est un certificat acheté, pas un ACME : il n'y a **pas** de renouvellement
automatique. À l'échéance (affichée à chaque run), remplacer les 4 attachments dans
l'entrée KeePass `Certificate *.eonelia.fr` puis relancer `make immich` — les mêmes
attachments servent aussi au CT `headscale`, donc relancer `make headscale` également.

## Lancement

```bash
make immich                                          # déploiement / mise à jour
make check-immich                                    # dry-run (portée limitée, cf. ci-dessus)
make immich ARGS='-e immich_proxy_hsts_max_age=0'    # tests : sans HSTS
```

## Variables principales (`defaults/main.yml`)

| Variable                    | Défaut                         | Rôle                                |
| --------------------------- | ------------------------------ | ----------------------------------- |
| `immich_proxy_domain`       | `photos.eonelia.fr`            | nom public d'Immich                 |
| `immich_dsm_domain`         | `nas.eonelia.fr`               | nom public de DSM                   |
| `immich_proxy_listen_port`  | `8443`                         | port d'écoute de Caddy sur le NAS   |
| `immich_proxy_health_port`  | `9180`                         | sonde de santé, loopback uniquement |
| `immich_proxy_backend`      | `127.0.0.1:2283`               | backend Immich                      |
| `immich_dsm_backend`        | `127.0.0.1:443`                | backend DSM                         |
| `immich_proxy_dir`          | `/volume1/docker/immich-proxy` | racine du stack proxy               |
| `immich_proxy_staging`      | `/tmp/.immich-proxy-build`     | dépôt scp temporaire                |
| `immich_proxy_hsts_max_age` | `31536000`                     | HSTS ; `0` désactive l'en-tête      |

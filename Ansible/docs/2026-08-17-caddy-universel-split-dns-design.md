# Reverse-proxy Caddy universel et split-horizon DNS

**Date** : 2026-08-17
**Statut** : design validé, prêt pour plan d'implémentation
**Périmètre** : le reverse-proxy du NAS, la résolution DNS locale, la réduction des
ports exposés. Ni migration de service, ni changement d'hébergement applicatif.

## Contexte

Le NAS Synology porte un reverse-proxy Caddy déployé par le rôle `immich_proxy`
(branche `feat/immich-proxy`). Il écoute sur `8443`, la Freebox traduisant
`WAN:443 → NAS:8443` puisque nginx/DSM occupe déjà 80 et 443. Le certificat est le
wildcard `*.eonelia.fr`, recopié à la main depuis KeePass et partagé avec le rôle
`headscale`, donc renouvelé manuellement une fois l'an en relançant deux rôles.

Trois faits mesurés le 2026-08-17 motivent ce chantier et en fixent l'ordre.

**Le proxy sert la mauvaise instance, et elle est morte.** `photos.eonelia.fr`
pointait encore sur `127.0.0.1:2283`, c'est-à-dire l'ancienne instance Immich du NAS,
alors que l'instance en service tourne depuis sur la VM 101 de l'Optiplex
(`192.168.1.112:2283`). Les deux répondant `v3.1.0`, l'URL publique ne trahissait rien :
seul le `Caddyfile` déployé permettait de trancher. En cours de session, l'ancienne
instance a cessé de répondre — plus rien n'écoute sur son port — et `photos.eonelia.fr`
renvoie `502`. Le correctif est déjà commité (`c297bb3`).

**Le NAS est saturé, et Caddy n'y est pour rien.** Celeron N3160 de 2016, 4 cœurs,
0 % d'idle, load average mesuré entre 21 et 57, 121 à 487 Mo de RAM libre et 2,7 Go
de swap consommé. Les postes dominants sont `synoelasticd` (paquet SynoFinder,
indexation de la Recherche universelle, 195 minutes de CPU cumulées), `dockerd`, et
les Chromium headless des bots. Caddy consomme quelques dizaines de mégaoctets.
L'hypothèse initiale — « éteindre l'ancienne instance Immich rendra son CPU au NAS » —
a été **infirmée** : l'instance est morte et le load est monté de 21 à 57.

**Sept redirections de ports sont actives**, dont quatre ouvertes à toutes les IP :
`2283` (Immich en HTTP clair), `4343 → 5001` (DSM), `6690` (Synology Drive),
`7258` (SFTP), `443 → 8443` (Caddy), plus `3434` (SSH) et `5566` (DSM Replication)
restreintes par IP source. Aucune connexion externe n'a été observée sur `2283`,
`6690` ni `7258` — les quatre connexions du SFTP étaient toutes en loopback.

Enfin, **il n'existe aucun split-horizon DNS** : depuis le LAN, `photos.eonelia.fr`
résout vers l'IP publique `82.67.69.38`. Le hairpin de la Freebox fonctionne (TLS
négocié en 0,22 s depuis le Mac), mais chaque octet envoyé depuis la maison monte
jusqu'à la box et redescend, deux traversées de son NAT.

## Objectif

Faire de Caddy le point d'entrée unique et paramétrable des services de la maison,
avec un certificat qui se renouvelle seul, un chemin réseau optimal selon l'endroit
d'où l'on vient, et le minimum de ports ouverts sur Internet.

## Périmètre

**Inclus**

- Renommage et généralisation du rôle `immich_proxy`, piloté par une liste de vhosts
- Distinction vhosts publics / vhosts privés filtrés par `remote_ip`
- Certificats ACME par challenge DNS-01 chez IONOS, en remplacement du wildcard manuel
- Split-horizon DNS par `dnsmasq` dans une VM sur la Freebox Ultra
- Enregistrements du tailnet côté Headscale
- Fermeture des redirections de ports devenues inutiles
- Cibles Makefile, documentation, procédure de vérification

**Exclu — décidé explicitement**

- **Le déménagement de Caddy vers l'Optiplex.** Voir D1.
- **La migration des bots (`vinted-bot`, `pokemon-monitor`) et du CT `claude-code`.**
  Mesures à l'appui : le CT `claude-code` consomme plusieurs gigaoctets sur son hôte
  actuel (8,6 Go de `used` sur les 16 Go du Wyse, dont ~3,4 Go pour les huit premiers
  processus), alors que l'Optiplex n'a que ~1,4 Go de marge. Ce n'est pas un arbitrage
  de préférence : la place n'existe pas.
- **Le désengorgement du NAS** (`synoelasticd`, Chromium des bots, restes de l'ancien
  Immich). C'est un prérequis mesurable de l'étape DNS, traité en exploitation et non
  par ce design.
- **Le remplacement de SFTP par WebDAV.** Caddy ne peut pas proxifier SSH ; le tailnet
  couvre le besoin. Si un besoin WebDAV apparaît, il rentrera dans la liste de vhosts
  sans changement de structure.

## Décisions structurantes

### D1 — Caddy reste sur le NAS

| Option                                                 | Verdict     |
| ------------------------------------------------------ | ----------- |
| A. Caddy reste sur le NAS, rôle généralisé             | **retenue** |
| B. CT Caddy dédié sur l'Optiplex (`proxmox_caddy_lxc`) | rejetée     |

B avait été retenue en première analyse, puis **abandonnée après mesure**. Les
bénéfices attendus ne résistent pas aux faits : la résilience n'en est pas un, car les
originaux d'Immich vivent sur le NAS en NFS — si le NAS tombe, Immich tombe où que soit
le proxy ; et la décharge CPU n'en est pas un non plus, Caddy ne pesant rien face à
`synoelasticd`. Restait l'hygiène (fin du `8443`, du `auto_https disable_redirects` et
du certificat manuel), dont **le certificat est traité par D4 sans déménager quoi que
ce soit**. B coûtait un CT, un rôle, une bascule de la porte d'entrée publique sous
HSTS, et de la RAM sur une machine qui n'en a plus. L'écart de valeur ne le justifie pas.

Conséquence directe : le rôle `proxmox_caddy_lxc` envisagé n'a plus d'objet.

### D2 — Le résolveur local va dans une VM sur la Freebox Ultra

| Option                                                         | Verdict                |
| -------------------------------------------------------------- | ---------------------- |
| A. `dnsmasq` en VM sur la Freebox Ultra                        | **retenue**            |
| B. `dnsmasq` en second service du compose du proxy, sur le NAS | rejetée pour l'instant |
| C. LXC dédié sur l'Optiplex (AdGuard Home ou dnsmasq)          | rejetée                |
| D. Enregistrements DNS locaux dans la Freebox                  | impossible             |
| E. Ne rien faire, garder le hairpin                            | repli acceptable       |

D a été éliminée sur constat : l'écran _Réseau local / DHCP_ de la Freebox ne permet
que de **distribuer** des serveurs DNS (cinq champs), pas de créer des enregistrements.
Les baux statiques ne produisent que des noms en `.home`.

A est retenue pour une raison qui la distingue de toutes les autres : **la Freebox est
déjà le point unique dont la panne coupe Internet et le DHCP.** Y placer le DNS
n'ajoute aucun point de défaillance, alors que B et C en créent un — et C sur une
machine qui a démontré le 2026-08-17 qu'elle peut disparaître du réseau trente minutes
(voir `2026-08-16-optiplex-proxmox-socle-design.md` et le bug e1000e traité depuis).
La faisabilité est acquise : Home Assistant y a tourné en VM avant sa migration sur
l'Optiplex, donc le stockage, les ressources et la procédure d'import d'image sont
connus.

B reste le second choix et devient bon **si et seulement si** le NAS est désengorgé :
le DNS est latence-sensible, et sur une machine à 0 % d'idle une résolution de 2 ms
peut en prendre 200, ce qui se manifeste comme une lenteur générale d'Internet
attribuée à tort à la box.

C est rejetée pour le point de défaillance, et parce que la parade évidente n'en est
pas une : déclarer deux serveurs DNS dans le DHCP ne fait pas un basculement propre,
les clients alternent, et le split-horizon deviendrait intermittent. **La redondance
casse la fonction qu'on cherche.**

AdGuard Home a été écarté non pour des raisons techniques mais de justification : il
ne fait rien de plus que `dnsmasq` pour le split-horizon. Il se justifie par le
filtrage réseau (seul moyen pratique de bloquer la publicité dans les applications
iOS) et par sa visibilité des requêtes. Si ce besoin apparaît, il remplacera `dnsmasq`
dans la même VM sans rien changer au reste du design.

### D3 — Le rôle est renommé et piloté par des données

`immich_proxy` devient `caddy_proxy`. Son nom devient faux dès qu'il sert Home
Assistant ou DSM, et un rôle mal nommé se paie à chaque relecture. La liste
`caddy_vhosts` remplace le template figé : ajouter un service coûte une entrée de
données, pas une modification de template.

Le `Caddyfile.j2` existant est **conservé, commentaires compris**. Ils documentent le
403 Web Station et le « Your login is invalid » de DSM ; c'est du savoir cher, il ne
se réécrit pas.

### D4 — Certificats par ACME DNS-01 chez IONOS

| Option                                          | Verdict     |
| ----------------------------------------------- | ----------- |
| A. ACME DNS-01 via l'API IONOS                  | **retenue** |
| B. Garder le wildcard KeePass recopié à la main | rejetée     |
| C. ACME HTTP-01 ou TLS-ALPN                     | impossible  |

C est **structurellement impossible** ici, et c'est ce qui rend A évidente plutôt que
préférable : nginx/DSM occupe 80 et 443 sur le NAS, et la Freebox traduit vers `8443`.
Un challenge HTTP-01 ou TLS-ALPN frapperait donc des ports qui n'appartiennent pas à
Caddy. DNS-01 ne demande aucun port entrant.

Effet secondaire recherché : le rôle `headscale` cesse d'être couplé au renouvellement
du wildcard. Il continue de l'utiliser, mais on ne doit plus relancer les deux rôles
ensemble.

### D5 — Plugin `caddy-dns/ionos` par binaire pré-construit

Le plugin n'est ni dans `caddy:2-alpine` ni dans le paquet standard. Le binaire est
récupéré depuis l'API de build officielle
(`caddyserver.com/api/download?os=linux&arch=amd64&p=github.com/caddy-dns/ionos`),
**version et somme de contrôle épinglées dans les defaults du rôle**, puis monté en
volume par-dessus `/usr/bin/caddy` dans l'image officielle.

Aucune toolchain Go, aucune image à maintenir, et surtout **aucune compilation sur le
Celeron** : construire du Go sur une machine à 0 % d'idle et 121 Mo de RAM libre
finirait en OOM ou en une éternité. La contrepartie assumée est une dépendance au
service de build de Caddy au moment du provisionnement ; une montée de version devient
un changement de somme de contrôle explicite, ce qui est préférable à une image
silencieusement mouvante.

## §1 — Architecture : un nom, un certificat, trois chemins

Le nom public ne change jamais. Seule la réponse DNS diffère selon l'origine.

| D'où     | Résolveur                       | Réponse       | Chemin emprunté              |
| -------- | ------------------------------- | ------------- | ---------------------------- |
| Domicile | `dnsmasq` (VM Freebox)          | `192.168.1.7` | direct sur le LAN            |
| Tailnet  | Headscale (`dns.extra_records`) | `100.64.0.6`  | chiffré, hors LAN            |
| Internet | IONOS                           | `82.67.69.38` | Freebox `443` → Caddy `8443` |

C'est la propriété centrale du design : **un seul certificat reste valide partout et
une seule URL est configurée dans les applications.** Des noms en `.local` ou des
adresses IP briseraient l'un ou l'autre.

Le tableau vaut pour tous les vhosts publics. Les vhosts privés (§3) n'ont pas
d'enregistrement IONOS : ils ne sont résolvables que par `dnsmasq` et par Headscale,
ce qui les rend invisibles depuis Internet **en plus** du filtrage `remote_ip`.

## §2 — La VM DNS sur la Freebox et le rôle `dnsmasq`

Image **cloud Debian `arm64`** officielle en qcow2. L'architecture est une contrainte
dure : les VM de la Freebox Ultra sont ARM64, toute image x86_64 est inutilisable.
Le cloud-init de Freebox OS injecte le hostname et la clé publique du contrôleur ;
l'IP est fixée par bail statique ou choisie au-delà de `.200`, la plage DHCP allant de
`192.168.1.2` à `192.168.1.200`. Le démarrage automatique de la VM doit être activé :
c'est lui qui décide si une mise à jour nocturne de la box rend le DNS ou laisse la
maison sans résolution au réveil.

Aucune image sur mesure n'est fabriquée. Un qcow2 pré-cuit serait un artefact binaire
non versionnable, à refaire à chaque mise à jour de sécurité, et il dupliquerait ce
qu'Ansible fait mieux. Le seul geste manuel est la création de la VM dans Freebox OS —
documenté en runbook, comme le partitionnement swap de l'Optiplex. L'API Freebox
expose bien des endpoints VM, mais pour une VM unique le token d'application et le code
à écrire ne le valent pas.

Deux pièges que la configuration doit éviter explicitement.

**Ne jamais écrire `address=/eonelia.fr/192.168.1.7`.** Ce joker capture _tous_ les
sous-domaines du domaine, y compris ceux qui pointent légitimement ailleurs — le nom
utilisé par le rôle `headscale` en ferait les frais, et la panne serait silencieuse.
Les noms sont listés un par un, dérivés de la **même** liste que les vhosts Caddy pour
qu'ils ne puissent pas diverger.

**La VM ne doit pas se déclarer elle-même comme résolveur.** Son `/etc/resolv.conf`
vise `192.168.1.254`. Dans le cas contraire, `apt` se bloque au premier démarrage,
avant que `dnsmasq` ne soit lancé — et le rôle qui devait l'installer ne peut plus rien
télécharger.

Activation côté Freebox : `Serveur DNS 1` = l'IP de la VM, **et les quatre autres
champs laissés vides**. Un second serveur ferait alterner les clients et rendrait la
résolution locale intermittente.

Limite assumée : un client avec un DNS privé (DoH iOS) ou Tailscale actif contourne le
split-horizon. Ce n'est pas une panne — il empruntera le chemin WAN, qui fonctionne.

## §3 — Le rôle `caddy_proxy`

Les vhosts deviennent des données :

```yaml
caddy_vhosts:
  - name: photos.eonelia.fr
    backend: 192.168.1.112:2283
  - name: nas.eonelia.fr
    backend: 192.168.1.7:443
    upstream_tls: true
    header_up_host: true
  - name: ha.eonelia.fr
    backend: 192.168.1.6:8123
    allow_networks: [100.64.0.0/10, 192.168.1.0/24]
```

`upstream_tls` et `header_up_host` existent pour DSM et sont **indissociables** : sans
`header_up Host`, nginx ne trouve aucun `server_name` correspondant et retombe sur son
`default_server` — Web Station, qui répond 403. Le SNI est forcé plutôt que la
vérification désactivée. Ces contraintes sont déjà documentées dans le template actuel.

`allow_networks` produit un matcher `remote_ip` : Caddy écoute pour tout le monde mais
ne répond qu'aux origines déclarées. C'est ce qui apporte le bénéfice absent
aujourd'hui — **un certificat valide pour Home Assistant, DSM et Proxmox sans ouvrir
un seul port**, donc la fin des avertissements de sécurité sur ces interfaces.

## §4 — Certificats

Bloc **global** `acme_dns ionos {env.IONOS_API_TOKEN}`, et non par site : cela garantit
que DNS-01 soit le seul challenge tenté, là où un réglage par site laisserait Caddy
essayer HTTP-01 sur un port qu'il ne détient pas. Le token (format `prefix.secret`,
créé dans l'espace développeur IONOS) est stocké dans KeePass, résolu par
`viczem.keepass` et écrit dans `/etc/caddy/ionos.env` en `0600` — jamais dans le
`Caddyfile`.

**Le premier essai se fait contre le staging Let's Encrypt**
(`acme_ca https://acme-staging-v02.api.letsencrypt.org/directory`). Ce n'est pas une
précaution de confort : l'en-tête HSTS `max-age=31536000; includeSubDomains` est déjà
servi aux navigateurs, donc aucun repli en HTTP n'est possible si le certificat émis
est invalide. Le staging valide le token IONOS et toute la chaîne sans consommer les
quotas de production.

## §5 — Fermeture des ports

| WAN           | Sort                                   | Justification                                                                       |
| ------------- | -------------------------------------- | ----------------------------------------------------------------------------------- |
| `2283`        | **désactivé**                          | Immich en HTTP clair, ouvert à toutes les IP, doublon de `photos.eonelia.fr` en TLS |
| `4343 → 5001` | **désactivé**                          | doublon de `nas.eonelia.fr`                                                         |
| `6690`        | désactivé si Drive n'est plus utilisé  | sinon vhost `drive.eonelia.fr`, à valider avec le client                            |
| `7258`        | **désactivé**, remplacé par le tailnet | SFTP est du SSH, hors de portée d'un proxy HTTP                                     |
| `3434`        | désactivable                           | déjà restreint par IP, et le NAS est joignable par le tailnet (`100.64.0.6`)        |
| `5566`        | conservé                               | DSM Replication, restreint par IP, troisième site                                   |
| `443 → 8443`  | conservé                               | la porte d'entrée                                                                   |

**Méthode : désactiver par le toggle Freebox, ne pas supprimer, et attendre 48 h.**
Un instantané à zéro connexion ne prouve pas l'absence d'usage intermittent : une
application mobile ou un script nocturne se connectent par rafales. Le rollback est
alors un clic. Avant de toucher `2283`, vérifier sur quoi pointent réellement les
applications iOS : une configuration en `http://82.67.69.38:2283` couperait les
sauvegardes photo.

## §6 — Ordre d'exécution

L'ordre est contraint, chaque étape étant indépendamment réversible.

1. **Bascule Immich** (`c297bb3`) — répare le `502` en cours. Rien ne passe devant.
2. **Désengorger le NAS**, puis mesurer le load. Prérequis de l'étape 3 et condition
   de bascule vers l'option B de D2 si la VM Freebox se révélait insuffisante.
3. **VM DNS + rôle `dnsmasq`**, testés en pointant un seul poste vers le résolveur
   avant de le distribuer par DHCP à toute la maison.
4. **Renommage du rôle et vhosts privés** (Home Assistant, DSM, Proxmox).
5. **ACME DNS-01**, staging puis production.
6. **Fermeture des ports**, 48 h d'observation entre désactivation et suppression.

## §7 — Vérification

- `caddy validate` avant tout rechargement : le rôle doit refuser de déployer un
  `Caddyfile` invalide plutôt que de casser la porte d'entrée.
- Chaîne de certificats par `openssl s_client -servername`, pour vérifier qu'on sert
  bien Let's Encrypt et non le certificat interne que Caddy génère quand l'émission
  échoue.
- Résolution depuis les trois horizons : `dig` depuis un poste du LAN (doit rendre
  `192.168.1.7`), depuis le tailnet, et depuis l'extérieur.
- **Un vrai login DSM** sur `nas.eonelia.fr`, pas un simple code 200 : c'est
  exactement ce que le piège historique laissait passer.
- Un **upload vidéo depuis un téléphone** : le cas qui révèle les proxies mal réglés.
- Les vhosts privés doivent être **injoignables depuis Internet** et joignables depuis
  le LAN et le tailnet.

## Annexe — faits mesurés le 2026-08-17

Ces valeurs datent d'une session unique et doivent être re-mesurées avant décision.

| Mesure                                | Valeur                                                               |
| ------------------------------------- | -------------------------------------------------------------------- |
| CPU du NAS                            | Intel Celeron N3160 @ 1,60 GHz, 4 cœurs                              |
| Load average du NAS                   | 21 → 57 → 38, `0.0 id`                                               |
| RAM libre du NAS                      | 121 à 487 Mo, 2,0 à 2,7 Go de swap consommé                          |
| Poste CPU dominant                    | `synoelasticd` (SynoFinder), 77 % CPU, 195 min cumulées              |
| Ancienne instance Immich              | ne répond plus, `photos.eonelia.fr` → `502`                          |
| Instance en service                   | VM 101 de l'Optiplex, `192.168.1.112:2283`, `v3.1.0`                 |
| Résolution LAN de `photos.eonelia.fr` | `82.67.69.38` (aucun split-horizon)                                  |
| Hairpin Freebox                       | fonctionnel, TLS en 0,22 s                                           |
| Plage DHCP                            | `192.168.1.2` → `192.168.1.200`, assignation fixe par machine active |
| DNS distribué                         | `192.168.1.254` seul, quatre champs libres                           |
| Marge RAM de l'Optiplex               | ~1,4 Go après réduction de Home Assistant à 2 Go                     |

# Reverse-proxy Caddy universel, certificats autonomes et split-horizon DNS

**Date** : 2026-08-17
**Statut** : design validé, prêt pour plan d'implémentation
**Périmètre** : le reverse-proxy de la maison, ses certificats, la résolution DNS
locale, la réduction des ports exposés. Ni migration applicative, ni changement
d'hébergement des services proxifiés.

> **Échéance dure : le certificat wildcard en service expire le 25 août 2026.**
> Avec `Strict-Transport-Security: max-age=31536000`, les navigateurs et les apps
> Immich refuseront `photos.eonelia.fr` et `nas.eonelia.fr` **sans contournement
> possible**. Tout ce document est ordonné par cette contrainte.

## Contexte

Le NAS Synology porte un reverse-proxy Caddy déployé par le rôle `immich_proxy`. Il
écoute sur `8443`, la Freebox traduisant `WAN:443 → NAS:8443` puisque nginx/DSM occupe
déjà 80 et 443. Le certificat est un wildcard `*.eonelia.fr` recopié à la main depuis
KeePass et partagé avec le rôle `headscale`.

Cinq faits mesurés le 2026-08-17 fixent le contenu et l'ordre de ce chantier.

**Le certificat dure 45 jours, pas un an.** `CN=*.eonelia.fr`, Sectigo DV, valide du
11 juillet au 25 août 2026. Le renouvellement manuel supposé annuel est en réalité une
manipulation toutes les six semaines : télécharger le certificat, le remettre dans
KeePass, relancer deux rôles. Son oubli casse l'accès sans recours, HSTS oblige.

**L'API DNS d'IONOS est fermée à ce contrat.** Le portail développeur affiche « API
Programme is not yet active », et le lien d'inscription répond « This article is not
available for your contract ». Le challenge DNS-01 est donc hors d'atteinte.

**La zone `eonelia.fr` porte le courrier** : `mx00`/`mx01.ionos.fr`, SPF
`include:_spf-eu.ionos.com`, DMARC délégué à `dmarc.ionos.fr`, `autodiscover` vers
`adsredir.ionos.info`. Déplacer la zone pour obtenir une API DNS met donc en jeu la
réception du courrier, avec des erreurs silencieuses.

**Le proxy servait la mauvaise instance Immich, et elle est morte en cours de session.**
Corrigé depuis (commit `c297bb3`) : `photos.eonelia.fr` sert désormais la VM 101 de
l'Optiplex (`192.168.1.112:2283`), vérifié `200`, certificat valide, DSM sans régression.
Le piège à retenir : les deux instances répondaient `v3.1.0`, seul le `Caddyfile`
déployé permettait de trancher.

**Le NAS est saturé et Caddy n'y est pour rien.** Celeron N3160, 0 % d'idle, load entre
21 et 57, 121 à 487 Mo de RAM libre, 2 à 2,7 Go de swap. Le poste dominant est
`synoelasticd` (SynoFinder) avec 195 minutes de CPU cumulées. Caddy pèse quelques
dizaines de mégaoctets. L'hypothèse « éteindre l'ancien Immich rendra son CPU au NAS »
a été **infirmée** : l'instance est morte et le load est monté de 21 à 57.

Enfin, **il n'existe aucun split-horizon DNS** : depuis le LAN, `photos.eonelia.fr`
résout vers `82.67.69.38`. Le hairpin de la Freebox fonctionne (TLS en 0,22 s), mais
chaque octet envoyé depuis la maison traverse deux fois son NAT.

## Objectif

Un reverse-proxy unique et paramétrable, dont **les certificats se renouvellent seuls**,
qui emprunte le chemin réseau optimal selon l'endroit d'où l'on vient, et qui laisse le
minimum de ports ouverts sur Internet.

## Périmètre

**Inclus**

- CT Caddy dédié sur l'Optiplex, rôle `proxmox_caddy_lxc`, rattaché au tailnet
- Vhosts pilotés par des données, avec distinction public / privé filtré par `remote_ip`
- Certificats ACME **HTTP-01**, automatiques, en remplacement du wildcard manuel
- Split-horizon DNS par `dnsmasq` dans une VM sur la Freebox Ultra
- Enregistrements du tailnet côté Headscale
- Fermeture des redirections de ports devenues inutiles
- Cibles Makefile, documentation, procédure de vérification et de rollback

**Exclu — décidé explicitement**

- **La migration des bots (`vinted-bot`, `pokemon-monitor`) et du CT `claude-code`.**
  Mesures à l'appui : le CT `claude-code` pèse plusieurs gigaoctets (8,6 Go de `used`
  sur les 16 Go du Wyse, dont ~3,4 Go pour les huit premiers processus) quand l'Optiplex
  n'a que ~1,4 Go de marge. Ce n'est pas un arbitrage, la place n'existe pas.
- **Le désengorgement du NAS** (`synoelasticd`, Chromium des bots, restes de l'ancien
  Immich). Prérequis mesurable de l'option de repli de D2, traité en exploitation.
- **Le remplacement de SFTP par WebDAV.** Caddy ne proxifie pas SSH ; le tailnet couvre
  le besoin. Un vhost WebDAV s'ajouterait sans changer la structure.
- **Le sort du wildcard pour `headscale`.** Voir « Point ouvert » en fin de document.

## Décisions structurantes

### D1 — Caddy déménage sur un CT de l'Optiplex

| Option                                                 | Verdict     |
| ------------------------------------------------------ | ----------- |
| A. CT Caddy dédié sur l'Optiplex (`proxmox_caddy_lxc`) | **retenue** |
| B. Caddy reste sur le NAS, rôle généralisé             | rejetée     |

**Cette décision a été prise, renversée, puis reprise dans la même session. Le
raisonnement est conservé en entier, parce qu'il explique pourquoi le déménagement se
justifie aujourd'hui par une raison qui n'était pas la bonne au départ.**

A avait d'abord été retenue pour de mauvaises raisons — résilience et décharge CPU — qui
ne survivent pas à la mesure. **La résilience n'en est pas une** : les originaux
d'Immich vivent sur le NAS en NFS, donc si le NAS tombe, Immich tombe où que soit le
proxy. **La décharge CPU n'en est pas une non plus** : Caddy ne pèse rien face à
`synoelasticd`. A fut donc rejetée au profit de B, ne laissant au déménagement qu'un
argument d'hygiène jugé insuffisant — la fin du `8443`, de `auto_https disable_redirects`
et du certificat manuel.

**Deux faits découverts ensuite ont inversé le verdict** : l'API DNS d'IONOS est fermée
à ce contrat, et le certificat ne dure que 45 jours. Le renouvellement automatique
devient donc une nécessité, et le seul challenge ACME praticable sans toucher à la zone
qui porte le courrier est HTTP-01 — qui exige un port 80 libre, ce que seul un CT dédié
offre.

Le coût de A se compare désormais à une corvée toutes les six semaines assortie d'un
risque de panne, et non à un confort : un CT (~80 Mo réels, un LXC ne préalloue rien),
un rôle, une bascule de la porte d'entrée sous HSTS. L'arbitrage change de sens.

**Correction du 2026-08-18 : l'urgence des « 45 jours » ne tenait pas.** Le renouvellement
effectué ce jour-là a produit un certificat valable du 17 août 2026 au 22 février 2027,
soit environ 189 jours — pas six semaines. L'échantillon du 11 juillet au 25 août 2026
était vraisemblablement un remplacement qui héritait de la fin du cycle précédent ; une
durée nominale avait été extrapolée à tort depuis ce seul échantillon (voir l'annexe des
faits mesurés). L'urgence invoquée ci-dessus pour renverser le verdict n'était donc pas
fondée : il n'y avait pas de corvée toutes les six semaines qui s'annonçait.

Le déménagement reste néanmoins la bonne décision, mais pour ses autres motifs, restés
vrais indépendamment de la durée réelle du certificat : un renouvellement entièrement
automatique plutôt que semestriel (~189 jours) et manuel, la fin du port `8443` et de
`auto_https disable_redirects`, et la fin d'un certificat partagé entre deux rôles
(`caddy_proxy` et `headscale`) — un partage qui couple leurs pannes sans raison
technique. Le raisonnement des paragraphes précédents est conservé tel qu'écrit sur le
moment ; ce correctif ne le supprime pas, il le complète, dans le même esprit que le
retournement A→B→A documenté plus haut.

### D2 — Le résolveur local va dans une VM sur la Freebox Ultra

| Option                                                | Verdict            |
| ----------------------------------------------------- | ------------------ |
| A. `dnsmasq` en VM sur la Freebox Ultra               | **retenue**        |
| B. `dnsmasq` en second service du compose du proxy    | repli, conditionné |
| C. LXC dédié sur l'Optiplex (AdGuard Home ou dnsmasq) | rejetée            |
| D. Enregistrements DNS locaux dans la Freebox         | impossible         |
| E. Ne rien faire, garder le hairpin                   | repli acceptable   |

D a été éliminée sur constat : l'écran _Réseau local / DHCP_ ne fait que **distribuer**
des serveurs DNS (cinq champs), il ne crée aucun enregistrement. Les baux statiques ne
produisent que des noms en `.home`.

A est retenue pour une raison qui la distingue de toutes les autres : **la Freebox est
déjà le point unique dont la panne coupe Internet et le DHCP.** Y placer le DNS n'ajoute
aucun point de défaillance, là où B et C en créent un — C sur une machine qui a démontré
le 2026-08-17 qu'elle peut disparaître du réseau trente minutes (bug e1000e, corrigé
depuis par `nic-offload` et `nic-link-watchdog`). La faisabilité est acquise : Home
Assistant a tourné en VM sur cette box avant sa migration, donc stockage, ressources et
procédure d'import d'image qcow2 sont connus.

B ne devient bon **que si le NAS est désengorgé** : le DNS est latence-sensible, et sur
une machine à 0 % d'idle une résolution de 2 ms peut en prendre 200, ce qui se manifeste
comme une lenteur générale attribuée à tort à la box.

C est rejetée aussi parce que sa parade évidente n'en est pas une : déclarer deux
serveurs DNS dans le DHCP ne fait pas un basculement propre, les clients alternent, et
le split-horizon devient intermittent. **La redondance casse la fonction qu'on cherche.**

AdGuard Home est écarté non pour des raisons techniques mais de justification : il
n'apporte rien de plus que `dnsmasq` pour le split-horizon. Il se justifie par le
filtrage réseau — seul moyen pratique de bloquer la publicité dans les applications iOS
— et par sa visibilité des requêtes. Si ce besoin apparaît, il remplacera `dnsmasq` dans
la même VM sans rien changer au reste du design.

### D3 — Le rôle est renommé et piloté par des données

`immich_proxy` devient `caddy_proxy`, dont le CT est provisionné par
`proxmox_caddy_lxc` sur le modèle de `proxmox_headscale_lxc` (création `pct`
idempotente, sans token API, clé du contrôleur injectée). Le nom `immich_proxy` devient
faux dès qu'il sert Home Assistant ou DSM, et un rôle mal nommé se paie à chaque
relecture. La liste `caddy_vhosts` remplace le template figé : ajouter un service coûte
une entrée de données.

Le `Caddyfile.j2` existant est **conservé, commentaires compris**. Ils documentent le
403 Web Station et le « Your login is invalid » de DSM ; c'est du savoir cher, il ne se
réécrit pas.

### D4 — Certificats par ACME HTTP-01, depuis le CT

| Option                                          | Verdict     |
| ----------------------------------------------- | ----------- |
| A. ACME HTTP-01 depuis le CT                    | **retenue** |
| B. ACME DNS-01 via l'API IONOS                  | impossible  |
| C. Délégation du challenge par CNAME (acme-dns) | repli       |
| D. Déplacer la zone vers Cloudflare ou deSEC    | rejetée     |
| E. Garder le wildcard Sectigo manuel            | rejetée     |

**B était la décision initiale et elle est simplement impossible** : « This article is
not available for your contract ». Ce n'est pas un problème de navigation dans
l'interface, c'est un droit que le contrat n'ouvre pas. Tout le montage
`caddy-dns/ionos` tombe avec elle, y compris la décision qui portait sur son plugin.

A n'est possible **que grâce à D1** : sur le CT, aucun autre service ne détient 80 ni
443, alors que sur le NAS nginx/DSM les occupe tous les deux. Il faut donc ajouter une
redirection `WAN:80 → CT:80` à côté du 443. Ce n'est pas une régression notable : sur le
80, Caddy ne sert que la redirection vers HTTPS et les challenges ACME.

D est rejetée pour risque disproportionné : recréer MX, SPF, DMARC, `autodiscover` et un
éventuel DKIM ailleurs met en jeu la réception du courrier, et l'erreur y est
silencieuse. C reste le repli si A se révélait impraticable — elle n'ajoute que des CNAME
`_acme-challenge` statiques dans la zone existante, sans toucher au courrier, au prix
d'une dépendance à un service de délégation tiers.

E est rejetée par la mesure des 45 jours : le renouvellement supposé annuel revient en
réalité toutes les six semaines, et son oubli est sans recours sous HSTS.

**Conséquence sur les vhosts privés :** HTTP-01 exige que chaque nom soit résolvable
publiquement et joignable sur le 80. Les noms internes (`ha`, `dsm`, `pve`) auront donc
des enregistrements A publics, leur confidentialité reposant sur le seul matcher
`remote_ip`. Ce n'est pas une perte : les certificats Let's Encrypt étant publiés dans
les journaux Certificate Transparency, ces noms seraient publics même avec DNS-01. Le
service, lui, reste fermé.

## §1 — Architecture : un nom, un certificat, trois chemins

Le nom public ne change jamais. Seule la réponse DNS diffère selon l'origine.

| D'où     | Résolveur                       | Réponse          | Chemin emprunté         |
| -------- | ------------------------------- | ---------------- | ----------------------- |
| Domicile | `dnsmasq` (VM Freebox)          | `192.168.1.210`  | direct sur le LAN       |
| Tailnet  | Headscale (`dns.extra_records`) | IP tailnet du CT | chiffré, hors LAN       |
| Internet | IONOS                           | `82.67.69.38`    | Freebox `80`/`443` → CT |

C'est la propriété centrale du design : **un seul certificat reste valide partout et une
seule URL est configurée dans les applications.** Des noms en `.local` ou des adresses IP
briseraient l'un ou l'autre.

L'horizon tailnet impose que **le CT rejoigne le tailnet** (rôle `tailscale_client`).
À noter que l'Optiplex lui-même n'y est pas : `tailscale status` ne montre aucun nœud le
concernant, malgré le commit `a5625d4`. À traiter dans le même mouvement.

## §2 — La VM DNS sur la Freebox et le rôle `dnsmasq`

Image **cloud Debian `arm64`** officielle en qcow2. L'architecture est une contrainte
dure : les VM de la Freebox Ultra sont ARM64, toute image x86_64 est inutilisable. Le
cloud-init de Freebox OS injecte le hostname et la clé publique du contrôleur ; l'IP est
fixée par bail statique ou choisie **au-delà de `.200`**, la plage DHCP allant de
`192.168.1.2` à `192.168.1.200`. Le démarrage automatique de la VM doit être activé :
c'est lui qui décide si une mise à jour nocturne de la box rend le DNS ou laisse la
maison sans résolution au réveil.

Aucune image sur mesure n'est fabriquée. Un qcow2 pré-cuit serait un artefact binaire
non versionnable, à refaire à chaque mise à jour de sécurité, et il dupliquerait ce
qu'Ansible fait mieux. Le seul geste manuel est la création de la VM dans Freebox OS,
documentée en runbook comme le partitionnement swap de l'Optiplex. L'API Freebox expose
des endpoints VM, mais pour une VM unique le token d'application et le code ne le valent
pas.

Deux pièges que la configuration doit éviter explicitement.

**Ne jamais écrire `address=/eonelia.fr/192.168.1.210`.** Ce joker capture _tous_ les
sous-domaines, y compris ceux qui pointent légitimement ailleurs — le nom utilisé par le
rôle `headscale` en ferait les frais, et la panne serait silencieuse. Les noms sont
listés un par un, dérivés de la **même** liste que les vhosts Caddy pour qu'ils ne
puissent pas diverger.

**La VM ne doit pas se déclarer elle-même comme résolveur.** Son `/etc/resolv.conf` vise
`192.168.1.254`, sinon `apt` se bloque au premier démarrage, avant que `dnsmasq` ne soit
lancé — et le rôle qui devait l'installer ne peut plus rien télécharger.

Activation côté Freebox : `Serveur DNS 1` = l'IP de la VM, **et les quatre autres champs
laissés vides**. Un second serveur ferait alterner les clients et rendrait la résolution
locale intermittente.

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
  - name: ha.eonelia.fr
    backend: 192.168.1.6:8123
    allow_networks: [100.64.0.0/10, 192.168.1.0/24]
```

`upstream_tls` est le seul levier ; il n'existe pas de `header_up_host` distinct. Le
template (`Caddyfile.j2`) émet `header_up Host {{ vhost.name }}` automatiquement dès que
`upstream_tls` est vrai — c'est délibéré, et c'est mieux qu'une seconde clé : il devient
impossible d'activer l'un sans l'autre. Sans ce `header_up Host`, nginx ne trouve aucun
`server_name` correspondant et retombe sur son `default_server` — Web Station, qui répond 403. Le SNI est forcé plutôt que la vérification désactivée.

`allow_networks` produit un matcher `remote_ip` : Caddy écoute pour tout le monde mais ne
répond qu'aux origines déclarées. C'est ce qui apporte le bénéfice absent aujourd'hui —
**un certificat valide pour Home Assistant, DSM et Proxmox sans ouvrir un seul port de
service** — donc la fin des avertissements de sécurité sur ces interfaces.

Le CT écoutant directement sur 443, le port `8443` et la directive
`auto_https disable_redirects` disparaissent : Caddy reprend son comportement nominal,
redirection HTTP→HTTPS incluse.

## §4 — Émission et renouvellement des certificats

Un certificat Let's Encrypt par nom, émis et renouvelé automatiquement par Caddy via
HTTP-01. Aucun secret à stocker, aucun plugin à compiler, aucune dépendance à une API de
registrar : c'est le mode de fonctionnement par défaut de Caddy, retrouvé grâce à D1.

**Le premier essai se fait contre le staging Let's Encrypt**
(`acme_ca https://acme-staging-v02.api.letsencrypt.org/directory`). Ce n'est pas une
précaution de confort : l'en-tête HSTS `max-age=31536000; includeSubDomains` est déjà
servi aux navigateurs, donc aucun repli en HTTP n'est possible si l'émission échoue. Le
staging valide toute la chaîne — redirection Freebox du 80, résolution publique des noms,
accessibilité du challenge — sans consommer les quotas de production.

Une fois la production validée, les journaux du CT et une lecture directe des `.crt` du
répertoire de données de Caddy (`openssl x509 -noout -issuer -dates`, la commande
`caddy list-certificates` n'existant pas dans la version déployée) donnent les
échéances. Le renouvellement intervient à 30 jours de la fin, sans intervention.

## §5 — Ports : ce qui s'ouvre et ce qui se ferme

| WAN             | Sort                                   | Justification                                                                |
| --------------- | -------------------------------------- | ---------------------------------------------------------------------------- |
| `80` → CT       | **à ouvrir**                           | requis par HTTP-01 ; n'expose que la redirection HTTPS et les challenges     |
| `443` → CT      | **à rebasculer** (depuis `NAS:8443`)   | la porte d'entrée déménage                                                   |
| `443` → `8443`  | désactivée, conservée                  | rollback en un clic pendant toute la période d'observation                   |
| `2283`          | **désactivé**                          | Immich en HTTP clair, ouvert à toutes les IP, doublon de `photos.eonelia.fr` |
| `4343` → `5001` | **désactivé**                          | doublon de `nas.eonelia.fr`                                                  |
| `6690`          | désactivé si Drive n'est plus utilisé  | sinon vhost `drive.eonelia.fr`, à valider avec le client                     |
| `7258`          | **désactivé**, remplacé par le tailnet | SFTP est du SSH, hors de portée d'un proxy HTTP                              |
| `3434`          | désactivable                           | déjà restreint par IP, et le NAS est joignable par le tailnet                |
| `5566`          | conservé                               | DSM Replication, restreint par IP, troisième site                            |

**Méthode : désactiver par le toggle Freebox, ne pas supprimer, et attendre 48 h.** Un
instantané à zéro connexion ne prouve pas l'absence d'usage intermittent — une
application mobile ou un script nocturne se connectent par rafales. Avant de toucher
`2283`, vérifier sur quoi pointent réellement les applications iOS : une configuration
en `http://82.67.69.38:2283` couperait les sauvegardes photo.

## §6 — Ordre d'exécution

L'ordre est commandé par l'échéance du 25 août.

1. **Sécuriser l'échéance, immédiatement.** Vérifier dans l'espace IONOS si le wildcard
   est en renouvellement automatique. Si oui, récupérer les nouveaux fichiers, les
   remettre dans KeePass et relancer `immich_proxy` et `headscale`. Cela achète six
   semaines et rend le reste du chantier serein. **À faire même si l'étape 2 avance
   bien** : c'est le filet.
2. **CT Caddy + rôle, certificats en staging puis production**, testés par
   `curl --resolve` avant toute bascule Freebox. Cible : avant le 25 août.
3. **Bascule Freebox** — ouverture du 80, `443` vers le CT, ancienne règle désactivée
   mais conservée. Vérification depuis un réseau mobile, pas depuis le LAN, où le
   hairpin peut masquer une règle fausse.
4. **Rattachement du CT au tailnet** et enregistrements Headscale.
5. **VM DNS + `dnsmasq`**, testés sur un seul poste avant distribution par DHCP.
6. **Vhosts privés** (Home Assistant, DSM, Proxmox).
7. **Fermeture des ports**, 48 h d'observation entre désactivation et suppression.
8. **Retrait du Caddy du NAS** et du rôle `immich_proxy`, après une période de rollback.

## §7 — Vérification

- `caddy validate` avant tout rechargement : le rôle doit refuser de déployer un
  `Caddyfile` invalide plutôt que de casser la porte d'entrée.
- Chaîne de certificats par `openssl s_client -servername`, pour confirmer qu'on sert
  Let's Encrypt et non le certificat interne que Caddy génère quand l'émission échoue.
- Résolution depuis les trois horizons : `dig` depuis le LAN (doit rendre
  `192.168.1.210`), depuis le tailnet, depuis l'extérieur.
- **Un vrai login DSM** sur `nas.eonelia.fr`, pas un simple code 200 : c'est exactement
  ce que le piège historique laissait passer.
- Un **upload vidéo depuis un téléphone** : le cas qui révèle les proxies mal réglés.
- Les vhosts privés doivent être **injoignables depuis Internet** et joignables depuis
  le LAN et le tailnet.
- Après bascule, vérifier qu'un renouvellement automatique a bien lieu avant de
  démonter le Caddy du NAS.

## Point ouvert — `headscale` et l'échéance du 25 août

Le déménagement de Caddy **ne supprime pas la corvée pour `headscale`**, et ce service
est concerné par la même échéance. Faits établis :

- `headscale_server_url: https://mom.eonelia.fr:34443`, et `mom.eonelia.fr` résout vers
  `88.172.204.162` — l'IP publique de chez la mère d'Aurélien, où vit le Wyse. Vérifié
  joignable, `200`, TLS valide, servi par **le même wildcard Sectigo**.
- `headscale_base_domain: ts.eonelia.fr` (suffixe MagicDNS, distinct par obligation).
- Le rôle dépose le wildcard depuis l'entrée KeePass `Certificate *.eonelia.fr`.

**Donc `mom.eonelia.fr` tombera aussi le 26 août**, ce qui empêcherait l'enrôlement de
nouveaux nœuds sur le tailnet. C'est un second service à couvrir par l'étape 1 de §6,
pas seulement le proxy.

Et la voie « placer `headscale` derrière ce Caddy » **est à écarter** : il est hébergé
sur un autre site, derrière une autre connexion. L'y faire passer ferait dépendre le
plan de contrôle du tailnet de la connexion domestique d'Aurélien, et créerait une
dépendance circulaire — le tailnet est précisément ce qui sert à joindre les machines.

La voie propre est un **ACME local sur le Wyse** : un petit Caddy devant `headscale`, ou
`headscale` avec son propre client ACME, avec le port 80 ouvert sur la box de la mère
pour le challenge HTTP-01. Cela supprimerait définitivement le wildcard partagé, et avec
lui la dernière manipulation manuelle. À instruire dans son propre cycle.

## Annexe — faits mesurés le 2026-08-17

Ces valeurs datent d'une session unique et doivent être re-mesurées avant décision.

> **Correction du 2026-08-18.** La ligne « Certificat en service » ci-dessous a été lue
> comme la durée nominale du cycle de renouvellement (« 45 jours »), extrapolée à tort
> depuis ce seul échantillon — voir la correction dans D1. Le renouvellement effectué le
> 2026-08-18 a produit un certificat valable jusqu'au **22 février 2027**, soit environ
> 189 jours depuis son émission. L'échantillon du 11 juillet au 25 août 2026 était
> vraisemblablement un remplacement héritant de la fin d'un cycle précédent, pas une
> mesure du cycle complet.

| Mesure                                 | Valeur                                                     |
| -------------------------------------- | ---------------------------------------------------------- |
| Certificat en service (mesuré le 17)   | `CN=*.eonelia.fr`, Sectigo DV, 11 juil. → **25 août 2026** |
| Certificat renouvelé le 18 (correctif) | 17 août 2026 → **22 février 2027**, soit ~189 jours        |
| API DNS IONOS                          | « not available for your contract »                        |
| Serveurs de noms de `eonelia.fr`       | `ns1054.ui-dns.com` et homologues `.de/.org/.biz` (IONOS)  |
| Courrier de la zone                    | `mx00`/`mx01.ionos.fr`, SPF IONOS, DMARC, `autodiscover`   |
| CPU du NAS                             | Intel Celeron N3160 @ 1,60 GHz, 4 cœurs                    |
| Load average du NAS                    | 21 → 57 → 38, `0.0 id`                                     |
| RAM libre du NAS                       | 121 à 487 Mo, 2,0 à 2,7 Go de swap                         |
| Poste CPU dominant du NAS              | `synoelasticd` (SynoFinder), 77 % CPU, 195 min cumulées    |
| Instance Immich en service             | VM 101 de l'Optiplex, `192.168.1.112:2283`, `v3.1.0`       |
| Résolution LAN de `photos.eonelia.fr`  | `82.67.69.38` (aucun split-horizon)                        |
| Hairpin Freebox                        | fonctionnel, TLS en 0,22 s                                 |
| Plage DHCP                             | `.2` → `.200`, assignation fixe par machine active         |
| DNS distribué                          | `192.168.1.254` seul, quatre champs libres                 |
| Marge RAM de l'Optiplex                | ~1,4 Go après réduction de Home Assistant à 2 Go           |
| Tailnet                                | 8 nœuds, **aucun Optiplex** malgré le commit `a5625d4`     |

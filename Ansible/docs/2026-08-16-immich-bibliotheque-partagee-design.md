# Reproduire une photothèque partagée iCloud dans Immich

**Note de décision — 16 août 2026.** Ce document sert à _choisir une approche_. Rien n'est
mis en œuvre tant qu'une option n'est pas retenue.

---

## 1. Le besoin

Reproduire dans Immich le comportement d'une **photothèque partagée iCloud** :

- chacun garde **sa** bibliothèque personnelle ;
- il existe un **pool commun** que tous voient et alimentent ;
- le versement est **automatique**, sur critère de **reconnaissance faciale** (l'analogue de la
  règle « participants à proximité » d'iCloud) ;
- **aucun doublon**.

Participants pressentis : Aurélien, sa compagne, sa mère. Terminaux iOS, application Immich
avec sauvegarde automatique.

### État actuel

| Élément          | Situation                                                                                                        |
| ---------------- | ---------------------------------------------------------------------------------------------------------------- |
| Serveur          | Immich sur le NAS Synology (docker-compose), série 2.5.x                                                         |
| Exposition       | Publique via Caddy, routage SNI `photos.eonelia.fr` — pas de VPN, condition du backup iOS automatique            |
| Contenu          | Déjà migré : **external library** alimentée depuis Synology Photos                                               |
| Machine learning | **Déporté sur le Mac** (port 3003 via tailnet), le CPU du NAS étant le facteur limitant — cf. `immich/README.md` |
| Cible matérielle | **Dell OptiPlex 7090 Micro**, destiné à reprendre Immich et les autres runtimes                                  |

### Deux sortes de doublons, à ne pas confondre

Elles ne se traitent pas de la même façon et départagent les approches :

- **Doublon d'affichage** — la même photo apparaît deux fois à l'écran alors qu'il n'existe
  qu'un seul fichier. C'est ce que produit le partner sharing.
- **Doublon de stockage** — le fichier est réellement écrit deux fois sur le disque parce que
  deux comptes l'ont importé chacun de son côté.

Point capital : **ajouter un asset à un album ne le duplique pas.** Un album Immich est une
vue, pas une copie. Une architecture fondée sur les albums est donc nativement exempte des
deux problèmes.

---

## 2. Ce qu'Immich sait et ne sait pas faire (vérifié)

### Ce qui est bloqué

| Constat                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Conséquence                                                                                                                                        |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| **L'Album Sync mobile par nom ne s'accroche pas à l'album d'autrui.** Si un album du téléphone porte le nom d'un album partagé appartenant à quelqu'un d'autre, l'app **crée un album en doublon** ([#28796](https://github.com/immich-app/immich/discussions/28796), fermée en doublon de la feature request #12748, non implémentée)                                                                                                                                                  | Le versement automatique ne peut pas venir du téléphone. Il doit passer par l'**API, côté serveur**.                                               |
| **Un album partagé n'apparaît jamais dans la timeline des autres membres**, seulement dans l'onglet Albums. Demande récurrente, toujours ouverte : [#1779](https://github.com/immich-app/immich/discussions/1779), [#7047](https://github.com/immich-app/immich/discussions/7047), [#10425](https://github.com/immich-app/immich/discussions/10425), [#13421](https://github.com/immich-app/immich/discussions/13421), [#26874](https://github.com/immich-app/immich/discussions/26874) | Le pool commun se consulte dans l'onglet Albums. C'est l'écart le plus visible avec iCloud.                                                        |
| **Recherche et reconnaissance faciale restent inopérantes sur les photos des autres membres** d'un album partagé, y compris en v2.7.5 ([#28544](https://github.com/immich-app/immich/issues/28544))                                                                                                                                                                                                                                                                                     | On ne cherche pas « maman » dans les photos versées par les autres.                                                                                |
| **Le partage est gelé côté projet.** [#12614 « Better sharing in Immich (feature freeze) »](https://github.com/immich-app/immich/issues/12614), ouverte depuis septembre 2024 : toute évolution du partage attend une refonte du contrôle d'accès                                                                                                                                                                                                                                       | Inutile d'espérer un correctif à court terme ; et toute solution retenue doit rester **réversible**.                                               |
| **Les identités de visages sont propres à chaque compte.** Les données de personnes ne sont pas partagées ([partner sharing](https://docs.immich.app/features/partner-sharing/))                                                                                                                                                                                                                                                                                                        | « Maman » chez Aurélien et « maman » chez sa compagne sont deux entités sans lien. Trois référentiels à entretenir séparément.                     |
| **On ne peut pas ajouter les assets d'autrui à un album** — 403 `no_permission` ([#11333](https://github.com/immich-app/immich/issues/11333), [#15050](https://github.com/immich-app/immich/issues/15050))                                                                                                                                                                                                                                                                              | Un service centralisé unique est impossible : il faut **une clé API par personne**, chacune versant ses propres photos.                            |
| **La déduplication est mono-compte.** Deux comptes détenant le même fichier = deux assets, stockage ×2, ML ×2 ([FAQ](https://docs.immich.app/FAQ/)) ; dédup globale demandée en [#17422](https://github.com/immich-app/immich/discussions/17422)                                                                                                                                                                                                                                        | Toute approche qui **copie** les photos double le stockage, définitivement.                                                                        |
| **Une external library appartient définitivement à un seul utilisateur**, choisi à la création et non modifiable ; les **symlinks sont explicitement déconseillés** ; pas d'upload mobile ([doc](https://docs.immich.app/features/libraries))                                                                                                                                                                                                                                           | La piste « symlinks + cron » est **écartée** : ce n'est pas un problème de robustesse qu'on comble avec des scripts, c'est structurellement fermé. |

### Ce qui est disponible

| Brique                                                                                                                                                            | Ce qu'elle apporte                                                                                                                                                                                                  |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Albums partagés**, rôles Owner / Editor / Viewer                                                                                                                | Un espace commun où chaque membre contribue ses propres photos ([doc](https://docs.immich.app/features/sharing/))                                                                                                   |
| **Partner sharing** avec option **« Show in timeline »** par partenaire                                                                                           | Le seul mécanisme existant pour faire apparaître les photos d'un autre **dans sa propre timeline**. Unidirectionnel, bibliothèque entière, lecture seule ([doc](https://docs.immich.app/features/partner-sharing/)) |
| **API** : `POST /api/search/metadata` accepte `personIds` ; `PUT /api/albums/{id}/assets` ajoute au pool ; clés API à **permissions granulaires** depuis la 1.135 | Une règle « tel visage → tel album » est réalisable proprement                                                                                                                                                      |
| [**`immich-face-to-album`**](https://github.com/romainrbr/immich-face-to-album)                                                                                   | Outil tiers qui fait déjà exactement cela en cron incrémental : `--require-all-faces`, `--remove-non-matching`, fichier d'état                                                                                      |
| **Workflows v3.0.0** (sortie 1ᵉʳ juillet 2026, en preview) : trigger `AssetCreate` → action « ajouter à un album »                                                | Le bon squelette… **mais aucun filtre par personne** ([#29167](https://github.com/immich-app/immich/discussions/29167)). Ne remplace pas le cron pour ce besoin.                                                    |

---

## 3. Les approches

### Approche A — Album partagé « Famille » + service de règles par visage

Un album « Famille » appartenant à un **compte de service dédié** (`famille@`, quota nul, il ne
stocke rien), partagé en **Editor** avec chaque participant. Sur l'OptiPlex, un conteneur cron
exécute pour **chaque personne**, avec **sa** clé API :
`search/metadata(personIds=[…])` → `PUT /albums/{famille}/assets`, en incrémental.

Chaque compte a sa propre configuration `{clé API, identifiants de personnes locaux, règles}`,
puisque les visages ne sont pas partagés entre comptes. Les photos issues de l'external library
Synology sont éligibles comme n'importe quel autre asset.

- **Vécu utilisateur** — rien à changer : la sauvegarde iOS continue telle quelle. Onglet
  Albums → « Famille » : les photos de tous, ajout manuel possible, commentaires et favoris.
  Les photos où figurent les visages configurés y arrivent seules, sous une heure environ.
- **Automatisme** — élevé. Équivalent de la règle iCloud par participants, sans la détection
  de proximité. Latence = période du cron + délai du job de reconnaissance faciale.
- **Doublons** — **aucun**, ni stockage ni affichage.
- **Compromis** — pool absent de la timeline ; pas de recherche ni de visages sur les photos
  des autres ; suppression asymétrique (un Editor ne retire que ses propres photos,
  [#20617](https://github.com/immich-app/immich/issues/20617)).
- **Modes de panne** — changement d'identifiant de personne après fusion ou renommage d'un
  visage ; clé API révoquée ; service arrêté → simple retard, rattrapé à la reprise sans
  doublon (l'ajout d'un asset déjà présent est idempotent). Faux positifs de reconnaissance →
  photos indésirables dans le pool, retirables à la main.
- **Maintenance** — faible. Un conteneur cron, une configuration par personne, aucune
  modification d'Immich, insensible aux mises à jour.

### Approche A+ — la même, plus partner sharing dans le couple

Approche A, complétée par un partner sharing réciproque Aurélien ↔ compagne avec
« Show in timeline » : timeline fusionnée du foyer en supplément du pool.

Réserve : c'est précisément là que peuvent réapparaître des **doublons d'affichage**, si les
deux comptes ont importé les mêmes fichiers (photo AirDropée puis sauvegardée par les deux
téléphones). L'option s'active et se désactive en un clic — donc essayable sans risque.

### Approche B — Partner sharing généralisé seul

Chacun partage sa bibliothèque entière avec les deux autres. **Écartée** : lecture seule,
aucun filtrage (la mère verrait tout), pas de pool, et c'est la configuration qui produit
les doublons d'affichage reprochés au départ.

### Approche C′ — Compte « Famille » propriétaire, copie physique + archivage

Le service **copie** chaque photo correspondant à la règle (téléchargement de l'original, puis
envoi sous la clé du compte Famille), **archive** l'original chez son propriétaire, et le
compte Famille fait du partner sharing descendant vers chacun avec « Show in timeline ».

- **Gains réels** — le pool apparaît **dans la timeline de tous** (seul mécanisme existant), et
  le ML tourne de façon **cohérente** sur l'ensemble du pool sous un compte unique : recherche
  et visages fonctionnent enfin sur les photos de tous.
- **Prix** — **stockage ×2 systématique** ; bibliothèque personnelle vidée de ses photos de
  famille au profit du pool ; favoris, albums et retouches perdus sur les copies ; pool en
  **lecture seule** pour les membres (c'est du partner sharing) ; service nettement plus
  intrusif ; **long à défaire** (archivage et copies de masse à inverser).
- L'archivage plutôt que la suppression de l'original est impératif : après purge de la
  corbeille, le hash disparaît du compte et **la sauvegarde mobile réexpédie le fichier**, d'où
  un cycle sans fin envoi → copie → suppression.

C′ est plus fidèle à iCloud sur un point de principe — iCloud _déplace_ réellement les photos
vers la photothèque partagée — mais paie très cher un seul avantage : la timeline commune.

### Approche D — Attendre le natif

« User groups » et « Better sharing, especially around facial recognition data » figurent à la
[roadmap](https://immich.app/roadmap), tous deux « Soon™ », **sans date**, sous feature freeze
depuis 2024. Aucune PR fusionnée n'apporte de vraie bibliothèque partagée. Ce n'est pas une
option aujourd'hui — mais c'est un argument fort en faveur de A, qui n'engage rien et se
démonte en supprimant un cron le jour où le natif arrive.

---

## 4. Comparatif

|                                 | **A**                     | **A+**                      | **C′**                             |
| ------------------------------- | ------------------------- | --------------------------- | ---------------------------------- |
| Où vit le pool                  | Onglet Albums             | Albums + timeline du couple | **Timeline de tous**               |
| Doublons de stockage            | Aucun                     | Aucun                       | **×2 systématique**                |
| Doublons d'affichage            | Aucun                     | Possibles dans le couple    | Aucun (au prix de l'archivage)     |
| Bibliothèque personnelle        | Intacte                   | Intacte                     | Vidée de ses photos de famille     |
| Droits dans le pool             | Chacun ajoute les siennes | Idem                        | **Lecture seule** pour les membres |
| Recherche / visages sur le pool | Non                       | Non                         | **Oui**                            |
| Réversibilité                   | Totale                    | Totale                      | Longue et pénible                  |
| Charge de développement         | Outil existant en cron    | Idem                        | Service maison conséquent          |

---

## 5. Recommandation

**Approche A**, avec ces choix précis :

1. **Créer un compte de service `famille`** propriétaire de l'album. Immich n'a **pas de
   transfert de propriété d'album** : rattacher le pool à un compte personnel serait le seul
   choix réellement difficile à défaire de cette architecture.
2. **Démarrer avec `immich-face-to-album` en cron** — un service par participant — et ne
   développer un outil maison que si un besoin concret le justifie (exiger la présence
   simultanée de plusieurs visages, alimenter plusieurs albums, notifier).
3. **Essayer A+** ensuite : l'option « Show in timeline » se teste en un clic et se retire
   aussi vite si les doublons d'affichage gênent.

C′ n'est justifiable que si **la timeline commune est non négociable** — c'est la seule
question qui reste à trancher.

### À valider avant de s'engager

|        | Test                                                                                                                                                              | Enjeu                                                                                          |
| ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| **T1** | Avec la clé API d'un Editor, `PUT /albums/{id}/assets` accepte-t-il ses propres assets sur l'album du compte `famille` ? Quelles permissions granulaires cocher ? | **Bloquant** — non confirmé noir sur blanc par la documentation. Toute l'approche A en dépend. |
| **T2** | L'identifiant d'une personne survit-il à une fusion ou un renommage de visages ?                                                                                  | Détermine s'il faut resynchroniser la configuration après chaque ménage dans les visages       |
| **T3** | Latence bout en bout : sauvegarde iPhone → reconnaissance → apparition dans l'album                                                                               | Fixe la période du cron et les attentes                                                        |
| **T4** | Comportement de l'app de la mère face à l'album partagé (affichage, ajout manuel, aucune tentation de créer un album homonyme)                                    | L'ergonomie pour une utilisatrice non technique est le vrai critère de réussite                |

---

## 6. Ce que la migration vers l'OptiPlex change

- **Le machine learning revient sur la machine Immich.** Le montage actuel — inférence déportée
  sur le Mac via launchd, avec repli silencieux sur le NAS quand le Mac dort — existe parce que
  le CPU du NAS ne suit pas. Un OptiPlex 7090 Micro absorbe cette charge : le service `immichml`
  du Mac et ses deux jobs launchd deviennent inutiles. Cela **conditionne directement l'approche
  A**, entièrement suspendue à une reconnaissance faciale fiable et à jour.
- **Un hôte capable de faire tourner le service de règles**, ce que le NAS ne permettait pas
  confortablement.
- **Occasion de passer en v3.x** et d'évaluer les workflows en preview. Ils ne couvrent pas le
  filtre par visage, mais peuvent absorber d'autres automatismes.
- **L'external library Synology est à reprendre** : son propriétaire est figé, à vérifier lors
  du déménagement des données.
- **Le proxy Caddy et l'exposition publique sont à réviser** : Immich change d'adresse, le NAS
  garde DSM sur le 443 partagé. Chantier distinct de la présente note.

---

## 7. Écarts résiduels avec iCloud — qu'aucune approche ne comble

1. **Pas de timeline commune** dans l'approche recommandée : le pool vit dans l'onglet Albums.
   C'est l'écart le plus visible pour qui vient d'iCloud.
2. **Suppression asymétrique** : personne ne peut supprimer la photo d'un autre, là où iCloud
   donne un droit symétrique à tous les participants.
3. **Recherche et visages inopérants** sur les photos des autres dans le pool — gelé côté
   Immich jusqu'à la refonte du partage.
4. **Pas de règle de proximité ni de date de début**, pas de suggestions de versement : seul le
   critère « tel visage est présent » est automatisable, et il dépend de la qualité de la
   reconnaissance **de chaque compte pris séparément**.
5. **Pas de bascule perso / partagé dans l'application Appareil photo**, ni de choix au moment
   de la prise de vue.
6. **Les retouches** d'un membre ne se propagent pas comme un état partagé du pool.

---

## 8. Sources

[docs.immich.app — mobile app](https://docs.immich.app/features/mobile-app/) ·
[sharing](https://docs.immich.app/features/sharing/) ·
[partner sharing](https://docs.immich.app/features/partner-sharing/) ·
[libraries](https://docs.immich.app/features/libraries) ·
[FAQ](https://docs.immich.app/FAQ/) ·
[roadmap](https://immich.app/roadmap) ·
[v3.0.0](https://immich.app/blog/v3.0.0-release) ·
[récap juin 2026](https://immich.app/blog/2026-june-recap) ·
[#12614 feature freeze](https://github.com/immich-app/immich/issues/12614) ·
[#28544](https://github.com/immich-app/immich/issues/28544) ·
[#15572](https://github.com/immich-app/immich/issues/15572) ·
[#28796](https://github.com/immich-app/immich/discussions/28796) ·
[#11333](https://github.com/immich-app/immich/issues/11333) ·
[#15050](https://github.com/immich-app/immich/issues/15050) ·
[#20617](https://github.com/immich-app/immich/issues/20617) ·
[#17422](https://github.com/immich-app/immich/discussions/17422) ·
[#29167](https://github.com/immich-app/immich/discussions/29167) ·
[#5649 collaborative albums](https://github.com/immich-app/immich/discussions/5649) ·
[immich-face-to-album](https://github.com/romainrbr/immich-face-to-album) ·
[addAssetsToAlbum](https://api.immich.app/endpoints/albums/addAssetsToAlbum) ·
[searchAssets](https://api.immich.app/endpoints/search/searchAssets) ·
[odd.blog — symlinks, écarté](https://odd.blog/2026/01/16/creating-a-shared-photo-library-in-immich/)

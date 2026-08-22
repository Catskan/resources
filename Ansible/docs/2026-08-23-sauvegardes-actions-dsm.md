# Sauvegardes — actions à faire côté DSM

Relevé du 2026-08-23 (nuit). Tout ce qui suit se règle **dans DSM** ou demande une
décision, donc hors de portée d'Ansible et de l'assistant. Le volet Proxmox est fait
et codifié : branche `feat/proxmox-backup-job`, commits `86f00ae`, `7e5a318`, `2f8cb9c`.

---

## 1. 🔴 Les cinq réplications sont en erreur — rien ne part hors site

Constaté dans Snapshot Replication > Replication, toutes les destinations sur
`Volume 3` en Btrfs :

| tâche                | source              | état                    |
| -------------------- | ------------------- | ----------------------- |
| `Aurelien-1`         | `[Nas] Aurelien`    | `Permission Error`      |
| `docker-1`           | `[Nas] docker`      | `Permission Error`      |
| `Gene-1`             | `[Nas] Gene`        | `Permission Error`      |
| `Sauvegardes-1`      | `[Nas] Sauvegardes` | `Permission Error`      |
| `homes-replicated-2` | `[82.64.232.199]`   | **`Connection Failed`** |

Les quatre `Permission Error` correspondent au mot de passe à réactualiser.

⚠️ **`homes-replicated-2` est un autre mode de panne** : `Connection Failed` est du
réseau ou de l'hôte, pas de l'authentification. Et sa source `82.64.232.199` n'est **ni
le site d'Aurélien** (`82.67.69.38`) **ni celui de la mère** (`82.67.182.91`).
Identifier de quelle machine il s'agit avant de le réparer — ça peut être une source
obsolète à supprimer plutôt qu'à remettre en route.

Tant que ces tâches sont en erreur, la protection hors site est **nulle**, quel que
soit le reste.

## 2. 🔴 Les dumps Proxmox partent hors site pour rien — il faut un partage dédié

`showmount -e 192.168.1.7` confirme que `/volume2/Sauvegardes` est un **partage**, celui
que `Sauvegardes-1` réplique chez l'ami. Son contenu au 2026-08-23 :

| entrée                        | taille                           |
| ----------------------------- | -------------------------------- |
| `@ActiveBackup`               | 154 Go                           |
| `Proxmox Aurelien`            | 54 Go ← job vzdump de l'Optiplex |
| `dump`                        | 8,1 Go                           |
| `Proxmox maman`               | 6,5 Go ← job vzdump du Wyse      |
| `Amandine`, `untitled folder` | 0                                |

Les deux jobs vzdump créés dans la nuit écrivent donc **dans le partage répliqué**.
Snapshot Replication étant **à la granularité du partage**, on ne peut pas en exclure
un sous-dossier. Conséquence : ~60 Go de dumps complets neufs expédiés chaque semaine
par le lien montant, sans aucune communauté de blocs avec la semaine précédente (un
dump zstd complet diffère de bout en bout) — pour de la donnée **reproductible**.

**À faire dans DSM :** créer un partage dédié, par exemple `ProxmoxBackup`, sur
`volume2`, **non couvert par la réplication**, et l'exporter en NFS vers `192.168.1.100`
et le tailnet (`100.64.0.7`) avec les mêmes options que l'existant
(`vers=4,soft,timeo=600,retrans=2`).

Ensuite, côté Proxmox (assistant, 10 min) : repointer les deux stockages
`NAS_Backup_NFS` sur le nouvel export, déplacer les archives existantes, et un commit
Ansible. **Ne pas oublier** que le stockage du Wyse vise `100.64.0.6` (tailnet) et
celui de l'Optiplex `192.168.1.7` (LAN) — deux entrées à ajuster, pas une.

## 3. Vérifier lequel des deux produits est réellement en place

Aucun conteneur `.hbk` n'est visible ni dans `Aurelien` ni dans `Sauvegardes` — les
seuls partages inspectables depuis l'extérieur, les partages sans export NFS étant
invisibles. En revanche `@ActiveBackup` pèse 154 Go : c'est **Active Backup for
Business**, pas **Hyper Backup**. Deux produits distincts, chemins de restauration
distincts.

À confirmer :

- où vit la destination de la tâche Hyper Backup « entre les deux disques » ;
- **si cette tâche est chiffrée** — c'est ce qui rend acceptable que la copie atterrisse
  sur le matériel d'un tiers, Snapshot Replication n'ayant aucun chiffrement propre ;
- si cette destination est elle aussi dans un partage répliqué (sinon la chaîne
  « HB local → réplication hors site » est rompue).

Si la tâche HB n'est pas chiffrée, c'est le seul vrai point faible du montage :
la donnée est lisible par l'administrateur du NAS distant.

## 4. 🔴 volume1 est à 99 % — 63 Go libres sur 3,5 To

```
192.168.1.7:/volume1/Aurelien   3.5T  3.5T   63G  99%
192.168.1.7:/volume2/…          3.5T  2.5T  1.1T  71%
```

C'est le volume qui porte `Vault` (le `.kdbx` dont dépend **tout** Ansible),
`Documents`, `PrivateGit`, `Projects` (dont les 7,1 Go du bot Vinted), `Photos`,
`Videos`, `Movies`.

À ce niveau de remplissage, **les snapshots commencent à être purgés ou refusés et la
réplication n'a plus de marge pour travailler sur la source** — donc ça bloque les
points 1 et 2 avant même de les traiter. Premier endroit à regarder : `#recycle`.

## 5. Ce qu'il faut envoyer hors site, et ce qu'il ne faut pas

Mesuré le 2026-08-23.

**À envoyer** — l'irremplaçable :

- `/volume2/Photos/Immich/library` — **749 Go**. C'est la bibliothèque photo réelle ;
  elle n'est **pas** dans le disque de la VM Immich, donc aucun `vzdump` ne la couvre.
- `Photos`, `Documents`, `PrivateGit`, `Vault`, et les `data-*` du bot Vinted (7,1 Go).

**À ne pas envoyer :**

- `/volume2/Photos/Immich/encoded-video` — **292 Go**, entièrement regénérable par
  re-transcodage.
- `Sauvegardes/Proxmox *` — ~360 Go à terme, renouvelés en entier chaque semaine donc
  sans gain de déduplication, et reproductibles. C'est l'objet du point 2.

Ces deux exclusions économisent ~650 Go sur le disque de l'ami et sur le lien montant.

**Amorcer sur le LAN** : 749 Go par un lien montant grand public se comptent en jours.
Faire la première copie sur place, puis emporter le disque.

**Casser la dépendance circulaire** : `Vault/Aurel-vault.kdbx` (502 Ko) vit sur le NAS
et c'est ce dont tous les playbooks ont besoin (`KEEPASS_LOCATION` par défaut
`/Volumes/Aurelien/Vault/`). Perdre le NAS, c'est perdre à la fois les données et le
moyen de reconstruire. Ces 502 Ko méritent une copie qui ne dépende pas du NAS.

## 6. Notifications Proxmox — décision à prendre

Les deux nœuds n'ont **aucun endpoint de notification** : seul le matcher intégré
`mail-to-root`, donc un échec de sauvegarde écrit dans la boîte mail locale de root.
C'est précisément ce qui a permis à un mois d'échecs de passer inaperçu (voir le
commit `7e5a318`).

PVE 9.2 supporte `smtp`, `gotify` et `webhook`. Le plus rapide serait un **webhook
Slack**, en réutilisant le token bot déjà en place pour l'agent d'astreinte
(`/srv/astreinte/secrets/slack.env` dans le LXC 103). Non fait : ça engage un secret et
une intégration sortante, donc validation attendue.

## 7. Ménage, accessoire

Dans `Sauvegardes`, partage qui part hors site : `dump` (8,1 Go, ancien emplacement de
dumps ?), `untitled folder` et `Amandine` vides.

---

## Rappel du seul contrôle fiable d'une sauvegarde Proxmox

Un invité en échec laisse un `.log` **sans archive**, posé à côté des archives réussies
des autres. Ni l'UI ni `/cluster/backup-info/not-backed-up` ne le montrent — cette API
décrit l'intention du job, pas son résultat.

```bash
cd /mnt/pve/NAS_Backup_NFS/dump
for l in *.log; do b=${l%.log}; [ -e "${b}.tar.zst" ] || [ -e "${b}.vma.zst" ] || echo "ECHEC: $l"; done
```

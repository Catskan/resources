# Inventaire des jeux — checklist de réinstallation (bare-metal)

> **Pourquoi ce fichier ?** Les jeux installés via **launchers tiers** (Ubisoft
> Connect, Epic, GOG, EA, Rockstar) et via **Xbox Game Pass** ne sont **pas
> auto-installables par Ansible** : ces plateformes n'exposent aucune commande
> d'installation scriptable, et les titres Game Pass exigent l'app Xbox +
> l'abonnement. Le rôle `windows_gaming` installe déjà les **launchers**, l'**app
> Xbox** et configure les **chemins d'install** — mais les jeux eux-mêmes se
> réinstallent **manuellement** après connexion à chaque launcher.
>
> Cette liste sert de **checklist** post-bare-metal pour ne rien oublier.
> À compléter/mettre à jour à la main (Aurélien).

## Xbox / Game Pass (app Xbox → installer sur `M:\XboxGames`)

- [ ] **Forza Horizon 6** (+ Expansion 1, Expansion 2)

## Ubisoft Connect (login → bibliothèque → installer)

- [ ] **The Crew Motorfest**
- [ ] _… à compléter_

## Epic Games

- [ ] _… à compléter_

## GOG Galaxy

- [ ] _… à compléter_

## EA app

- [ ] _… à compléter_

## Rockstar Games

- [ ] _… à compléter_

---

_Steam n'est pas listé ici : sa bibliothèque se re-télécharge intégralement au
login (dossier `M:\SteamLibrary` déjà configuré par `launcher_paths.yml`)._

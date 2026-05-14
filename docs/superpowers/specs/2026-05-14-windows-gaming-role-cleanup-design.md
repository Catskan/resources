# Windows Gaming Role Cleanup & Modernization — Design Spec

**Date** : 2026-05-14
**Branch** : `feature/windows-gaming-optim-spec` (même branche que la spec d'optim)
**Scope** : `Ansible/roles/windows_gaming/tasks/{system_settings,softwares_check,softwares_download,softwares_install,softwares_uninstall,softwares_check_versions,ms_store_apps,user_folders}.yml` + `Ansible/roles/common/templates/firefox_policies.json`
**Hors scope** : tout ce qu'on a déjà ajouté en Tasks 1-16 (defender.yml / gaming_optim.yml / console_ux.yml / drivers.yml / verify_gaming_optim.yml) — **intouché**.

---

## 1. Objectif

Le rôle a accumulé du legacy depuis la migration "GitHub Actions → Vagrant Docker → Ansible local". Trois classes de problèmes coexistent :

- **Bugs idempotence** (Firefox check version-pinné, reboot non-coordonné, etc.) qui peuvent faire planter le run réel à venir
- **Inconsistance modules / FQCN** que `make lint` flagge déjà
- **Dette pattern** (modules non-FQCN, GUIDs hardcodés au lieu de winget)

Trois phases indépendantes pour découpler livraison et risque :

| Phase                  | Effort | Bloque Task 17 ? | Bénéfice                                                                          |
| ---------------------- | ------ | ---------------- | --------------------------------------------------------------------------------- |
| 1 — Critical fixes     | ~1h    | **Oui**          | Run réel propre, plus de reboot fantôme, GFE pas réinstallé                       |
| 2 — Important refactor | ~1h    | Non              | Code lint-clean, idempotence native                                               |
| 3 — Vision winget      | ~5h    | Non              | Maintenance triviale, suppression progressive de softwares_check/download/install |

**Ordre de livraison recommandé** : Phase 1 → run Task 17 → Phase 2 → Phase 3.

---

## 2. Phase 1 — Critical fixes (avant Task 17)

### 2.1 C1 — Firefox check sans version-pin

**Fichier** : `Ansible/roles/windows_gaming/tasks/softwares_check.yml` ligne 9-12

**Avant** :

```yaml
- name: Check if Firefox is already installed
  win_reg_stat:
    path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Mozilla Firefox 106.0.5 (x64 en-US)
  register: Firefox_installed
```

**Après** :

```yaml
- name: Check if Firefox is already installed
  ansible.windows.win_reg_stat:
    path: HKLM:\SOFTWARE\Mozilla\Mozilla Firefox
  register: Firefox_installed
```

`HKLM:\SOFTWARE\Mozilla\Mozilla Firefox` est créé par TOUT installer Firefox (officiel ou ESR), indépendant de la version. Stable depuis Firefox 3.x.

### 2.2 C2 — Firefox install : same as before, downstream consumer

L'install task à `softwares_install.yml:7` continue de fonctionner avec `Firefox_installed.exists == false`. Une fois C1 corrigé, ce check ne déclenche plus de ré-install sur les Firefox déjà présents.

**Vérification post-fix** : lancer `make windows ARGS='--tags softwares_install'` après un Firefox manuel installé → doit annoncer `changed=0` sur cette task.

### 2.3 C3 — Variables `register: result` dupliquées

**Fichier** : `softwares_install.yml` lignes 10-18

**Avant** : NVIDIA driver et GFE register both as `result` (le 2ème écrase le 1er).

**Après** : renommer en `nvidia_driver_install_result` et `nvidia_gfe_install_result` (et supprimer la GFE task — voir C4).

### 2.4 C4 — Supprimer install NVIDIA GeForce Experience

**Fichier** : `softwares_install.yml` lignes 15-18 + `softwares_download.yml` lignes 32-37 + `softwares_check.yml` lignes 22-26

Contradiction directe avec le spec de gaming optim (Q6a A1-bis : pas de GFE, services telemetry désactivés). Supprimer les 3 blocs liés à GFE :

- check `Nvidia_Geforce_Experience_installed`
- download `Nvidia Geforce Experience`
- install `Nvidia Geforce Experience`

Variables associées (`nvidia_geforce_experience`) à retirer de `group_vars/windows_hosts/main.yml` si présentes.

### 2.5 C5 — Reboot non-coordonné dans user_folders.yml

**Fichier** : `Ansible/roles/windows_gaming/tasks/user_folders.yml` lignes 509-512

**Avant** :

```yaml
- name: Reboot Gaming
  ansible.windows.win_reboot:
    test_command: 'exit (Get-Service -Name WinRM).Status -ne "Running"'
  when: inventory_hostname == "aurelien-gaming"
```

Inconditionnel : reboot à CHAQUE run de user_folders sur aurelien-gaming, même si rien n'a changé. Et redundant avec le reboot block consolidé en fin de `main.yml` (Task 16).

**Après** : supprimer le bloc Reboot inline. À la place, après les `win_regedit` qui changent les paths, ajouter une notification au reboot consolidé :

```yaml
- name: Flag reboot if user folder paths changed
  ansible.builtin.set_fact:
    reboot_required: true
  when: <chaque task win_regedit change>.changed | default(false)
```

**Implémentation simple** : register chaque `win_regedit` clé dans une liste, puis un seul `set_fact: reboot_required: true` quand n'importe quel `changed`.

### 2.6 Phase 1 — Critères d'acceptation

1. `make lint` ne lève aucune NOUVELLE erreur (les pré-existantes peuvent rester)
2. Sur un host avec Firefox déjà installé : `make windows ARGS='--tags softwares'` → `Firefox_installed.exists == true`
3. Aucun reboot déclenché par `user_folders.yml` quand rien n'a changé
4. Variables `nvidia_geforce_experience*` absentes des group_vars (grep négatif)
5. Le rôle ne tente plus d'installer GFE

---

## 3. Phase 2 — Important refactor (réduite — items redondants avec Phase 3 retirés)

**Note de scope** (mise à jour 2026-05-14) : Phase 3 supprime entièrement `softwares_check.yml`, `softwares_download.yml`, `softwares_install.yml`, `softwares_uninstall.yml`, `ms_store_apps.yml`, `drivers.yml`. Tous les refactors qui visaient à les nettoyer (migration `win_package`, rescue blocks, cleanup tag) sont donc **inutiles** — ils seraient appliqués pour ensuite supprimer les fichiers. Phase 2 se réduit aux items qui survivent Phase 3 : nettoyage `user_folders.yml` et FQCN sur les fichiers qui ne sont **pas** supprimés en Phase 3.

Effort estimé révisé : ~1h (vs 3h initial).

### 3.1 I2 — FQCN sur les fichiers qui survivent Phase 3

**Fichiers concernés** :

- `Ansible/roles/windows_gaming/tasks/main.yml`
- `Ansible/roles/windows_gaming/tasks/system_settings.yml`
- `Ansible/roles/windows_gaming/tasks/user_folders.yml`

(Les autres fichiers — `softwares_*.yml`, `ms_store_apps.yml`, `drivers.yml` — étant supprimés en Phase 3, on ne perd pas son temps à les FQCN-ifier.)

Pattern remplacement :

| Ancien         | Nouveau                        |
| -------------- | ------------------------------ |
| `win_reg_stat` | `ansible.windows.win_reg_stat` |
| `win_shell`    | `ansible.windows.win_shell`    |
| `win_service`  | `ansible.windows.win_service`  |
| `win_regedit`  | `ansible.windows.win_regedit`  |
| `win_reboot`   | `ansible.windows.win_reboot`   |
| `win_file`     | `ansible.windows.win_file`     |

Effort : ~10 minutes de search/replace + 1 lint pass.

### 3.2 I3 — Cleanup `user_folders.yml`

**Avant** : 513 lignes dont ~80% commentées.

**Après cible** : ~80-100 lignes actives.

Actions :

- Supprimer tous les blocs commentés (HKLM\..., HKCU\...\User User Shell Folders qui est invalide, "Common Administrative Tools", etc.)
- Dedup `Documents` (2× redirected), `Music` vs `My Music` (2 paths différents pour la même chose)
- Supprimer `Get-WmiObject Win32_Account ... SID` + le fact `user_name_sid` (jamais utilisé)
- Supprimer la task `debug: var: user_name_sid` (output de debug oublié)
- Supprimer le reboot inline (déjà fait en Phase 1 C5)
- Re-indenter au top-level standard (2 spaces, pas 4)
- Déplacer les 2 tasks VSS access control vers `system_settings.yml` (ou nouveau `vss.yml`)
- Appliquer FQCN (en même temps que I2 ci-dessus)

### 3.3 Phase 2 — Critères d'acceptation

1. `make lint` : zéro erreur sur les 3 fichiers ciblés (main.yml, system_settings.yml, user_folders.yml)
2. `user_folders.yml` ≤ 120 lignes (vs 513 actuellement)
3. Aucun module non-FQCN dans les 3 fichiers ciblés (grep `^\s*win_` négatif sauf à l'intérieur de strings/commentaires)
4. 2 runs successifs de `make windows` (sans Phase 3 encore appliquée) → `changed=0` au second run sur ces 3 fichiers

### 3.4 Items NON inclus dans Phase 2 (redondants avec Phase 3)

Pour mémoire — ne PAS implémenter :

- ~~I1 win_package migration~~ → `softwares_install.yml` supprimé en Phase 3
- ~~FQCN sur softwares\_\*.yml / ms_store_apps.yml / drivers.yml~~ → fichiers supprimés en Phase 3
- ~~Rescue blocks dans softwares_download.yml~~ → fichier supprimé en Phase 3
- ~~Cleanup tag sur Remove Temp directory~~ → softwares_install.yml supprimé en Phase 3

Si pour une raison X on doit ship Phase 2 sans Phase 3 (ex : winget pose problème inattendu), revisiter le spec et restaurer ces items.

---

## 4. Phase 3 — Vision longue : migration winget complète

### 4.1 P3a — Remplacer softwares\_{check,download,install}.yml + drivers.yml par softwares_winget.yml

**Décision** (mise à jour 2026-05-14) : tout passe par winget, **y compris les drivers GPU et chipset**. `drivers.yml` est vidé de sa logique d'install, seule la partie telemetry cleanup NVIDIA est conservée et déplacée vers un nouveau fichier `nvidia_cleanup.yml` (services + scheduled task) car elle n'est pas une opération winget.

**Nouvelle structure** :

```
roles/windows_gaming/tasks/
├── softwares_winget.yml    ← UNIQUE fichier d'install (drivers + apps), remplace les 4 ci-dessous
├── softwares_check.yml     ← supprimé
├── softwares_download.yml  ← supprimé
├── softwares_install.yml   ← supprimé (shortcut Playnite migré vers console_ux.yml ou apps_shortcuts.yml)
├── softwares_uninstall.yml ← supprimé (AppX bloatware migré dans console_ux.yml — cf. §4.4 P3d)
├── drivers.yml             ← supprimé (install logic absorbée par winget ; telemetry cleanup → nvidia_cleanup.yml)
└── nvidia_cleanup.yml      ← NEW — uniquement les services NVIDIA disable + NvTmRep_CrashReport removal
```

**Variables consommées par le nouveau `nvidia_cleanup.yml`** : `nvidia_telemetry_cleanup` (bool, déjà dans host_vars). Les variables `nvidia_driver_install_strategy`, `nvidia_driver_url`, `nvidia_driver_version` deviennent obsolètes — à retirer du host_vars dans la même PR (le user veut full winget, pas de fallback direct_url).

**Contenu de `softwares_winget.yml`** (~50 lignes) :

```yaml
- name: Install softwares via winget
  ansible.windows.win_powershell:
    script: |
      $packages = @({{ winget_packages | map('to_json') | join(', ') }})
      $changed = $false
      foreach ($id in $packages) {
        $installed = winget list --id $id --exact 2>$null | Select-String $id
        if (-not $installed) {
          winget install --id $id --silent --accept-package-agreements --accept-source-agreements
          $changed = $true
        }
      }
      $Ansible.Changed = $changed
```

**Nouvelle variable** dans `host_vars/aurelien-gaming/main.yml` (drivers d'abord, puis apps) :

```yaml
winget_packages:
  # --- Drivers GPU + chipset (ex-drivers.yml) ---
  - AdvancedMicroDevices.AMDChipsetDrivers
  - Nvidia.GeForceDriver

  # --- Launchers de jeux ---
  - Valve.Steam
  - EpicGames.EpicGamesLauncher
  - Ubisoft.Connect
  - GOG.Galaxy
  - ElectronicArts.EADesktop

  # --- Apps user ---
  - Mozilla.Firefox
  - Notepad++.Notepad++
  - VideoLAN.VLC
  - CrystalDewWorld.CrystalDiskInfo
  - Synology.DriveClient # à vérifier la disponibilité winget
  - 7zip.7zip
  - Microsoft.WindowsTerminal
  - Microsoft.PowerToys
  - Microsoft.PowerShell

  # --- MS Store (ex-ms_store_apps.yml) ---
  - 9NBLGGH4TXTC # Xbox Accessories (winget retrouve via Store ID)
```

**Note sur les drivers** : `Nvidia.GeForceDriver` via winget installe **uniquement le driver, pas GeForce Experience** — ce qui aligne avec le choix Q6a (NVCleanstall style). L'idempotence est garantie par le check `winget list --id $id --exact` au début de chaque itération.

**Note sur la stratégie `direct_url`** : supprimée. Le full-winget signifie que si un package n'existe pas dans winget, on le retire de la liste et l'install reste manuelle. Plus de complexité multi-stratégies.

### 4.2 P3b — Migration progressive, pas big-bang

Phase 3 par étapes (chacune un commit, testable indépendamment) :

1. **3.1** : créer `softwares_winget.yml` à côté de l'existant, wire dans main.yml derrière un tag `softwares_winget` (pas dans le tag `softwares`)
2. **3.2** : tester en parallèle (`make windows ARGS='--tags softwares_winget'`) sans casser l'existant
3. **3.3** : migrer un package à la fois — Firefox d'abord (puisqu'on l'a déjà reverifié en Phase 1), puis Steam, etc.
4. **3.4** : à chaque migration, supprimer le check/download/install du package dans les 3 anciens fichiers
5. **3.5** : **migrer les drivers** — ajouter `AdvancedMicroDevices.AMDChipsetDrivers` et `Nvidia.GeForceDriver` à `winget_packages`, créer `nvidia_cleanup.yml` (services + scheduled task), supprimer `drivers.yml`
6. **3.6** : **migrer Xbox Accessories** — ajouter au `winget_packages`, supprimer `ms_store_apps.yml` du repo et de `main.yml`
7. **3.7** : quand TOUT est migré, supprimer `softwares_check.yml` / `softwares_download.yml` / `softwares_install.yml`
8. **3.8** : **migrer la liste AppX** — déplacer la liste hardcoded de `softwares_uninstall.yml` (19 items) dans la var unifiée `appx_bloatware: [28 items]`, faire pointer le loop de `console_ux.yml` dessus, supprimer `softwares_uninstall.yml` du repo
9. **3.9** : déplacer le shortcut Playnite (la seule task non-winget restante) vers `console_ux.yml` ou un nouveau `apps_shortcuts.yml`
10. **3.10** : retirer les vars obsolètes de `host_vars` (`nvidia_driver_install_strategy`, `nvidia_driver_url`, `nvidia_driver_version`, `nvidia_geforce_experience` si encore présente, `nvidia_driver` dans group_vars/windows_hosts) et de tout ce qui pointait vers les fichiers supprimés

### 4.3 P3c — Update `firefox_policies.json` URLs

**Fichier** : `Ansible/roles/common/templates/firefox_policies.json`

URLs pinned à remplacer par `latest.xpi` :

| Extension           | Avant                                                           | Après                                                      |
| ------------------- | --------------------------------------------------------------- | ---------------------------------------------------------- |
| VideoDownloadHelper | `firefox/downloads/file/3804074/video_downloadhelper-7.6.0.xpi` | `firefox/downloads/latest/video-downloadhelper/latest.xpi` |
| DownThemAll         | `firefox/downloads/file/3983650/downthemall-4.5.2.xpi`          | `firefox/downloads/latest/downthemall/latest.xpi`          |

uBlock et KeePassXC sont déjà sur `latest.xpi` — aucune action.

### 4.4 P3d — `softwares_uninstall.yml` + `appx_bloatware_extended` unification

Le rôle a deux listes d'AppX à virer : `softwares_uninstall.yml` (19 hardcoded) et `appx_bloatware_extended` (9 dans host_vars).

**Décision** (mise à jour 2026-05-14) : **Option A** — la liste unifiée vit dans `console_ux.yml`. `softwares_uninstall.yml` est entièrement supprimé du repo. Le tag `softwares_uninstall` (et son alias `cleanup`) sont retirés de `main.yml`.

Justification : sémantiquement, retirer les AppX bloatware est du **debloat console UX**, pas un workflow d'install software. Concentrer ça dans `console_ux.yml` rend le rôle plus cohérent : `console_ux.yml` = "tout ce qui rend Windows propre", `softwares_winget.yml` = "tout ce qu'on installe".

**Étapes** :

1. Renommer la var `appx_bloatware_extended` (9 items) → `appx_bloatware` et y ajouter les 19 items hardcoded de `softwares_uninstall.yml` (total 28 items).
2. Modifier le loop de `console_ux.yml` §4.3.1 pour consommer `appx_bloatware` au lieu de `appx_bloatware_extended`.
3. Supprimer `Ansible/roles/windows_gaming/tasks/softwares_uninstall.yml`.
4. Retirer de `main.yml` :
   - L'include `softwares_uninstall.yml` (tag `softwares_uninstall, cleanup`)
   - La mention de ces tags dans le commentaire header
5. Retirer les tags `softwares_uninstall` et `cleanup` du tableau de `CLAUDE.md`.

### 4.5 Phase 3 — Critères d'acceptation

1. `softwares_check.yml`, `softwares_download.yml`, `softwares_install.yml` supprimés du repo
2. `make windows` install tout via winget en idempotent
3. `firefox_policies.json` n'a aucune URL avec `/file/<id>/<name>.xpi` (juste `/latest/<slug>/latest.xpi`)
4. Pas de doublon de liste AppX entre `softwares_uninstall.yml` et host_vars
5. `make lint` passe à zéro

---

## 5. Risques & non-régression

| Risque                                                                   | Phase | Mitigation                                                                                                                                                                                                                                                    |
| ------------------------------------------------------------------------ | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Firefox check Mozilla path différent selon ESR vs Release                | 1     | Tester sur les deux types. Fallback : check via `Get-ItemProperty HKLM:\SOFTWARE\Mozilla\Mozilla Firefox\CurrentVersion`.                                                                                                                                     |
| Suppression de `user_folders.yml` commenté = perte d'historique          | 2     | Tous les blocs sont dans git history. `git log -p user_folders.yml` reste accessible.                                                                                                                                                                         |
| Tasks VSS access control déplacées depuis user_folders.yml               | 2     | Verifier que la nouvelle location dans `system_settings.yml` (ou nouveau `vss.yml`) reste correctement appliquée. Tester avec `make verify-windows`.                                                                                                          |
| Winget package indisponible (`Synology.DriveClient`)                     | 3     | Vérifier disponibilité avant migration via `winget search`. Si absent : retirer de la liste et installer manuellement. La stratégie `direct_url` est explicitement abandonnée pour rester full-winget.                                                        |
| Migration winget casse les paths d'install attendus par d'autres scripts | 3     | Winget installe dans des paths standardisés (`C:\Program Files\<App>\`). Audit Playnite, etc. avant.                                                                                                                                                          |
| `Nvidia.GeForceDriver` via winget tire-t-il GFE en sneaky ?              | 3     | Vérifier sur un host de test : `winget show Nvidia.GeForceDriver` indique l'installer flags. À documenter dans le commit. Si GFE arrive en bundle, fallback : retirer NVIDIA du `winget_packages` et garder le driver install manuel (NVCleanstall une fois). |
| Xbox Accessories via Store ID `9NBLGGH4TXTC`                             | 3     | Vérifier que winget accepte les Store IDs (alphanumériques) en plus des publisher.app IDs. Si non : utiliser `Microsoft.XboxAccessories` (vérifier la disponibilité). Sinon : remettre `ms_store_apps.yml` minimal pour ce seul cas.                          |

---

## 6. Critères globaux d'acceptation

Le projet de cleanup est considéré terminé quand :

1. Toutes les Phase 1/2/3 critères individuels sont remplis
2. `make windows` complet sur `aurelien-gaming` annonce `changed=0` au 2e run (idempotence parfaite)
3. `make lint` passe sans aucun warning ni error
4. `make verify-windows` (le playbook de Task 2 de l'autre plan) confirme l'état final
5. `Ansible/roles/windows_gaming/tasks/` ne contient plus que (8 fichiers vs 13 actuellement) :
   - `main.yml` (orchestrateur — tags `softwares_uninstall`, `cleanup`, `ms_store`, `drivers` retirés)
   - `system_settings.yml` (nettoyé en Phase 2 ; éventuellement +2 tasks VSS migrées depuis user_folders.yml)
   - `user_folders.yml` (≤ 120 lignes après Phase 2)
   - `softwares_winget.yml` (NEW — drivers + apps + MS Store unifiés)
   - `nvidia_cleanup.yml` (NEW — services NVIDIA disable + scheduled task removal, seule logique non-winget)
   - `defender.yml`, `gaming_optim.yml`, `console_ux.yml` (du spec précédent ; `console_ux.yml` absorbe l'AppX bloatware loop)
6. **Fichiers supprimés** : `softwares_check.yml`, `softwares_download.yml`, `softwares_install.yml`, `softwares_uninstall.yml`, `ms_store_apps.yml`, `drivers.yml` (6 fichiers en moins)
7. **Variables supprimées** de `host_vars` et `group_vars` : `nvidia_driver_install_strategy`, `nvidia_driver_url`, `nvidia_driver_version`, `nvidia_driver` (group_vars), `nvidia_geforce_experience`, et tous les `*_installed` registres qu'on n'utilise plus
8. **Variable renommée** : `appx_bloatware_extended` → `appx_bloatware` (28 items)
9. **Variable nouvelle** : `winget_packages` (liste des packages winget à installer)

---

## 7. Hors scope (volontairement laissé)

- **Migration des autres rôles** (`linux_laptop`, `common`) — focus est `windows_gaming` uniquement
- **Refactor de `system_settings.yml`** au-delà du minimum requis par Phase 1/2 (RDP/WoL/AutoLogon restent là)
- **Audit `bootstrap_winrm.ps1`** — auto-run sur new install, séparé de la chaîne Ansible
- **Tests automatisés** — pas de framework de test pour ce rôle, on s'appuie sur `make check-windows` + `make verify-windows`

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
- **Dette pattern** (`win_command` partout au lieu de `win_package`, GUIDs hardcodés au lieu de winget)

Trois phases indépendantes pour découpler livraison et risque :

| Phase                  | Effort | Bloque Task 17 ? | Bénéfice                                                                          |
| ---------------------- | ------ | ---------------- | --------------------------------------------------------------------------------- |
| 1 — Critical fixes     | ~1h    | **Oui**          | Run réel propre, plus de reboot fantôme, GFE pas réinstallé                       |
| 2 — Important refactor | ~3h    | Non              | Code lint-clean, idempotence native                                               |
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

## 3. Phase 2 — Important refactor

### 3.1 I1 — Migration `win_package` au lieu de `win_command`

**Fichiers** : `softwares_install.yml`

Pattern actuel :

```yaml
- name: Install Firefox
  win_command: C:\Windows\System32\msiexec.exe /i C:\temp\Firefox.msi /qb /norestart
  when: Firefox_installed.exists == false
```

Pattern cible :

```yaml
- name: Install Firefox
  ansible.windows.win_package:
    path: C:\temp\Firefox.msi
    state: present
    arguments: /qb /norestart
```

`win_package` est idempotent natif (vérifie via `product_id` ou MSI ProductCode si fourni), tracke uninstall, supporte `--check` mode. Plus besoin du check.yml registre pour les MSI.

À migrer : Firefox, Synology Drive, Epic, Ubisoft Connect, Steam (EXE pas MSI mais `win_package` supporte aussi via `creates:` ou `product_id`).

**Cas spéciaux** : NVIDIA driver (EXE silencieux), Steam (EXE), CrystalDiskInfo (EXE) — soit on garde `win_command` avec `creates:` (path d'install attendu), soit on bascule sur winget directement (Phase 3).

### 3.2 I2 — FQCN partout

**Fichiers concernés** : `softwares_*.yml`, `user_folders.yml`, `ms_store_apps.yml`, `system_settings.yml`

Pattern remplacement :
| Ancien | Nouveau |
|---|---|
| `win_reg_stat` | `ansible.windows.win_reg_stat` |
| `win_get_url` | `ansible.windows.win_get_url` |
| `win_command` | `ansible.windows.win_command` |
| `win_shell` | `ansible.windows.win_shell` |
| `win_service` | `ansible.windows.win_service` |
| `win_regedit` | `ansible.windows.win_regedit` |
| `win_template` | `ansible.windows.win_template` |
| `win_unzip` | `community.windows.win_unzip` |
| `win_reboot` | `ansible.windows.win_reboot` |

Effort : ~15 minutes de search/replace + 1 lint pass.

### 3.3 I3 — Cleanup `user_folders.yml`

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

### 3.4 I4 — `softwares_download.yml` : rescue/failed_when manquants

Wrap chaque download dans un block avec rescue, ou ajouter `failed_when: false` + `register:` pour permettre au playbook de continuer même si un mirror est down. Le main.yml a déjà un `rescue:` block sur l'include — c'est partiel.

Pattern :

```yaml
- name: Download softwares
  block:
    - include_tasks: softwares_download.yml
  rescue:
    - debug: msg: "Un download a échoué — voir log"
```

Existe déjà. Mais à l'intérieur de `softwares_download.yml`, on peut ajouter `ignore_errors: true` + register sur chaque `win_get_url` individuel pour que UNE URL morte ne plante pas TOUS les downloads.

### 3.5 I5 — Soigner `Remove Temp directory`

**Fichier** : `softwares_install.yml` lignes 121-124

**Avant** : `state: absent` à la fin, supprime même si tout a réussi.

**Après** : tagger `[cleanup]` pour permettre `make windows ARGS='--skip-tags cleanup'`, qui garde C:\temp pour debug.

### 3.6 Phase 2 — Critères d'acceptation

1. `make lint` : zéro erreur (pas juste "no new" — vraiment zéro)
2. `softwares_install.yml` n'utilise plus `win_command` pour les MSI (exception NVIDIA EXE conservée si pas migré winget)
3. `user_folders.yml` ≤ 120 lignes (vs 513 actuellement)
4. 2 runs successifs de `make windows` → `changed=0` au second run, partout

---

## 4. Phase 3 — Vision longue : migration winget complète

### 4.1 P3a — Remplacer softwares\_{check,download,install}.yml par softwares_winget.yml

**Nouvelle structure** :

```
roles/windows_gaming/tasks/
├── softwares_winget.yml    ← UNIQUE fichier, remplace les 3 ci-dessous
├── softwares_check.yml     ← supprimé
├── softwares_download.yml  ← supprimé
├── softwares_install.yml   ← supprimé (le shortcut Playnite reste à reloger)
└── softwares_uninstall.yml ← gardé (AppX uninstall, indépendant de winget)
```

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

**Nouvelle variable** dans `host_vars/aurelien-gaming/main.yml` :

```yaml
winget_packages:
  - Mozilla.Firefox
  - Valve.Steam
  - EpicGames.EpicGamesLauncher
  - Ubisoft.Connect
  - GOG.Galaxy
  - ElectronicArts.EADesktop
  - Notepad++.Notepad++
  - VideoLAN.VLC
  - CrystalDewWorld.CrystalDiskInfo
  - Synology.DriveClient # à vérifier la disponibilité winget
  - 7zip.7zip
  - Microsoft.WindowsTerminal
  - Microsoft.PowerToys
  - Microsoft.PowerShell
```

### 4.2 P3b — Migration progressive, pas big-bang

Phase 3 par étapes (chacune un commit, testable indépendamment) :

1. **3.1** : créer `softwares_winget.yml` à côté de l'existant, wire dans main.yml derrière un tag `softwares_winget` (pas dans le tag `softwares`)
2. **3.2** : tester en parallèle (`make windows ARGS='--tags softwares_winget'`) sans casser l'existant
3. **3.3** : migrer un package à la fois — Firefox d'abord (puisqu'on l'a déjà reverifié en Phase 1), puis Steam, etc.
4. **3.4** : à chaque migration, supprimer le check/download/install du package dans les 3 anciens fichiers
5. **3.5** : quand TOUT est migré, supprimer `softwares_check.yml` / `softwares_download.yml` / `softwares_install.yml`
6. **3.6** : déplacer le shortcut Playnite (la seule task non-winget) vers `console_ux.yml` ou un nouveau `apps_shortcuts.yml`

### 4.3 P3c — Update `firefox_policies.json` URLs

**Fichier** : `Ansible/roles/common/templates/firefox_policies.json`

URLs pinned à remplacer par `latest.xpi` :

| Extension           | Avant                                                           | Après                                                      |
| ------------------- | --------------------------------------------------------------- | ---------------------------------------------------------- |
| VideoDownloadHelper | `firefox/downloads/file/3804074/video_downloadhelper-7.6.0.xpi` | `firefox/downloads/latest/video-downloadhelper/latest.xpi` |
| DownThemAll         | `firefox/downloads/file/3983650/downthemall-4.5.2.xpi`          | `firefox/downloads/latest/downthemall/latest.xpi`          |

uBlock et KeePassXC sont déjà sur `latest.xpi` — aucune action.

### 4.4 P3d — `softwares_uninstall.yml` + `appx_bloatware_extended` unification

Le rôle a deux listes d'AppX à virer : `softwares_uninstall.yml` (19 hardcoded) et `appx_bloatware_extended` (9 dans host_vars). Fusionner en une seule variable `appx_bloatware: [...]` (28 entrées) et un seul fichier `softwares_uninstall.yml` qui boucle dessus.

### 4.5 Phase 3 — Critères d'acceptation

1. `softwares_check.yml`, `softwares_download.yml`, `softwares_install.yml` supprimés du repo
2. `make windows` install tout via winget en idempotent
3. `firefox_policies.json` n'a aucune URL avec `/file/<id>/<name>.xpi` (juste `/latest/<slug>/latest.xpi`)
4. Pas de doublon de liste AppX entre `softwares_uninstall.yml` et host_vars
5. `make lint` passe à zéro

---

## 5. Risques & non-régression

| Risque                                                                   | Phase | Mitigation                                                                                                                                           |
| ------------------------------------------------------------------------ | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Firefox check Mozilla path différent selon ESR vs Release                | 1     | Tester sur les deux types. Fallback : check via `Get-ItemProperty HKLM:\SOFTWARE\Mozilla\Mozilla Firefox\CurrentVersion`.                            |
| `win_package` ne détecte pas le product_id sans le fournir               | 2     | Pour les MSI, lire le ProductCode via `msiexec /a` ou via PowerShell `Get-Package`. Pour les EXE non-MSI, garder `win_command` avec `creates:` path. |
| Suppression de `user_folders.yml` commenté = perte d'historique          | 2     | Tous les blocs sont dans git history. `git log -p user_folders.yml` reste accessible.                                                                |
| Winget package indisponible (`Synology.DriveClient`)                     | 3     | Vérifier disponibilité avant migration. Garder l'install direct-URL en fallback pour les manquants.                                                  |
| Migration winget casse les paths d'install attendus par d'autres scripts | 3     | Winget installe dans des paths standardisés (`C:\Program Files\<App>\`). Audit Playnite, etc. avant.                                                 |

---

## 6. Critères globaux d'acceptation

Le projet de cleanup est considéré terminé quand :

1. Toutes les Phase 1/2/3 critères individuels sont remplis
2. `make windows` complet sur `aurelien-gaming` annonce `changed=0` au 2e run (idempotence parfaite)
3. `make lint` passe sans aucun warning ni error
4. `make verify-windows` (le playbook de Task 2 de l'autre plan) confirme l'état final
5. `Ansible/roles/windows_gaming/tasks/` ne contient plus que :
   - `main.yml` (orchestrateur)
   - `system_settings.yml` (nettoyé)
   - `user_folders.yml` (≤ 120 lignes)
   - `softwares_winget.yml`
   - `softwares_uninstall.yml` (liste unifiée)
   - `defender.yml`, `gaming_optim.yml`, `console_ux.yml`, `drivers.yml` (du spec précédent, intouchés)
   - `ms_store_apps.yml` (optionnel — peut être absorbé dans softwares_winget.yml)

---

## 7. Hors scope (volontairement laissé)

- **Migration des autres rôles** (`linux_laptop`, `common`) — focus est `windows_gaming` uniquement
- **Refactor de `system_settings.yml`** au-delà du minimum requis par Phase 1/2 (RDP/WoL/AutoLogon restent là)
- **Audit `bootstrap_winrm.ps1`** — auto-run sur new install, séparé de la chaîne Ansible
- **Tests automatisés** — pas de framework de test pour ce rôle, on s'appuie sur `make check-windows` + `make verify-windows`

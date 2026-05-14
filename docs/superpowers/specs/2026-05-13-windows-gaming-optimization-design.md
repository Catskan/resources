# Windows 11 Gaming Optimization — Design Spec

**Date** : 2026-05-13
**Host cible** : `aurelien-gaming` (PC physique gaming uniquement)
**Hardware** : Ryzen 9800X3D, Asus B850 Max Gaming Wifi W, DDR5 CL30, Fanxiang M.2 NVMe sur C: (système + quelques jeux fréquents) + 2× SSD SATA (M: pour library jeux/data user + un autre), NVIDIA RTX 3080 FE, watercooling custom CPU + GPU
**Rôle Ansible affecté** : `Ansible/roles/windows_gaming/` (+ une modif `Ansible/roles/common/`)

---

## 1. Objectif

Transformer Windows 11 24H2 sur `aurelien-gaming` en OS au comportement le plus proche possible d'une **console Xbox** :

- **Maximum de FPS** et minimum de stutter (focus pain point A)
- **Surface d'attaque réduite + zéro bloatware** (focus pain point E)
- **Zéro interruption pendant le jeu** (pas de notif Cortana, pas d'overlay Edge, pas de sync OneDrive)
- **Boot rapide**, état système stable run après run, idempotent

Trade-off explicite assumé : on sacrifie une partie de la posture de sécurité Windows par défaut (VBS, Tamper Protection, cloud sample reporting) au profit de la perf. Tolérable parce que :

- Machine perso, compte local, jamais utilisée en pro
- Defender reste actif (real-time scanning ON) avec exclusions ciblées sur les paths jeu
- Comptes externes (NAS, Microsoft, Ubisoft, Docker Hub) stockés dans la base KeePass externe — pas dans Windows Credential Manager au-delà du minimum nécessaire

## 2. Pré-requis hors-Ansible (BIOS / hardware)

À configurer **avant** le premier run du rôle. Ansible ne touche pas au BIOS.

| Item                    | Valeur                                                                 |
| ----------------------- | ---------------------------------------------------------------------- |
| Resizable BAR           | `Enabled`                                                              |
| EXPO (mémoire)          | `Enabled` (profile DDR5 CL30)                                          |
| PBO                     | `Enabled` avec Curve Optimizer entre -25 et -30 (X3D sécurisé)         |
| ErP / Energy Star Mode  | `Disabled` ou `Enabled (S4+S5)` — requis pour que WOL fonctionne en S5 |
| Power on by PCIe Device | `Enabled` — requis pour WOL                                            |
| Secure Boot             | au choix — pas requis par le rôle, non touché                          |
| TPM 2.0                 | activé (Win11 le réclame de toute façon)                               |

**Driver NVIDIA 3080 FE** : vérifier qu'on est sur un VBIOS ≥ 90.02.0B.00.97 (rebar support). Update VBIOS via NVIDIA si pas le cas — hors-Ansible.

## 3. Architecture du rôle

### 3.1 Layout fichiers

```
Ansible/roles/windows_gaming/tasks/
├── main.yml              ← orchestrateur (4 nouveaux includes)
├── system_settings.yml   ← inchangé
├── user_folders.yml      ← inchangé
├── softwares_check.yml         ← inchangé
├── softwares_download.yml      ← inchangé
├── softwares_install.yml       ← inchangé
├── softwares_uninstall.yml     ← inchangé (étendu via var, pas le fichier)
├── softwares_check_versions.yml ← inchangé
├── ms_store_apps.yml     ← inchangé
├── defender.yml          ← NEW — Defender exclusions + tuning
├── gaming_optim.yml      ← NEW — VBS off, kernel/réseau/storage, Game DVR/Mode
├── console_ux.yml        ← NEW — debloat, OneDrive uninstall, Edge neutralize, Firefox default
└── drivers.yml           ← NEW — NVIDIA via winget + AMD chipset + NVIDIA telemetry
```

### 3.2 Tags

| Tag            | Couvre             | Exécution sélective                   |
| -------------- | ------------------ | ------------------------------------- |
| `defender`     | `defender.yml`     | `make windows ARGS='--tags defender'` |
| `gaming_optim` | `gaming_optim.yml` | `--tags gaming_optim`                 |
| `console_ux`   | `console_ux.yml`   | `--tags console_ux`                   |
| `drivers`      | `drivers.yml`      | `--tags drivers`                      |

Les tags `defender`, `gaming_optim` et `console_ux` sont aussi inclus dans le tag global existant `system` (tweaks OS-level). Le tag `drivers` est inclus dans le tag global existant `softwares` (catégorie "installation logicielle"). Dans tous les cas, un `make windows` complet exécute les 4 nouveaux fichiers automatiquement.

### 3.3 Variables — `inventory/host_vars/aurelien-gaming/main.yml`

```yaml
# === Defender (defender.yml) ===
defender_exclusion_paths:
  - "C:\\Program Files (x86)\\Steam\\steamapps"
  - "C:\\Program Files\\Epic Games"
  - "C:\\Program Files (x86)\\GOG Galaxy\\Games"
  - "C:\\Program Files (x86)\\Ubisoft\\Ubisoft Game Launcher\\games"
  - "C:\\Program Files\\WindowsApps"
  - "C:\\XboxGames"
  - "C:\\Program Files\\ModifiableWindowsApps"
  - "M:\\"
  - "M:\\XboxGames"
defender_exclusion_processes:
  - "steam.exe"
  - "EpicGamesLauncher.exe"
  - "GalaxyClient.exe"
  - "UbisoftConnect.exe"
  - "gamingservices.exe"
  - "XboxAppServices.exe"
  - "GameBar.exe"
defender_exclusion_extensions: [".dxvk-cache", ".cache", ".pak"]
defender_maps_reporting: "Disabled"
defender_submit_samples: "NeverSend"

# === Gaming optim (gaming_optim.yml) ===
vbs_enabled: false
vbs_weekly_reset:
  enabled: true
  day: Sunday
  time: "04:00"
system_responsiveness: 0
network_throttling_index: "0xFFFFFFFF"
nagle_disable_on_gaming_nic: true
hibernation_enabled: false
page_file:
  strategy: fixed
  initial_size_mb: 32768
  max_size_mb: 49152
usb_selective_suspend: false
pcie_link_state_power_off: true
game_dvr_disabled: true
game_mode_enabled: true
# Xbox Game Bar overlay laissé ON volontairement (capture native)

# === Console UX (console_ux.yml) ===
appx_bloatware_extended:
  - Microsoft.549981C3F5F10 # Cortana
  - Microsoft.BingSearch
  - Microsoft.MicrosoftStickyNotes
  - Microsoft.MixedReality.Portal
  - Microsoft.Wallet
  - Microsoft.WindowsCommunicationsApps # Mail + Calendar
  - MicrosoftCorporationII.QuickAssist
  - Microsoft.OutlookForWindows
  - Microsoft.Windows.DevHome
cortana_disabled: true
bing_search_disabled: true
widgets_disabled: true
onedrive_uninstall: true
edge_neutralize: true
notifications_globally_off: true
background_apps_force_deny: true
recommended_files_off: true
startup_apps_disable:
  - "MSEdgeUpdate"
  - "Adobe ARM"
  - "iTunesHelper"
  - "iCloudDrive"
  - "Cortana"
telemetry_minimum: true
firefox_set_default: true

# === Drivers (drivers.yml) ===
amd_chipset_install: true
nvidia_driver_install_strategy: "winget" # winget | direct_url | skip
nvidia_telemetry_cleanup: true
```

## 4. Détail par fichier de tâches

### 4.1 `defender.yml`

**Approche** : on conserve `RealtimeMonitoring ON` (jamais désactivé) mais on désactive Tamper Protection + on injecte exclusions paths/processus + on coupe le cloud sample reporting.

**Tâches** :

1. **Tamper Protection — pré-requis manuel one-shot**
   - Tamper Protection ne se désactive plus via GPO/registre sur Win11 récent
   - `Set-MpPreference -DisableTamperProtection` peut échouer selon la version
   - **Stratégie** : Ansible _vérifie_ via `Get-MpComputerStatus`. Si `IsTamperProtected = $true`, la tâche échoue avec un message clair demandant la désactivation manuelle dans Windows Security UI une seule fois
   - Une fois désactivé, les tâches suivantes peuvent procéder
2. **Exclusions paths** : boucle sur `defender_exclusion_paths` → `Add-MpPreference -ExclusionPath`. Idempotent (le cmdlet est déjà idempotent côté MS).
3. **Exclusions processus** : boucle sur `defender_exclusion_processes` → `Add-MpPreference -ExclusionProcess`.
4. **Exclusions extensions** : boucle sur `defender_exclusion_extensions` → `Add-MpPreference -ExclusionExtension`.
5. **Cloud reporting** : `Set-MpPreference -MAPSReporting Disabled -SubmitSamplesConsent NeverSend`.

**Tag** : `defender`. **Reboot requis** : non.

---

### 4.2 `gaming_optim.yml`

**Approche** : tweaks bas-niveau OS, désactivation VBS + filet anti-update, Game DVR off.

**Sections** :

#### 4.2.1 VBS / HVCI désactivation

Clés registre :

```
HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard
  EnableVirtualizationBasedSecurity = 0
  RequirePlatformSecurityFeatures   = 0
HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity
  Enabled = 0
HKLM:\SYSTEM\CurrentControlSet\Control\Lsa
  LsaCfgFlags = 0
```

**Scheduled task de sécurité anti-update** créée via `community.windows.win_scheduled_task` :

- Nom : `VBS-Safety-Reset`
- Triggers : hebdomadaire (`{{ vbs_weekly_reset.day }}` à `{{ vbs_weekly_reset.time }}`) + au boot avec délai 5min
- Action : script PowerShell embedded qui relit les 5 clés ci-dessus et les remet à `0` si l'une d'elles est revenue à `1`
- Run as : `SYSTEM`, highest privileges, hidden
- Reboot : pas déclenché par la scheduled task, l'utilisateur peut redémarrer à son rythme

#### 4.2.2 Kernel / multimedia

```
HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile
  SystemResponsiveness     = {{ system_responsiveness }}
  NetworkThrottlingIndex   = {{ network_throttling_index }}
HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games
  GPU Priority             = 8
  Priority                 = 6
  Scheduling Category      = "High"
  SFIO Priority            = "High"
```

#### 4.2.3 Réseau — Nagle off sur le NIC gaming

Script PowerShell idempotent :

1. Récupère le NIC `Up` + `MediaType = '802.3'` (même filtre que la tâche WOL existante dans `system_settings.yml`)
2. Récupère son `InterfaceGuid`
3. Sous `HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{guid}`, écrit :
   - `TcpAckFrequency = 1`
   - `TCPNoDelay = 1`
   - `TcpDelAckTicks = 0`
4. Compare avant/après pour positionner `$Ansible.Changed` correctement

#### 4.2.4 Stockage / power

- `powercfg /h off` si `hibernation_enabled = false` (récupère ~32 GB sur Fanxiang)
- Page file via `Set-CimInstance Win32_PageFileSetting` selon `page_file.strategy` :
  - `fixed` : `InitialSize = page_file.initial_size_mb`, `MaximumSize = page_file.max_size_mb`, sur `C:\`
  - `system_managed` : `AutomaticManagedPagefile = $true`
  - `none` : pas de page file (déconseillé sauf 64+ GB RAM, à vérifier dans une future itération)
- USB selective suspend OFF :
  ```powershell
  powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 `
           48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
  powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 `
           48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
  powercfg /setactive SCHEME_CURRENT
  ```
- PCIe Link State Power Management OFF :
  ```powershell
  powercfg /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 `
           ee12f906-d277-404b-b6da-e5fa1a576df5 0
  ```

#### 4.2.5 Game DVR / Game Mode

```
# Game DVR (background recorder) OFF
HKCU:\System\GameConfigStore
  GameDVR_Enabled = 0
HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR
  AllowGameDVR = 0

# Game Mode ON
HKCU:\Software\Microsoft\GameBar
  AllowAutoGameMode    = 1
  AutoGameModeEnabled  = 1
```

Les clés `HKCU` sont écrites via `ansible_become_user: "{{ user_name }}"`.

**Tag** : `gaming_optim`. **Reboot requis** : oui si VBS vient d'être désactivé (changement de fact `reboot_required`).

---

### 4.3 `console_ux.yml`

**Approche** : éliminer tout ce qui rend Windows bavard / surveillant / intrusif. Surface d'attaque réduite + zéro interruption pendant le jeu.

#### 4.3.1 AppX bloatware étendu

`softwares_uninstall.yml` itère déjà sur une liste hardcodée de 19 packages. Le nouveau comportement :

- Le fichier `softwares_uninstall.yml` n'est **pas modifié**
- Nouvelle tâche dans `console_ux.yml` qui boucle sur `appx_bloatware_extended` avec le même module `ansible.windows.win_package: state=absent`
- À terme (hors scope de ce spec, à reprendre plus tard) on pourra fusionner les deux listes dans une var unique

#### 4.3.2 Cortana / Bing / Widgets / Start menu

Clés registre listées dans la Section 3 du brainstorming — pour mémo :

```
HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search
  AllowCortana = 0
HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search
  BingSearchEnabled = 0
  CortanaConsent = 0
HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer
  DisableSearchBoxSuggestions = 1
HKLM:\SOFTWARE\Policies\Microsoft\Dsh
  AllowNewsAndInterests = 0
HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer
  HideRecommendedSection = 1
HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced
  Start_TrackDocs = 0
  Start_TrackProgs = 0
```

#### 4.3.3 OneDrive — désinstallation complète

Script PowerShell `Uninstall-OneDrive` :

1. `taskkill /F /IM OneDrive.exe` (suppression idempotente : ignore le `not running`)
2. Détecte chemin de `OneDriveSetup.exe` selon architecture (`%SystemRoot%\System32\` ou `\SysWOW64\`)
3. `OneDriveSetup.exe /uninstall`
4. Suppression `%LocalAppData%\Microsoft\OneDrive`, `%ProgramData%\Microsoft OneDrive`, `%UserProfile%\OneDrive`
5. Retrait entrée Explorer namespace : `HKCU:\SOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}` → `System.IsPinnedToNameSpaceTree = 0`
6. Policy anti-réinstall : `HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive\DisableFileSyncNGSC = 1`

Script `$Ansible.Changed = $true` uniquement si OneDrive était présent au début.

#### 4.3.4 Edge — neutralisation

```
# Services
sc config edgeupdate                        start= disabled
sc config edgeupdatem                       start= disabled
sc config MicrosoftEdgeElevationService     start= disabled

# Policies
HKLM:\SOFTWARE\Policies\Microsoft\Edge
  StartupBoostEnabled              = 0
  BackgroundModeEnabled            = 0
  HideFirstRunExperience           = 1
  PersonalizationReportingEnabled  = 0
  EdgeShoppingAssistantEnabled     = 0
  ConfigureDoNotTrack              = 1
```

Suppression des raccourcis :

- Desktop : `Remove-Item *Edge*.lnk` dans `%PUBLIC%\Desktop` et `%USERPROFILE%\Desktop`
- Taskbar/Start : via COM `IShellLink` ou Unpin verb. Approche fragile, on l'enveloppe d'un `try { } catch { }` et on accepte un échec partiel.

#### 4.3.5 Firefox par défaut (Group Policy)

1. Template Jinja `firefox_default_associations.xml.j2` → rendu vers `C:\ProgramData\Microsoft\Windows\DefaultAssociations.xml` :
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <DefaultAssociations>
     <Association Identifier=".html"  ProgId="FirefoxHTML-308046B0AF4A39CB" ApplicationName="Firefox" />
     <Association Identifier=".htm"   ProgId="FirefoxHTML-308046B0AF4A39CB" ApplicationName="Firefox" />
     <Association Identifier=".shtml" ProgId="FirefoxHTML-308046B0AF4A39CB" ApplicationName="Firefox" />
     <Association Identifier=".xht"   ProgId="FirefoxHTML-308046B0AF4A39CB" ApplicationName="Firefox" />
     <Association Identifier=".xhtml" ProgId="FirefoxHTML-308046B0AF4A39CB" ApplicationName="Firefox" />
     <Association Identifier="http"   ProgId="FirefoxURL-308046B0AF4A39CB"  ApplicationName="Firefox" />
     <Association Identifier="https"  ProgId="FirefoxURL-308046B0AF4A39CB"  ApplicationName="Firefox" />
     <Association Identifier="ftp"    ProgId="FirefoxURL-308046B0AF4A39CB"  ApplicationName="Firefox" />
     <Association Identifier=".pdf"   ProgId="FirefoxHTML-308046B0AF4A39CB" ApplicationName="Firefox" />
   </DefaultAssociations>
   ```
2. Group Policy :
   ```
   HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
     DefaultAssociationsConfiguration = "C:\ProgramData\Microsoft\Windows\DefaultAssociations.xml"
   ```
3. **Limite** : effet appliqué au **prochain login utilisateur**, pas immédiatement après le run Ansible. Documenté.

#### 4.3.6 Telemetry minimum

```
HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection
  AllowTelemetry                              = 1
  DoNotShowFeedbackNotifications              = 1
HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo
  DisabledByGroupPolicy                       = 1
HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent
  DisableConsumerFeatures                     = 1
  DisableWindowsConsumerFeatures              = 1
  DisableTailoredExperiencesWithDiagnosticData = 1
```

Services en `disabled` (si présents — Win11 24H2 les a déjà retirés pour certains) : `DiagTrack`, `dmwappushservice`.

#### 4.3.7 Notifications / Background apps / Startup cleanup

```
# Notifications globales OFF
HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications
  ToastEnabled = 0
HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings
  NOC_GLOBAL_SETTING_TOASTS_ENABLED = 0

# Background apps : Force Deny global
HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy
  LetAppsRunInBackground = 2
```

**Startup apps cleanup — approche conservative** : boucle sur `startup_apps_disable` qui supprime les entrées correspondantes dans `HKCU:\...\Run` et `HKLM:\...\Run` (et leurs variantes `RunOnce`).

**Tag** : `console_ux`. **Reboot requis** : non (mais Firefox default attend le prochain login).

---

### 4.4 `drivers.yml`

#### 4.4.1 AMD chipset

Install via winget si absent. Détection via `winget list --id AdvancedMicroDevices.AMDChipsetDrivers --exact`.

#### 4.4.2 NVIDIA driver — stratégie A1-bis

Trois variantes via `nvidia_driver_install_strategy` :

| Valeur            | Comportement                                                                                                                                                                                                                                                       |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `winget` (défaut) | Install une seule fois si pas de driver NVIDIA détecté (`Get-PnpDevice -Class Display \| Where FriendlyName -match 'NVIDIA'`). Si absent → `winget install Nvidia.GeForceDriver --silent`. Si présent → skip (user gère les updates manuellement).                 |
| `direct_url`      | Fallback : 2 vars dédiées (`nvidia_driver_url` + `nvidia_driver_version`) consommées par une tâche `ansible.windows.win_get_url` puis `ansible.windows.win_package` avec `arguments: -s -clean`. Pattern identique aux autres softs dans `softwares_download.yml`. |
| `skip`            | Ansible ne touche jamais au driver.                                                                                                                                                                                                                                |

Le nettoyage telemetry NVIDIA tourne **toujours**, quelle que soit la stratégie.

#### 4.4.3 NVIDIA telemetry cleanup (à chaque run)

Services en `disabled` + `stopped` :

- `NvTelemetryContainer`
- `NvContainerLocalSystem`
- `NvContainerNetworkService`
- `NVDisplay.ContainerLocalSystem` (selon version driver)

`failed_when: false` partout pour ne pas planter si un service n'existe pas dans la version installée.

Scheduled task `NvTmRep_CrashReport` (recréé à chaque update driver) supprimé via `community.windows.win_scheduled_task: state=absent`.

**Tag** : `drivers`. **Reboot requis** : oui si install initial des drivers (set fact `reboot_required`).

---

### 4.5 `main.yml` — orchestration

Ajout en fin de fichier, après `Install MS Store / winget apps` :

```yaml
- name: Apply Windows Defender exclusions and tuning
  ansible.builtin.include_tasks: defender.yml
  tags: [system, defender]

- name: Apply gaming optimizations (VBS off, kernel, network, Game DVR)
  ansible.builtin.include_tasks: gaming_optim.yml
  tags: [system, gaming_optim]

- name: Apply console-style UX hardening
  ansible.builtin.include_tasks: console_ux.yml
  tags: [system, console_ux]

- name: Install and tune GPU/chipset drivers
  ansible.builtin.include_tasks: drivers.yml
  tags: [softwares, drivers]

- name: Reboot if any task flagged it
  ansible.windows.win_reboot:
    reboot_timeout: 600
    test_command: 'exit (Get-Service -Name WinRM).Status -ne "Running"'
  when: reboot_required | default(false)
```

Chaque sous-tâche critique (VBS, hibernation, drivers, hostname, page file) set `reboot_required: true` via `set_fact` quand `register.changed`. Un seul reboot final, jamais multiples.

### 4.6 `common` role — Firefox policies

Fichier `Ansible/roles/common/templates/firefox_policies.json` modifié pour :

- **Retirer** toute référence à Bitwarden (entrée `Extensions.Install`, `ExtensionSettings` ciblant Bitwarden, ou policy `Locked` associée). Identification précise au moment de l'implémentation par lecture du fichier.
- **Ajouter** KeePassXC-Browser :
  ```json
  "ExtensionSettings": {
    "keepassxc-browser@keepassxc.org": {
      "installation_mode": "force_installed",
      "install_url": "https://addons.mozilla.org/firefox/downloads/latest/keepassxc-browser/latest.xpi",
      "default_area": "navbar"
    }
  }
  ```

## 5. Tests & verification

### 5.1 Pre-flight (avant tout run réel)

```bash
make ping-windows                              # WinRM joignable ?
make check-windows ARGS='--tags console_ux'   # dry-run d'un sous-ensemble
```

### 5.2 Post-run verification

Nouveau playbook `Ansible/playbooks/verify_gaming_optim.yml` qui lit l'état système via `ansible.windows.win_powershell` et affiche un tableau récap :

| Vérification                    | Commande                                                                                                              |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Defender exclusions             | `Get-MpPreference \| Select ExclusionPath, MAPSReporting`                                                             |
| VBS désactivé                   | `Get-CimInstance Win32_DeviceGuard \| Select VirtualizationBasedSecurityStatus`                                       |
| Hibernation OFF                 | `powercfg /a` → contient "L'hibernation n'a pas été activée"                                                          |
| NVIDIA telemetry                | `Get-Service NvTelemetryContainer` → `Stopped` + `StartType: Disabled`                                                |
| AppX résiduels                  | `Get-AppxPackage \| Where Name -match 'Bing\|Cortana\|OneDrive\|DevHome'` → vide                                      |
| Firefox default policy          | `Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' DefaultAssociationsConfiguration` |
| Scheduled task VBS-Safety-Reset | `Get-ScheduledTask VBS-Safety-Reset`                                                                                  |

Nouvelle cible Makefile :

```makefile
verify-windows:
	./scripts/run.sh ansible-playbook playbooks/verify_gaming_optim.yml
```

### 5.3 Mesure d'impact (manuelle, hors-Ansible)

Pour vérifier objectivement le gain FPS / stutter, l'utilisateur peut :

1. **Avant run** : enregistrer 60 secondes de gameplay dans un benchmark de référence (CS2 FPS benchmark, Forza Horizon benchmark intégré) via Xbox Game Bar Win+G → noter min/avg/1% low FPS
2. **Après run** : refaire la même mesure dans les mêmes conditions
3. Comparer

Gains attendus typiques : **+3 à +12% FPS moyens**, **+15 à +25% sur les 1% low** (stutter), grâce surtout à VBS off + Defender exclusions + Game DVR off.

## 6. Rollback

Le rôle est **déclaratif et idempotent**. Pour revenir en arrière :

1. **Re-flipper la variable** dans `host_vars/aurelien-gaming/main.yml` (ex : `vbs_enabled: true`)
2. Re-runner `make windows` (ou `--tags gaming_optim` pour cibler)

**Exceptions où le rollback Ansible ne suffit pas** (nécessite intervention manuelle) :

- **OneDrive réinstall** : `winget install Microsoft.OneDrive`
- **AppX bloatware réinstall** : `winget install <app>` ou via Microsoft Store
- **Edge raccourcis re-pinned** : manuel
- **Tamper Protection re-activation** : Windows Security UI (manuel)

## 7. Risques & mitigations

| Risque                                      | Probabilité                      | Impact                             | Mitigation                                                                               |
| ------------------------------------------- | -------------------------------- | ---------------------------------- | ---------------------------------------------------------------------------------------- |
| Tamper Protection bloque `Set-MpPreference` | Moyenne                          | Defender exclusions pas appliquées | Vérif explicite avec message clair, désactivation manuelle one-shot puis Ansible reprend |
| WOL casse après hibernation OFF             | Faible                           | Pas de wake distant                | Pré-requis BIOS documentés Section 2. Fallback : `powercfg /h on`                        |
| Driver NVIDIA winget package indisponible   | Moyenne                          | Install échoue                     | Fallback `direct_url` documenté                                                          |
| Edge raccourci taskbar pas retiré           | Élevée                           | Cosmétique                         | Try/catch, échec partiel toléré                                                          |
| Firefox default policy ignorée après login  | Faible                           | http ouvre dans Edge               | Documenté, user fait "Set default" manuellement une fois si besoin                       |
| Update Windows 11 majeure réactive VBS      | Élevée (à chaque feature update) | Perte 5-15% FPS                    | Scheduled task `VBS-Safety-Reset` hebdomadaire + déclencheur au boot                     |
| `winget` absent ou en panne                 | Faible                           | Drivers pas installés              | `failed_when: false` sur les tâches winget, log clair, user installe manuellement        |

## 8. Hors scope (à explorer plus tard)

Volontairement laissés pour de futures itérations :

- **NVIDIA Control Panel settings** via registry (Power Mode, Low Latency Mode "Ultra", Threaded Optimization) — possible via `HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm` ou `nvidia-smi.exe`, mais clés non-publiques et instables
- **Audio low-latency** (WASAPI exclusive mode, désactivation des "audio enhancements") — non bloquant
- **Game-specific tweaks** (CS2 launch options, Forza shader cache pre-warming) — par-jeu, hors infrastructure
- **PBO / Curve Optimizer monitoring** via `HWiNFO` ou `Ryzen Master` — applicatif, pas système
- **Sync de la liste `bloatware_appx` actuelle avec `appx_bloatware_extended`** dans une variable unique — refactor cosmétique

## 9. Critères d'acceptation

Le spec est considéré complet quand :

1. `make check-windows ARGS='--tags gaming_optim,console_ux,defender,drivers'` ne lève **aucune erreur** lint/syntax
2. `make windows` complet sur `aurelien-gaming` aboutit sans erreur après au plus **un reboot**
3. `make verify-windows` confirme tous les états attendus de la Section 5.2
4. Un second `make windows` immédiatement après le premier annonce **0 changement** (idempotence)
5. Le rôle reste compatible avec `make windows ARGS='--skip-tags drivers,console_ux'` (subsets)

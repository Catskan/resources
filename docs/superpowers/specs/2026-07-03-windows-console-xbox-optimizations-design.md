# Consolisation Windows 11 « façon Xbox » — design

**Date** : 2026-07-03
**Cible** : hôte `aurelien-gaming` (Ryzen 7 9800X3D, Radeon RX 9070 XT 16 Go, 32 Go RAM, Win11 Pro, admin unique en autologon, hôte de streaming Sunshine).
**But** : pousser le PC au plus près d'une console Xbox (boot manette-first, zéro chrome Windows, comportement d'appareil, zéro maintenance visible) sans dégrader le rôle gaming ni la fiabilité.
**Issu de** : deep-research 3 agents (Xbox Full-Screen/Xbox mode, perf 9800X3D/RX 9070 XT, UX appareil-console), juillet 2026.

## Décisions figées

- **Modèle d'alimentation** : **veille S3 + WoL**. Réveil via WoL/Moonlight (magic packet déjà configuré), pas de réveil manette (BT coupé en S3). Bouton power → veille.
- **Shell** : garder le **FSE / « Xbox mode » natif** (déjà implémenté). PAS de Shell Launcher v2 / kiosk (Enterprise/IoT only, conflit avec autologon admin + UAC off). PAS de Steam Big Picture comme shell.
- **MPO** : NE PAS désactiver (`OverlayTestMode=5` ignoré sur 25H2 + peut augmenter la latence borderless). Tâche retirée.
- **Home app** : app Xbox (agrège déjà Steam/Epic/GOG/Battle.net in-shell en 2026).

## Batches à implémenter (Ansible, idempotent, gaté `aurelien-gaming`)

### Batch 1 — Xbox mode (fichier `xbox_mode.yml`, tag `xbox_mode`)

- ViVeTool feature flags `58989070,59765208` (débloque « Xbox mode » sans attendre le CFR ; conditionnel à la build, best-effort idempotent).
- Prompts enter/exit OFF : `HKCU\...\GamingConfiguration\SystemDialogResults\EnterGamingPostureConfirmation_NoReboot=1`, `ExitGamingPostureConfirmation_Minimal=1`.
- Task View : `GamingConfiguration\ShowOnDesktopSwitcher=1` + `GameBar\TaskSwitcherNexusInjectionEnabled=1`.
- Discipline : rejouer `--tags xbox_mode` après chaque feature update (DeviceForm non migré) — documenté.

### Batch 2 — Windows Update no-reboot (nouveau `windows_update.yml`, tag `wu_control`)

- `HKLM\...\WindowsUpdate\AU` : `NoAutoRebootWithLoggedOnUsers=1` + `AUOptions=4`.
- Pin version : `TargetReleaseVersion=1` + `TargetReleaseVersionInfo="{{ windows_feature_pin }}"` + `ProductVersion="Windows 11"`.
- `ExcludeWUDriversInQualityUpdate=1` (protège l'Adrenalin géré par `drivers.yml`).
- Désarmer la tâche planifiée `\Microsoft\Windows\UpdateOrchestrator\Reboot`.
- Reboot d'update planifié dimanche ~04:00 (fenêtre du `vbs_weekly_reset`), conditionné à `RebootRequired`.

### Batch 3 — Power/UX + lock screen (nouveau `power_ux.yml`, tag `power_ux`)

- Bouton power → veille : `powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 1`.
- Forcer S3 si le firmware l'expose : check `powercfg /a`, puis `HKLM\System\CurrentControlSet\Control\Power\PlatformAoAcOverride=0` (assert-guard si S3 absent).
- Lock screen off : `HKLM\...\Personalization\NoLockScreen=1` ; pas de mot de passe au réveil : `CONSOLELOCK=0` ; screensaver off.
- ARSO sans lock : `DisableAutomaticRestartSignOn=0` + `AutomaticRestartSignOnConfig=1`.
- Écran off sans veille système contradictoire : `monitor-timeout-ac 10`, `standby-timeout-ac` selon S3 (veille activée).
- Nags/spotlight (HKCU + HKLM) : SCOOBE off, ContentDeliveryManager (spotlight/tips/welcome), backup reminder, account notifications, first-logon animation off, startup sound off.

### Batch 4 — Perf sûres + asserts BIOS (fichier `gaming_optim.yml`, tag `gaming_optim`)

- NIC Realtek anti-éco : EEE/Green/Gigabit Lite/Flow Control/Interrupt Moderation off via `Set-NetAdapterAdvancedProperty` (best-effort, exécuté en dernier — reset lien).
- NTFS : `fsutil behavior set disablelastaccess 1`, `disable8dot3 1`, `8dot3name strip M:` (one-shot), query TRIM.
- `Win32PrioritySeparation=0x2A` (short/fixed/high boost — A/B testable, rollback `0x2`).
- Accélération souris off (HKCU `Control Panel\Mouse` MouseSpeed/Threshold=0).
- Asserts (vérif, pas de fix OS) : ReBAR/SAM actif, EXPO (ConfiguredClockSpeed ≥ 2800), write-cache E:/M:.

## BIOS / manuel (documenter dans `docs/CLAUDE-HANDOFF.md`)

- **ReBAR/SAM + EXPO** (gains perf majeurs), **Restore AC Power Loss = Last State**, **ErP Disabled** (sinon casse WoL), **PBO/Curve Optimizer** (campagne de test obligatoire).
- Adrenalin (non scriptable) : **Anti-Lag 2** + **Advanced Shader Delivery**.
- One-shot : Steam Input desktop layout (manette→souris hors shell), Gaming Copilot privacy off, POST/logo BIOS.

## Ne PAS faire

Core parking (mono-CCD), `disabledynamictick`, ISLC/purge standby, timer resolution forcée, MPO off, Shell Launcher/kiosk, blob CloudStore quiet-hours, policies WU legacy (no-op 25H2), spoof physpanel.

## Variables (group_vars `windows_hosts`)

Nouveaux toggles : `xbox_prompts_suppress`, `windows_update_no_reboot`, `windows_feature_pin` (ex. `"25H2"`), `wu_exclude_drivers`, `power_button_sleep`, `force_s3_sleep`, `lock_screen_disabled`, `nic_power_savings_off`, `ntfs_optimize`, `win32_priority_separation` (0x2A), `mouse_accel_off`. Aucun secret nouveau.

## Hors périmètre (parké)

Tag `ai` (nœud LLM LM Studio/Vulkan pour vinted-bot) : design séparé, en attente du chemin/ID exact du modèle. ComfyUI + PyTorch/ROCm : tag distinct éventuel.

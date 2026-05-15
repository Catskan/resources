# Windows 11 Gaming Optimization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform Windows 11 on `aurelien-gaming` into a console-like (Xbox-style) gaming OS via 4 new Ansible task files (defender, gaming_optim, console_ux, drivers), a Firefox extension swap in the `common` role, a verification playbook, and new tags.

**Architecture:** Pure additive layer on top of the existing `windows_gaming` role. The current `system_settings.yml`, `softwares_*.yml`, `ms_store_apps.yml`, `user_folders.yml` are untouched. Four new task files are dropped into `roles/windows_gaming/tasks/`, included from `main.yml` in a deterministic order (defender first to install AV exclusions before driver installs, drivers last so reboots happen once). Each new file has its own tag for selective execution. New variables live in `inventory/host_vars/aurelien-gaming/main.yml`. A new playbook `playbooks/verify_gaming_optim.yml` asserts state post-run.

**Tech Stack:**

- Ansible 2.x with `community.windows` + `ansible.windows` collections (already in use)
- `viczem.keepass` lookup plugin for secrets (already in use)
- PowerShell 5+ on the Windows target (built-in)
- yamllint + ansible-lint for local validation (`make lint`)
- WinRM transport (already configured)

**Reference spec:** `docs/superpowers/specs/2026-05-13-windows-gaming-optimization-design.md` (commit `5518363` on branch `feature/windows-gaming-optim-spec`)

**Branch strategy:** Implement on `feature/windows-gaming-optim-spec` (where the spec lives) — commits stack on top of the spec commit, the branch becomes the deliverable.

---

## Workflow: dual-loop testing

Because the target host (`aurelien-gaming`) may not be powered on during dev, every task has **two verify phases**:

- **Fast loop (always run, ~5s)** — `make lint` from `Ansible/` directory. Catches YAML/ansible-lint errors. Iterate here until clean.
- **Slow loop (run at phase boundaries, requires the PC on)** — `make check-windows ARGS='--tags <tag>'` then `make windows ARGS='--tags <tag>'` then `make verify-windows`. Validates real apply + idempotence.

Each task ends with a fast-loop verification and a commit. Slow-loop verifications happen at the end of each phase (after all tasks in a category are done).

---

## File Structure

### Files created

| Path                                                                         | Purpose                                                                                                                             |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `Ansible/roles/windows_gaming/tasks/defender.yml`                            | Microsoft Defender exclusions + cloud reporting OFF                                                                                 |
| `Ansible/roles/windows_gaming/tasks/gaming_optim.yml`                        | VBS OFF + scheduled task + kernel/network/storage tweaks + Game DVR/Mode                                                            |
| `Ansible/roles/windows_gaming/tasks/console_ux.yml`                          | Debloat: AppX, Cortana/Bing/Widgets, OneDrive, Edge neutralize, Firefox default, telemetry, notifications, background apps, startup |
| `Ansible/roles/windows_gaming/tasks/drivers.yml`                             | AMD chipset + NVIDIA driver install + NVIDIA telemetry cleanup                                                                      |
| `Ansible/roles/windows_gaming/templates/firefox_default_associations.xml.j2` | Firefox-as-default-browser XML for Group Policy                                                                                     |
| `Ansible/playbooks/verify_gaming_optim.yml`                                  | Reads system state, asserts target values, no changes                                                                               |

### Files modified

| Path                                                   | Change                                                                                      |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------- |
| `Ansible/roles/windows_gaming/tasks/main.yml`          | Add 4 include_tasks (defender, gaming_optim, console_ux, drivers) + final reboot block      |
| `Ansible/inventory/host_vars/aurelien-gaming/main.yml` | Add ~30 new variables (defender*\*, vbs*\_, hibernation\_\_, appx_bloatware_extended, etc.) |
| `Ansible/inventory/group_vars/all/main.yml`            | Add `firefox_extension_id_keepassxc`                                                        |
| `Ansible/roles/common/templates/firefox_policies.json` | Add KeePassXC extension entry (no Bitwarden to remove — confirmed not present)              |
| `Ansible/Makefile`                                     | Add `verify-windows` target + help entry                                                    |
| `CLAUDE.md`                                            | Add new tags to the table in "Tags (rôle `windows_gaming`)" section                         |

---

## Phase 0 — Foundation

### Task 1: Add new variables to `host_vars/aurelien-gaming/main.yml`

**Files:**

- Modify: `Ansible/inventory/host_vars/aurelien-gaming/main.yml` (append at end)

- [ ] **Step 1: Open the file and append the new variables**

Append at the end of `Ansible/inventory/host_vars/aurelien-gaming/main.yml`:

```yaml
# ============================================================================
# Gaming optimization vars — see docs/superpowers/specs/2026-05-13-windows-gaming-optimization-design.md
# ============================================================================

# --- Defender (defender.yml) ---
defender_exclusion_paths:
  - 'C:\Program Files (x86)\Steam\steamapps'
  - 'C:\Program Files\Epic Games'
  - 'C:\Program Files (x86)\GOG Galaxy\Games'
  - 'C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\games'
  - 'C:\Program Files\WindowsApps'
  - 'C:\XboxGames'
  - 'C:\Program Files\ModifiableWindowsApps'
  - 'M:\'
  - 'M:\XboxGames'
defender_exclusion_processes:
  - steam.exe
  - EpicGamesLauncher.exe
  - GalaxyClient.exe
  - UbisoftConnect.exe
  - gamingservices.exe
  - XboxAppServices.exe
  - GameBar.exe
defender_exclusion_extensions:
  - .dxvk-cache
  - .cache
  - .pak
defender_maps_reporting: Disabled
defender_submit_samples: NeverSend

# --- VBS / HVCI (gaming_optim.yml) ---
vbs_enabled: false
vbs_weekly_reset:
  enabled: true
  day: SUN # MON, TUE, WED, THU, FRI, SAT, SUN
  time: "04:00"

# --- Kernel & multimedia (gaming_optim.yml) ---
system_responsiveness: 0
network_throttling_index: 0xFFFFFFFF
nagle_disable_on_gaming_nic: true

# --- Storage & power (gaming_optim.yml) ---
hibernation_enabled: false
page_file:
  strategy: fixed # fixed | system_managed
  initial_size_mb: 32768
  max_size_mb: 49152
usb_selective_suspend: false
pcie_link_state_power_off: true

# --- Game DVR / Mode (gaming_optim.yml) ---
game_dvr_disabled: true
game_mode_enabled: true

# --- AppX bloatware extended (console_ux.yml) ---
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

# --- Console UX policies (console_ux.yml) ---
cortana_disabled: true
bing_search_disabled: true
widgets_disabled: true
onedrive_uninstall: true
edge_neutralize: true
notifications_globally_off: true
background_apps_force_deny: true
recommended_files_off: true
startup_apps_disable:
  - MSEdgeUpdate
  - "Adobe ARM"
  - iTunesHelper
  - iCloudDrive
  - Cortana
telemetry_minimum: true
firefox_set_default: true

# --- Drivers (drivers.yml) ---
amd_chipset_install: true
nvidia_driver_install_strategy: winget # winget | direct_url | skip
nvidia_telemetry_cleanup: true
# Used only when nvidia_driver_install_strategy == "direct_url"
nvidia_driver_url: ""
nvidia_driver_version: ""
```

- [ ] **Step 2: Validate YAML syntax**

Run from `Ansible/`:

```bash
make lint
```

Expected: `0` errors. If yamllint complains about lines >80 chars, accept that (the file uses long lines already).

- [ ] **Step 3: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/inventory/host_vars/aurelien-gaming/main.yml
git commit -m "Add gaming optimization variables to aurelien-gaming host_vars

Adds the ~30 variables consumed by the four upcoming task files
(defender.yml, gaming_optim.yml, console_ux.yml, drivers.yml).
No behavior change yet — variables are not referenced anywhere.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Create verify playbook scaffold and Makefile target

**Files:**

- Create: `Ansible/playbooks/verify_gaming_optim.yml`
- Modify: `Ansible/Makefile`

- [ ] **Step 1: Create the verify playbook scaffold**

Create `Ansible/playbooks/verify_gaming_optim.yml`:

```yaml
---
# Vérifie l'état post-run des optimisations gaming.
# Aucune modification — uniquement des assertions et des prints d'état.
#
# Usage : make verify-windows
#
# Si une vérification échoue, le playbook plante et affiche ce qui manque.
# Tags par catégorie : defender, gaming_optim, console_ux, drivers, all.

- name: Verify Windows 11 gaming optimization state
  hosts: aurelien-gaming
  gather_facts: true

  tasks:
    - name: Header
      ansible.builtin.debug:
        msg: "=== Verifying gaming optimizations on {{ inventory_hostname }} ==="
      tags: [all]
```

- [ ] **Step 2: Add `verify-windows` target to Makefile**

Edit `Ansible/Makefile`. First, locate the `.PHONY` line near the top:

```makefile
.PHONY: help windows linux uninstall-bloat ping-windows check-windows check-linux test-keepass inspect-keepass lint
```

Change to:

```makefile
.PHONY: help windows linux uninstall-bloat ping-windows check-windows check-linux test-keepass inspect-keepass verify-windows lint
```

Then locate the `help:` block and add this line after `make test-keepass`:

```makefile
	@echo "  make verify-windows   — Vérifie l'état post-run des optimisations gaming (offline)"
```

Then locate the `test-keepass:` target and add after it:

```makefile
verify-windows:
	./scripts/run.sh ansible-playbook playbooks/verify_gaming_optim.yml $(ARGS)
```

- [ ] **Step 3: Validate**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
ansible-playbook --syntax-check playbooks/verify_gaming_optim.yml
make lint
```

Expected: syntax-check returns `playbook: playbooks/verify_gaming_optim.yml`. Lint passes.

- [ ] **Step 4: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/playbooks/verify_gaming_optim.yml Ansible/Makefile
git commit -m "Add verify_gaming_optim playbook scaffold and Makefile target

Empty playbook structure — verification tasks per category will be
appended as each gaming optim file is implemented. Makefile gets
'verify-windows' target wired via the existing scripts/run.sh wrapper.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 1 — Defender

### Task 3: Implement `defender.yml` + wire into main.yml + verify

**Files:**

- Create: `Ansible/roles/windows_gaming/tasks/defender.yml`
- Modify: `Ansible/roles/windows_gaming/tasks/main.yml`
- Modify: `Ansible/playbooks/verify_gaming_optim.yml`

- [ ] **Step 1: Create `defender.yml`**

Create `Ansible/roles/windows_gaming/tasks/defender.yml`:

```yaml
---
# Microsoft Defender — keep real-time monitoring ON, but exclude game paths
# and disable cloud sample reporting. Tamper Protection must be disabled
# manually one-shot in Windows Security before this file can fully apply.
# See spec §4.1.

- name: Check whether Tamper Protection is enabled
  ansible.windows.win_powershell:
    script: |
      $status = Get-MpComputerStatus
      $Ansible.Result = @{ tamper_protected = [bool]$status.IsTamperProtected }
  register: defender_tamper_status

- name: Fail with clear message if Tamper Protection is still ON
  ansible.builtin.fail:
    msg: >-
      Tamper Protection is ON. Disable it manually in Windows Security
      → Virus & threat protection → Manage settings → Tamper Protection (OFF),
      then re-run this playbook. Defender exclusions cannot be applied while
      Tamper Protection is active.
  when: defender_tamper_status.result.tamper_protected | bool

- name: Add Defender path exclusions
  ansible.windows.win_powershell:
    script: |
      $existing = @((Get-MpPreference).ExclusionPath)
      $changed = $false
      foreach ($p in @({{ defender_exclusion_paths | map('to_json') | join(', ') }})) {
        if ($existing -notcontains $p) {
          Add-MpPreference -ExclusionPath $p
          $changed = $true
        }
      }
      $Ansible.Changed = $changed

- name: Add Defender process exclusions
  ansible.windows.win_powershell:
    script: |
      $existing = @((Get-MpPreference).ExclusionProcess)
      $changed = $false
      foreach ($p in @({{ defender_exclusion_processes | map('to_json') | join(', ') }})) {
        if ($existing -notcontains $p) {
          Add-MpPreference -ExclusionProcess $p
          $changed = $true
        }
      }
      $Ansible.Changed = $changed

- name: Add Defender extension exclusions
  ansible.windows.win_powershell:
    script: |
      $existing = @((Get-MpPreference).ExclusionExtension)
      $changed = $false
      foreach ($p in @({{ defender_exclusion_extensions | map('to_json') | join(', ') }})) {
        if ($existing -notcontains $p) {
          Add-MpPreference -ExclusionExtension $p
          $changed = $true
        }
      }
      $Ansible.Changed = $changed

- name: Configure Defender cloud reporting (off)
  ansible.windows.win_powershell:
    script: |
      $pref = Get-MpPreference
      $changed = $false
      if ($pref.MAPSReporting -ne '{{ defender_maps_reporting }}') {
        Set-MpPreference -MAPSReporting {{ defender_maps_reporting }}
        $changed = $true
      }
      if ($pref.SubmitSamplesConsent -ne '{{ defender_submit_samples }}') {
        Set-MpPreference -SubmitSamplesConsent {{ defender_submit_samples }}
        $changed = $true
      }
      $Ansible.Changed = $changed
```

- [ ] **Step 2: Wire into `main.yml`**

Edit `Ansible/roles/windows_gaming/tasks/main.yml`. Append at the very end (after `Install MS Store / winget apps`):

```yaml
- name: Apply Windows Defender exclusions and tuning
  ansible.builtin.include_tasks: defender.yml
  tags: [system, defender]
```

- [ ] **Step 3: Append Defender verification block to `verify_gaming_optim.yml`**

Edit `Ansible/playbooks/verify_gaming_optim.yml`. Append before the closing of the `tasks:` list (so still under the same `- name: Verify Windows 11 ...` play):

```yaml
- name: Verify Defender exclusions and reporting
  ansible.windows.win_powershell:
    script: |
      $pref = Get-MpPreference
      $Ansible.Result = @{
        paths        = $pref.ExclusionPath
        processes    = $pref.ExclusionProcess
        extensions   = $pref.ExclusionExtension
        maps         = [string]$pref.MAPSReporting
        samples      = [string]$pref.SubmitSamplesConsent
        realtime_on  = -not $pref.DisableRealtimeMonitoring
      }
  register: defender_verify
  tags: [defender, all]

- name: Assert Defender state matches spec
  ansible.builtin.assert:
    that:
      - "(defender_exclusion_paths | difference(defender_verify.result.paths | default([]))) | length == 0"
      - "(defender_exclusion_processes | difference(defender_verify.result.processes | default([]))) | length == 0"
      - "(defender_exclusion_extensions | difference(defender_verify.result.extensions | default([]))) | length == 0"
      - "defender_verify.result.maps == defender_maps_reporting"
      - "defender_verify.result.samples == defender_submit_samples"
      - "defender_verify.result.realtime_on"
    fail_msg: "Defender state mismatch — see defender_verify.result above"
    success_msg: "Defender exclusions and reporting OK"
  tags: [defender, all]
```

- [ ] **Step 4: Validate locally**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
ansible-playbook --syntax-check main_windows_playbook.yml
ansible-playbook --syntax-check playbooks/verify_gaming_optim.yml
```

Expected: 0 lint errors, both syntax-check return their playbook paths.

- [ ] **Step 5: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/roles/windows_gaming/tasks/defender.yml \
        Ansible/roles/windows_gaming/tasks/main.yml \
        Ansible/playbooks/verify_gaming_optim.yml
git commit -m "Add defender.yml — Microsoft Defender exclusions and cloud reporting OFF

Real-time monitoring stays ON. Adds path/process/extension exclusions
for Steam, Epic, GOG, Ubisoft, Xbox apps, M:\\ and game-related processes.
Disables MAPS reporting and sample submission. Wired into main.yml under
tags [system, defender]. Verify playbook gets a Defender block.

Tamper Protection must be disabled manually one-shot — playbook fails
with a clear message if not.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 2 — Gaming Optim (split across 4 tasks for clarity)

### Task 4: gaming_optim.yml — VBS off + weekly safety-reset scheduled task

**Files:**

- Create: `Ansible/roles/windows_gaming/tasks/gaming_optim.yml`

- [ ] **Step 1: Create the file with VBS section**

Create `Ansible/roles/windows_gaming/tasks/gaming_optim.yml`:

```yaml
---
# Gaming optim — VBS/HVCI OFF, kernel/network/storage tweaks, Game DVR OFF,
# Game Mode ON. See spec §4.2.
#
# This file is split conceptually:
#   §4.2.1 VBS / HVCI            ← below
#   §4.2.2 Kernel / multimedia   ← Task 5
#   §4.2.3 Network (Nagle)       ← Task 5
#   §4.2.4 Storage / power       ← Task 6
#   §4.2.5 Game DVR / Mode       ← Task 7
# Order matters: VBS reboot, then kernel, then storage, then user-level.

# ======================== §4.2.1 VBS / HVCI ========================

- name: VBS — disable EnableVirtualizationBasedSecurity
  ansible.windows.win_regedit:
    path: HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard
    name: EnableVirtualizationBasedSecurity
    data: "{{ 1 if vbs_enabled else 0 }}"
    type: dword
  register: vbs_key1

- name: VBS — disable RequirePlatformSecurityFeatures
  ansible.windows.win_regedit:
    path: HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard
    name: RequirePlatformSecurityFeatures
    data: "{{ 1 if vbs_enabled else 0 }}"
    type: dword
  register: vbs_key2

- name: VBS — disable HypervisorEnforcedCodeIntegrity
  ansible.windows.win_regedit:
    path: HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity
    name: Enabled
    data: "{{ 1 if vbs_enabled else 0 }}"
    type: dword
  register: vbs_key3

- name: VBS — disable Credential Guard (LsaCfgFlags)
  ansible.windows.win_regedit:
    path: HKLM:\SYSTEM\CurrentControlSet\Control\Lsa
    name: LsaCfgFlags
    data: "{{ 1 if vbs_enabled else 0 }}"
    type: dword
  register: vbs_key4

- name: Flag reboot if any VBS key changed
  ansible.builtin.set_fact:
    reboot_required: true
  when: vbs_key1.changed or vbs_key2.changed or vbs_key3.changed or vbs_key4.changed

- name: Create VBS-Safety-Reset weekly scheduled task
  community.windows.win_scheduled_task:
    name: VBS-Safety-Reset
    description: Re-disable VBS/HVCI keys after Windows updates may have re-enabled them.
    state: present
    enabled: "{{ vbs_weekly_reset.enabled }}"
    username: SYSTEM
    run_level: highest
    hidden: true
    triggers:
      - type: weekly
        days_of_week: "{{ vbs_weekly_reset.day }}"
        start_boundary: "2026-01-01T{{ vbs_weekly_reset.time }}:00"
      - type: boot
        delay: PT5M
    actions:
      - path: powershell.exe
        arguments: >-
          -NoProfile -ExecutionPolicy Bypass -Command "
          $keys = @(
            @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name='EnableVirtualizationBasedSecurity'},
            @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; Name='RequirePlatformSecurityFeatures'},
            @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; Name='Enabled'},
            @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name='LsaCfgFlags'}
          );
          foreach ($k in $keys) {
            try { Set-ItemProperty -Path $k.Path -Name $k.Name -Value 0 -Type DWord -ErrorAction Stop }
            catch { }
          }"
```

- [ ] **Step 2: Validate**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
ansible-playbook --syntax-check main_windows_playbook.yml
```

Expected: pass.

- [ ] **Step 3: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/roles/windows_gaming/tasks/gaming_optim.yml
git commit -m "Add gaming_optim.yml §4.2.1 — VBS off + weekly safety-reset task

Disables EnableVirtualizationBasedSecurity, RequirePlatformSecurityFeatures,
HypervisorEnforcedCodeIntegrity, LsaCfgFlags. Sets reboot_required fact when
any key changes. Creates VBS-Safety-Reset scheduled task (weekly + boot
trigger) that re-zeros the keys if a Windows update flips them back on.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: gaming_optim.yml — kernel multimedia + Nagle off on gaming NIC

**Files:**

- Modify: `Ansible/roles/windows_gaming/tasks/gaming_optim.yml` (append)

- [ ] **Step 1: Append kernel/multimedia + Nagle sections**

Append to `Ansible/roles/windows_gaming/tasks/gaming_optim.yml`:

```yaml
# ======================== §4.2.2 Kernel / multimedia ========================

- name: Kernel — SystemResponsiveness
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile
    name: SystemResponsiveness
    data: "{{ system_responsiveness }}"
    type: dword

- name: Kernel — NetworkThrottlingIndex
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile
    name: NetworkThrottlingIndex
    data: "{{ network_throttling_index }}"
    type: dword

- name: Multimedia Games task — GPU Priority
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games
    name: GPU Priority
    data: 8
    type: dword

- name: Multimedia Games task — Priority
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games
    name: Priority
    data: 6
    type: dword

- name: Multimedia Games task — Scheduling Category
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games
    name: Scheduling Category
    data: High
    type: string

- name: Multimedia Games task — SFIO Priority
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games
    name: SFIO Priority
    data: High
    type: string

# ======================== §4.2.3 Network (Nagle OFF) ========================

- name: Network — disable Nagle on all Ethernet NICs (Up + 802.3)
  # Applies to all 802.3 adapters Up — same selection pattern as the WOL task
  # in system_settings.yml. On the B850 Max Gaming Wifi W there's only one
  # Ethernet port (Realtek 8125 2.5GbE). The WiFi NIC is excluded because
  # its MediaType is 'Native 802.11', not '802.3'.
  ansible.windows.win_powershell:
    script: |
      $changed = $false
      $touched = @()
      $adapters = Get-NetAdapter -Physical |
        Where-Object { $_.Status -eq 'Up' -and $_.MediaType -eq '802.3' }
      if (-not $adapters) {
        $Ansible.Result = @{ message = 'No Ethernet adapter Up'; touched = @() }
        return
      }
      $desired = @{ TcpAckFrequency = 1; TCPNoDelay = 1; TcpDelAckTicks = 0 }
      foreach ($a in $adapters) {
        $guid = $a.InterfaceGuid
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
        $adapterChanged = $false
        foreach ($name in $desired.Keys) {
          $current = (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name
          if ($current -ne $desired[$name]) {
            Set-ItemProperty -Path $path -Name $name -Value $desired[$name] -Type DWord
            $adapterChanged = $true
          }
        }
        if ($adapterChanged) { $changed = $true }
        $touched += @{ name = $a.Name; speed = [string]$a.LinkSpeed; guid = $guid; changed = $adapterChanged }
      }
      $Ansible.Changed = $changed
      $Ansible.Result = @{ touched = $touched }
  when: nagle_disable_on_gaming_nic
```

- [ ] **Step 2: Validate**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
```

- [ ] **Step 3: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/roles/windows_gaming/tasks/gaming_optim.yml
git commit -m "Add gaming_optim.yml §4.2.2-4.2.3 — kernel multimedia + Nagle off

SystemResponsiveness=0, NetworkThrottlingIndex=0xFFFFFFFF,
Games task priorities. Nagle's algorithm disabled on the Ethernet NIC
(same selection logic as the WOL task in system_settings.yml).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: gaming_optim.yml — storage and power tweaks (hibernation, page file, USB, PCIe)

**Files:**

- Modify: `Ansible/roles/windows_gaming/tasks/gaming_optim.yml` (append)

- [ ] **Step 1: Append storage/power section**

Append to `gaming_optim.yml`:

```yaml
# ======================== §4.2.4 Storage / power ========================

- name: Storage — disable hibernation
  ansible.windows.win_powershell:
    script: |
      $info = powercfg /a
      $hibern = ($info -join ' ') -match 'L''hibernation a été activée|Hibernation has been enabled'
      if ($hibern) {
        powercfg /h off
        $Ansible.Changed = $true
      }
  when: not hibernation_enabled

- name: Storage — configure fixed page file
  ansible.windows.win_powershell:
    script: |
      $changed = $false
      $cs = Get-CimInstance Win32_ComputerSystem
      if ($cs.AutomaticManagedPagefile) {
        Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false } | Out-Null
        $changed = $true
      }
      $pf = Get-CimInstance Win32_PageFileSetting -Filter "Name like 'C:%'"
      $desiredInit = {{ page_file.initial_size_mb }}
      $desiredMax  = {{ page_file.max_size_mb }}
      if ($null -eq $pf) {
        New-CimInstance -ClassName Win32_PageFileSetting -Property @{
          Name = 'C:\pagefile.sys'; InitialSize = $desiredInit; MaximumSize = $desiredMax
        } | Out-Null
        $changed = $true
      } elseif ($pf.InitialSize -ne $desiredInit -or $pf.MaximumSize -ne $desiredMax) {
        Set-CimInstance -InputObject $pf -Property @{ InitialSize = $desiredInit; MaximumSize = $desiredMax } | Out-Null
        $changed = $true
      }
      $Ansible.Changed = $changed
  when: page_file.strategy == 'fixed'

- name: Power — disable USB selective suspend
  ansible.windows.win_powershell:
    script: |
      # GUIDs documented in powercfg /q output
      $sub  = '2a737441-1930-4402-8d77-b2bebba308a3'  # USB settings
      $set  = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'  # USB selective suspend
      powercfg /setacvalueindex SCHEME_CURRENT $sub $set 0
      powercfg /setdcvalueindex SCHEME_CURRENT $sub $set 0
      powercfg /setactive SCHEME_CURRENT
      $Ansible.Changed = $true   # idempotent in effect; powercfg is silent
  when: not usb_selective_suspend
  changed_when: false

- name: Power — disable PCIe Link State Power Management
  ansible.windows.win_powershell:
    script: |
      $sub  = '501a4d13-42af-4429-9fd1-a8218c268e20'  # PCI Express
      $set  = 'ee12f906-d277-404b-b6da-e5fa1a576df5'  # Link State Power Mgmt
      powercfg /setacvalueindex SCHEME_CURRENT $sub $set 0
      powercfg /setactive SCHEME_CURRENT
      $Ansible.Changed = $true
  when: pcie_link_state_power_off
  changed_when: false
```

- [ ] **Step 2: Validate**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
```

- [ ] **Step 3: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/roles/windows_gaming/tasks/gaming_optim.yml
git commit -m "Add gaming_optim.yml §4.2.4 — hibernation/pagefile/USB/PCIe tweaks

Disables hibernation (frees ~32 GB on Fanxiang). Sets fixed page file
on C:\\ at 32 GB initial / 48 GB max. USB selective suspend OFF (anti
peripheral disconnects). PCIe Link State Power Mgmt OFF.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: gaming_optim.yml — Game DVR off / Game Mode on + wire into main.yml + verify

**Files:**

- Modify: `Ansible/roles/windows_gaming/tasks/gaming_optim.yml` (append)
- Modify: `Ansible/roles/windows_gaming/tasks/main.yml`
- Modify: `Ansible/playbooks/verify_gaming_optim.yml`

- [ ] **Step 1: Append Game DVR / Game Mode section**

Append to `gaming_optim.yml`:

```yaml
# ======================== §4.2.5 Game DVR / Mode ========================

- name: Game DVR — HKLM policy off
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR
    name: AllowGameDVR
    data: "{{ 0 if game_dvr_disabled else 1 }}"
    type: dword

- name: Game DVR & Mode — HKCU (user-level)
  ansible.windows.win_powershell:
    script: |
      $changed = $false
      $entries = @(
        @{Path='HKCU:\System\GameConfigStore';                Name='GameDVR_Enabled';         Value={{ 0 if game_dvr_disabled else 1 }}},
        @{Path='HKCU:\Software\Microsoft\GameBar';            Name='AllowAutoGameMode';        Value={{ 1 if game_mode_enabled else 0 }}},
        @{Path='HKCU:\Software\Microsoft\GameBar';            Name='AutoGameModeEnabled';      Value={{ 1 if game_mode_enabled else 0 }}}
      )
      foreach ($e in $entries) {
        if (-not (Test-Path $e.Path)) { New-Item -Path $e.Path -Force | Out-Null }
        $cur = (Get-ItemProperty -Path $e.Path -Name $e.Name -ErrorAction SilentlyContinue).($e.Name)
        if ($cur -ne $e.Value) {
          Set-ItemProperty -Path $e.Path -Name $e.Name -Value $e.Value -Type DWord
          $changed = $true
        }
      }
      $Ansible.Changed = $changed
  vars:
    ansible_become: true
    ansible_become_method: runas
    ansible_become_user: "{{ user_name }}"
    ansible_become_pass: "{{ ansible_password }}"
```

- [ ] **Step 2: Wire into `main.yml`**

Edit `Ansible/roles/windows_gaming/tasks/main.yml`. Append after the Defender include from Task 3:

```yaml
- name: Apply gaming optimizations (VBS off, kernel, network, Game DVR)
  ansible.builtin.include_tasks: gaming_optim.yml
  tags: [system, gaming_optim]
```

- [ ] **Step 3: Append gaming_optim verification block to verify_gaming_optim.yml**

Append before the closing of the `tasks:` list:

```yaml
- name: Verify VBS / DeviceGuard status
  ansible.windows.win_powershell:
    script: |
      $dg = Get-CimInstance -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
      $vbs_running = ($dg.VirtualizationBasedSecurityStatus -eq 2)
      $hvci_running = ($dg.SecurityServicesRunning -contains 2)
      $sched = Get-ScheduledTask -TaskName 'VBS-Safety-Reset' -ErrorAction SilentlyContinue
      $Ansible.Result = @{
        vbs_running  = [bool]$vbs_running
        hvci_running = [bool]$hvci_running
        sched_exists = [bool]$sched
      }
  register: vbs_verify
  tags: [gaming_optim, all]

- name: Assert VBS state matches spec
  ansible.builtin.assert:
    that:
      - vbs_verify.result.vbs_running == vbs_enabled
      - vbs_verify.result.hvci_running == vbs_enabled
      - vbs_verify.result.sched_exists == vbs_weekly_reset.enabled
    fail_msg: "VBS state mismatch — got {{ vbs_verify.result }}"
    success_msg: "VBS state OK"
  tags: [gaming_optim, all]

- name: Verify kernel multimedia keys
  ansible.windows.win_powershell:
    script: |
      $base = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
      $Ansible.Result = @{
        sys_resp = (Get-ItemProperty -Path $base -Name SystemResponsiveness -ErrorAction SilentlyContinue).SystemResponsiveness
        throttle = (Get-ItemProperty -Path $base -Name NetworkThrottlingIndex -ErrorAction SilentlyContinue).NetworkThrottlingIndex
      }
  register: kernel_verify
  tags: [gaming_optim, all]

- name: Assert kernel multimedia keys match spec
  ansible.builtin.assert:
    that:
      - kernel_verify.result.sys_resp == system_responsiveness
      - kernel_verify.result.throttle == network_throttling_index
    fail_msg: "Kernel multimedia keys mismatch — got {{ kernel_verify.result }}"
    success_msg: "Kernel multimedia OK"
  tags: [gaming_optim, all]

- name: Verify hibernation disabled
  ansible.windows.win_powershell:
    script: |
      $out = (powercfg /a) -join ' '
      $Ansible.Result = @{ hibernation_disabled = $out -match "L'hibernation n'a pas été activée|Hibernation has not been enabled" }
  register: hibern_verify
  tags: [gaming_optim, all]

- name: Assert hibernation status matches spec
  ansible.builtin.assert:
    that:
      - hibern_verify.result.hibernation_disabled == (not hibernation_enabled)
    fail_msg: "Hibernation state mismatch — got {{ hibern_verify.result }}"
    success_msg: "Hibernation state OK"
  tags: [gaming_optim, all]
```

- [ ] **Step 4: Validate**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
ansible-playbook --syntax-check main_windows_playbook.yml
ansible-playbook --syntax-check playbooks/verify_gaming_optim.yml
```

- [ ] **Step 5: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/roles/windows_gaming/tasks/gaming_optim.yml \
        Ansible/roles/windows_gaming/tasks/main.yml \
        Ansible/playbooks/verify_gaming_optim.yml
git commit -m "Complete gaming_optim.yml §4.2.5 + wire main.yml + verify

Game DVR off (HKLM policy + HKCU user-level), Game Mode on (HKCU under
become_user). Wires gaming_optim.yml into main.yml under tags
[system, gaming_optim]. Verify playbook gets VBS / kernel / hibernation
assertion blocks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 3 — Console UX (split across 6 tasks)

### Task 8: console_ux.yml — AppX bloatware extended uninstall

**Files:**

- Create: `Ansible/roles/windows_gaming/tasks/console_ux.yml`

- [ ] **Step 1: Create console_ux.yml with the AppX section**

Create `Ansible/roles/windows_gaming/tasks/console_ux.yml`:

```yaml
---
# Console-style UX hardening — debloat, debrand, deinterrupt.
# See spec §4.3.
#
# Conceptual split:
#   §4.3.1 AppX bloatware extended    ← below
#   §4.3.2 Cortana / Bing / Widgets    ← Task 9
#   §4.3.3 OneDrive uninstall          ← Task 10
#   §4.3.4 Edge neutralization         ← Task 11
#   §4.3.5 Firefox default             ← Task 12
#   §4.3.6 Telemetry minimum           ← Task 13
#   §4.3.7 Notifications/bg/startup    ← Task 13

# ======================== §4.3.1 AppX bloatware extended ========================

- name: Uninstall extended AppX bloatware
  ansible.windows.win_powershell:
    script: |
      $names = @({{ appx_bloatware_extended | map('to_json') | join(', ') }})
      $changed = $false
      foreach ($n in $names) {
        $pkg = Get-AppxPackage -AllUsers -Name "*$n*" -ErrorAction SilentlyContinue
        if ($pkg) {
          $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
          $prov = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*$n*"
          if ($prov) {
            $prov | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
          }
          $changed = $true
        }
      }
      $Ansible.Changed = $changed
```

- [ ] **Step 2: Validate**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
```

- [ ] **Step 3: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/roles/windows_gaming/tasks/console_ux.yml
git commit -m "Add console_ux.yml §4.3.1 — extended AppX bloatware uninstall

Removes Cortana, Bing search, Sticky Notes, Mixed Reality, Wallet,
Mail/Calendar (WindowsCommunicationsApps), Quick Assist, new Outlook,
Dev Home — also unprovisions them so new users don't get them either.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: console_ux.yml — Cortana / Bing / Widgets / Start menu policies

**Files:**

- Modify: `Ansible/roles/windows_gaming/tasks/console_ux.yml` (append)

- [ ] **Step 1: Append the policy keys section**

Append to `console_ux.yml`:

```yaml
# ======================== §4.3.2 Cortana / Bing / Widgets / Start menu ========================

- name: Cortana — disable via Windows Search policy
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search
    name: AllowCortana
    data: "{{ 0 if cortana_disabled else 1 }}"
    type: dword

- name: Widgets — disable News and Interests
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Policies\Microsoft\Dsh
    name: AllowNewsAndInterests
    data: "{{ 0 if widgets_disabled else 1 }}"
    type: dword

- name: Start menu — hide Recommended section
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer
    name: HideRecommendedSection
    data: "{{ 1 if recommended_files_off else 0 }}"
    type: dword

- name: Bing search / Cortana / recommendations (HKCU per-user)
  ansible.windows.win_powershell:
    script: |
      $changed = $false
      $entries = @(
        @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Search';                Name='BingSearchEnabled';         Value={{ 0 if bing_search_disabled else 1 }}},
        @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Search';                Name='CortanaConsent';             Value={{ 0 if cortana_disabled else 1 }}},
        @{Path='HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer';                    Name='DisableSearchBoxSuggestions'; Value={{ 1 if bing_search_disabled else 0 }}},
        @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';     Name='Start_TrackDocs';             Value={{ 0 if recommended_files_off else 1 }}},
        @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';     Name='Start_TrackProgs';            Value={{ 0 if recommended_files_off else 1 }}}
      )
      foreach ($e in $entries) {
        if (-not (Test-Path $e.Path)) { New-Item -Path $e.Path -Force | Out-Null }
        $cur = (Get-ItemProperty -Path $e.Path -Name $e.Name -ErrorAction SilentlyContinue).($e.Name)
        if ($cur -ne $e.Value) {
          Set-ItemProperty -Path $e.Path -Name $e.Name -Value $e.Value -Type DWord
          $changed = $true
        }
      }
      $Ansible.Changed = $changed
  vars:
    ansible_become: true
    ansible_become_method: runas
    ansible_become_user: "{{ user_name }}"
    ansible_become_pass: "{{ ansible_password }}"
```

- [ ] **Step 2: Validate**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
```

- [ ] **Step 3: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/roles/windows_gaming/tasks/console_ux.yml
git commit -m "Add console_ux.yml §4.3.2 — Cortana/Bing/Widgets/Start menu policies

HKLM policies (Cortana, Widgets, Recommended section) + HKCU per-user keys
(Bing search, Cortana consent, search-box suggestions, doc/program tracking).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: console_ux.yml — OneDrive uninstall

**Files:**

- Modify: `Ansible/roles/windows_gaming/tasks/console_ux.yml` (append)

- [ ] **Step 1: Append OneDrive uninstall section**

Append to `console_ux.yml`:

```yaml
# ======================== §4.3.3 OneDrive uninstall ========================

- name: OneDrive — uninstall completely
  ansible.windows.win_powershell:
    script: |
      $changed = $false
      Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
      $candidates = @(
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
      )
      foreach ($exe in $candidates) {
        if (Test-Path $exe) {
          & $exe /uninstall | Out-Null
          $changed = $true
        }
      }
      $paths = @(
        "$env:LocalAppData\Microsoft\OneDrive",
        "$env:ProgramData\Microsoft OneDrive",
        "$env:SystemDrive\OneDriveTemp",
        "$env:UserProfile\OneDrive"
      )
      foreach ($p in $paths) {
        if (Test-Path $p) {
          Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
          $changed = $true
        }
      }
      # Remove Explorer namespace entries (both 64-bit and 32-bit views)
      $ns = @(
        'HKCU:\SOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}',
        'HKCU:\SOFTWARE\Classes\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
      )
      foreach ($k in $ns) {
        if (Test-Path $k) {
          New-ItemProperty -Path $k -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -PropertyType DWord -Force | Out-Null
          $changed = $true
        }
      }
      # Run entry
      $runPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
      if (Get-ItemProperty -Path $runPath -Name 'OneDrive' -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $runPath -Name 'OneDrive' -ErrorAction SilentlyContinue
        $changed = $true
      }
      $Ansible.Changed = $changed
  when: onedrive_uninstall
  vars:
    ansible_become: true
    ansible_become_method: runas
    ansible_become_user: "{{ user_name }}"
    ansible_become_pass: "{{ ansible_password }}"

- name: OneDrive — block reinstall via group policy
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive
    name: DisableFileSyncNGSC
    data: 1
    type: dword
  when: onedrive_uninstall
```

- [ ] **Step 2: Validate**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
```

- [ ] **Step 3: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/roles/windows_gaming/tasks/console_ux.yml
git commit -m "Add console_ux.yml §4.3.3 — OneDrive full uninstall

Kills process, runs OneDriveSetup.exe /uninstall (both arch variants),
removes leftover dirs, unpins Explorer namespace entries, removes Run
entry. GPO DisableFileSyncNGSC=1 blocks reinstall.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: console_ux.yml — Edge neutralization

**Files:**

- Modify: `Ansible/roles/windows_gaming/tasks/console_ux.yml` (append)

- [ ] **Step 1: Append Edge neutralization section**

Append to `console_ux.yml`:

```yaml
# ======================== §4.3.4 Edge neutralization ========================

- name: Edge — disable update services
  ansible.windows.win_service:
    name: "{{ item }}"
    start_mode: disabled
    state: stopped
  loop:
    - edgeupdate
    - edgeupdatem
    - MicrosoftEdgeElevationService
  failed_when: false
  when: edge_neutralize

- name: Edge — apply restrictive policies
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Policies\Microsoft\Edge
    name: "{{ item.name }}"
    data: "{{ item.value }}"
    type: dword
  loop:
    - { name: StartupBoostEnabled, value: 0 }
    - { name: BackgroundModeEnabled, value: 0 }
    - { name: HideFirstRunExperience, value: 1 }
    - { name: PersonalizationReportingEnabled, value: 0 }
    - { name: EdgeShoppingAssistantEnabled, value: 0 }
    - { name: ConfigureDoNotTrack, value: 1 }
  when: edge_neutralize

- name: Edge — remove desktop shortcuts
  ansible.windows.win_powershell:
    script: |
      $changed = $false
      $dirs = @("$env:Public\Desktop", "$env:UserProfile\Desktop")
      foreach ($d in $dirs) {
        Get-ChildItem -Path $d -Filter '*Edge*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
          Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
          $changed = $true
        }
      }
      $Ansible.Changed = $changed
  when: edge_neutralize
  vars:
    ansible_become: true
    ansible_become_method: runas
    ansible_become_user: "{{ user_name }}"
    ansible_become_pass: "{{ ansible_password }}"
```

- [ ] **Step 2: Validate**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
```

- [ ] **Step 3: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/roles/windows_gaming/tasks/console_ux.yml
git commit -m "Add console_ux.yml §4.3.4 — Edge neutralization

Disables update services, applies 6 restrictive Edge policies
(StartupBoost off, BackgroundMode off, ShoppingAssistant off,
DoNotTrack on, etc.), removes Edge desktop shortcuts.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: console_ux.yml — Firefox as default browser (template + Group Policy)

**Files:**

- Create: `Ansible/roles/windows_gaming/templates/firefox_default_associations.xml.j2`
- Modify: `Ansible/roles/windows_gaming/tasks/console_ux.yml` (append)

- [ ] **Step 1: Create the XML template**

Create `Ansible/roles/windows_gaming/templates/firefox_default_associations.xml.j2`:

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

- [ ] **Step 2: Append Firefox default section to console_ux.yml**

Append to `console_ux.yml`:

```yaml
# ======================== §4.3.5 Firefox default browser ========================

- name: Firefox — deploy DefaultAssociations.xml
  ansible.builtin.template:
    src: firefox_default_associations.xml.j2
    dest: C:\ProgramData\Microsoft\Windows\DefaultAssociations.xml
    force: true
  when: firefox_set_default

- name: Firefox — configure GPO to read DefaultAssociations.xml
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
    name: DefaultAssociationsConfiguration
    data: 'C:\ProgramData\Microsoft\Windows\DefaultAssociations.xml'
    type: string
  when: firefox_set_default
```

- [ ] **Step 3: Validate**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
```

- [ ] **Step 4: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/roles/windows_gaming/templates/firefox_default_associations.xml.j2 \
        Ansible/roles/windows_gaming/tasks/console_ux.yml
git commit -m "Add console_ux.yml §4.3.5 — Firefox as default browser via GPO

Deploys DefaultAssociations.xml mapping http/https/ftp/.html/.pdf/etc
to Firefox ProgIds. Sets DefaultAssociationsConfiguration GPO to read it.
Effect applies at next user login (Windows 11 GPO limitation).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: console_ux.yml — Telemetry + Notifications + Background apps + Startup cleanup + wire main.yml + verify

**Files:**

- Modify: `Ansible/roles/windows_gaming/tasks/console_ux.yml` (append)
- Modify: `Ansible/roles/windows_gaming/tasks/main.yml`
- Modify: `Ansible/playbooks/verify_gaming_optim.yml`

- [ ] **Step 1: Append telemetry / notifications / background apps / startup sections**

Append to `console_ux.yml`:

```yaml
# ======================== §4.3.6 Telemetry minimum ========================

- name: Telemetry — apply DataCollection policy
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection
    name: "{{ item.name }}"
    data: "{{ item.value }}"
    type: dword
  loop:
    - { name: AllowTelemetry, value: 1 }
    - { name: DoNotShowFeedbackNotifications, value: 1 }
  when: telemetry_minimum

- name: Telemetry — apply AdvertisingInfo policy
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo
    name: DisabledByGroupPolicy
    data: 1
    type: dword
  when: telemetry_minimum

- name: Telemetry — apply CloudContent policy
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent
    name: "{{ item.name }}"
    data: "{{ item.value }}"
    type: dword
  loop:
    - { name: DisableConsumerFeatures, value: 1 }
    - { name: DisableWindowsConsumerFeatures, value: 1 }
    - { name: DisableTailoredExperiencesWithDiagnosticData, value: 1 }
  when: telemetry_minimum

- name: Telemetry — disable DiagTrack service if present
  ansible.windows.win_service:
    name: "{{ item }}"
    start_mode: disabled
    state: stopped
  loop:
    - DiagTrack
    - dmwappushservice
  failed_when: false
  when: telemetry_minimum

# ======================== §4.3.7 Notifications + Background apps + Startup ========================

- name: Notifications — global toggle (HKCU)
  ansible.windows.win_powershell:
    script: |
      $changed = $false
      $entries = @(
        @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications';                       Name='ToastEnabled';                       Value={{ 0 if notifications_globally_off else 1 }}},
        @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings';                  Name='NOC_GLOBAL_SETTING_TOASTS_ENABLED';   Value={{ 0 if notifications_globally_off else 1 }}}
      )
      foreach ($e in $entries) {
        if (-not (Test-Path $e.Path)) { New-Item -Path $e.Path -Force | Out-Null }
        $cur = (Get-ItemProperty -Path $e.Path -Name $e.Name -ErrorAction SilentlyContinue).($e.Name)
        if ($cur -ne $e.Value) {
          Set-ItemProperty -Path $e.Path -Name $e.Name -Value $e.Value -Type DWord
          $changed = $true
        }
      }
      $Ansible.Changed = $changed
  vars:
    ansible_become: true
    ansible_become_method: runas
    ansible_become_user: "{{ user_name }}"
    ansible_become_pass: "{{ ansible_password }}"

- name: Background apps — Force Deny global policy
  ansible.windows.win_regedit:
    path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy
    name: LetAppsRunInBackground
    data: "{{ 2 if background_apps_force_deny else 0 }}"
    type: dword

- name: Startup apps — disable explicit list
  ansible.windows.win_powershell:
    script: |
      $names = @({{ startup_apps_disable | map('to_json') | join(', ') }})
      $changed = $false
      $runKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
      )
      foreach ($k in $runKeys) {
        if (-not (Test-Path $k)) { continue }
        $props = (Get-Item -Path $k).Property
        foreach ($p in $props) {
          foreach ($n in $names) {
            if ($p -like "*$n*") {
              Remove-ItemProperty -Path $k -Name $p -ErrorAction SilentlyContinue
              $changed = $true
            }
          }
        }
      }
      $Ansible.Changed = $changed
  vars:
    ansible_become: true
    ansible_become_method: runas
    ansible_become_user: "{{ user_name }}"
    ansible_become_pass: "{{ ansible_password }}"
```

- [ ] **Step 2: Wire into `main.yml`**

Edit `Ansible/roles/windows_gaming/tasks/main.yml`. Append after the gaming_optim include from Task 7:

```yaml
- name: Apply console-style UX hardening
  ansible.builtin.include_tasks: console_ux.yml
  tags: [system, console_ux]
```

- [ ] **Step 3: Append console_ux verification block to verify_gaming_optim.yml**

Append before the closing of the `tasks:` list:

```yaml
- name: Verify console_ux state — AppX residuals + Firefox default + OneDrive gone
  ansible.windows.win_powershell:
    script: |
      $appxResiduals = @()
      foreach ($n in @({{ appx_bloatware_extended | map('to_json') | join(', ') }})) {
        $found = Get-AppxPackage -Name "*$n*" -ErrorAction SilentlyContinue
        if ($found) { $appxResiduals += $n }
      }
      $ffPolicy = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name DefaultAssociationsConfiguration -ErrorAction SilentlyContinue).DefaultAssociationsConfiguration
      $oneDrivePresent = Test-Path "$env:LocalAppData\Microsoft\OneDrive\OneDrive.exe"
      $Ansible.Result = @{
        appx_residuals    = $appxResiduals
        firefox_policy    = $ffPolicy
        onedrive_present  = $oneDrivePresent
      }
  register: cux_verify
  tags: [console_ux, all]

- name: Assert console_ux state matches spec
  ansible.builtin.assert:
    that:
      - cux_verify.result.appx_residuals | length == 0
      - cux_verify.result.firefox_policy == 'C:\\ProgramData\\Microsoft\\Windows\\DefaultAssociations.xml'
      - not cux_verify.result.onedrive_present
    fail_msg: "console_ux state mismatch — got {{ cux_verify.result }}"
    success_msg: "console_ux state OK (no AppX residuals, Firefox default policy set, OneDrive gone)"
  tags: [console_ux, all]
```

- [ ] **Step 4: Validate**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
ansible-playbook --syntax-check main_windows_playbook.yml
ansible-playbook --syntax-check playbooks/verify_gaming_optim.yml
```

- [ ] **Step 5: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/roles/windows_gaming/tasks/console_ux.yml \
        Ansible/roles/windows_gaming/tasks/main.yml \
        Ansible/playbooks/verify_gaming_optim.yml
git commit -m "Complete console_ux.yml + wire main.yml + verify

§4.3.6 telemetry minimum (DataCollection, Advertising, CloudContent
policies + DiagTrack disabled). §4.3.7 notifications off (HKCU),
background apps Force Deny (HKLM), startup apps explicit-disable loop.
Wires console_ux.yml into main.yml under tags [system, console_ux].
Verify playbook gets AppX-residual / Firefox-default / OneDrive-gone
assertions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 4 — Drivers

### Task 14: drivers.yml — AMD chipset + NVIDIA install strategy + telemetry cleanup + wire + verify

**Files:**

- Create: `Ansible/roles/windows_gaming/tasks/drivers.yml`
- Modify: `Ansible/roles/windows_gaming/tasks/main.yml`
- Modify: `Ansible/playbooks/verify_gaming_optim.yml`

- [ ] **Step 1: Create drivers.yml**

Create `Ansible/roles/windows_gaming/tasks/drivers.yml`:

```yaml
---
# GPU + chipset drivers. See spec §4.4.
# AMD chipset critical for 9800X3D v-cache aware scheduler.
# NVIDIA driver: one-shot install via winget by default, user updates manually
# afterwards. Telemetry services disabled on every run regardless.

# ======================== §4.4.1 AMD chipset ========================

- name: AMD chipset — install via winget if absent
  ansible.windows.win_powershell:
    script: |
      $installed = winget list --id AdvancedMicroDevices.AMDChipsetDrivers --exact 2>$null |
                   Select-String 'AMDChipsetDrivers'
      if (-not $installed) {
        winget install --id AdvancedMicroDevices.AMDChipsetDrivers `
                       --silent --accept-package-agreements --accept-source-agreements
        $Ansible.Changed = $true
        $Ansible.Result = @{ action = 'installed' }
      } else {
        $Ansible.Result = @{ action = 'already_present' }
      }
  when: amd_chipset_install

# ======================== §4.4.2 NVIDIA driver ========================

- name: NVIDIA — detect existing driver
  ansible.windows.win_powershell:
    script: |
      $nv = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
            Where-Object FriendlyName -match 'NVIDIA'
      $Ansible.Result = @{ present = [bool]$nv }
  register: nvidia_check
  when: nvidia_driver_install_strategy != 'skip'

- name: NVIDIA — install driver via winget (one-shot)
  ansible.windows.win_powershell:
    script: |
      winget install --id Nvidia.GeForceDriver `
                     --silent --accept-package-agreements --accept-source-agreements
      $Ansible.Changed = $true
  when:
    - nvidia_driver_install_strategy == 'winget'
    - not (nvidia_check.result.present | default(false))

- name: NVIDIA — install driver via direct URL (one-shot)
  block:
    - name: Download NVIDIA driver installer
      ansible.windows.win_get_url:
        url: "{{ nvidia_driver_url }}"
        dest: 'C:\Windows\Temp\nvidia-driver.exe'
    - name: Run NVIDIA installer silently
      ansible.windows.win_command:
        cmd: 'C:\Windows\Temp\nvidia-driver.exe -s -clean'
  when:
    - nvidia_driver_install_strategy == 'direct_url'
    - not (nvidia_check.result.present | default(false))
    - nvidia_driver_url | length > 0

# ======================== §4.4.3 NVIDIA telemetry cleanup ========================

- name: NVIDIA — disable telemetry services
  ansible.windows.win_service:
    name: "{{ item }}"
    start_mode: disabled
    state: stopped
  loop:
    - NvTelemetryContainer
    - NvContainerLocalSystem
    - NvContainerNetworkService
    - NVDisplay.ContainerLocalSystem
  failed_when: false
  when: nvidia_telemetry_cleanup

- name: NVIDIA — remove telemetry crash report scheduled task
  community.windows.win_scheduled_task:
    name: NvTmRep_CrashReport
    state: absent
  failed_when: false
  when: nvidia_telemetry_cleanup
```

- [ ] **Step 2: Wire into main.yml**

Edit `Ansible/roles/windows_gaming/tasks/main.yml`. Append after the console_ux include from Task 13:

```yaml
- name: Install and tune GPU/chipset drivers
  ansible.builtin.include_tasks: drivers.yml
  tags: [softwares, drivers]
```

- [ ] **Step 3: Append drivers verification block to verify_gaming_optim.yml**

Append before the closing of the `tasks:` list:

```yaml
- name: Verify NVIDIA telemetry services disabled
  ansible.windows.win_powershell:
    script: |
      $svcNames = @('NvTelemetryContainer','NvContainerLocalSystem','NvContainerNetworkService')
      $status = @{}
      foreach ($n in $svcNames) {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($s) {
          $status[$n] = @{ status=[string]$s.Status; start_type=[string]$s.StartType }
        } else {
          $status[$n] = $null
        }
      }
      $sched = Get-ScheduledTask -TaskName 'NvTmRep_CrashReport' -ErrorAction SilentlyContinue
      $Ansible.Result = @{
        services    = $status
        crash_task  = [bool]$sched
      }
  register: nvidia_verify
  tags: [drivers, all]

- name: Assert NVIDIA telemetry cleanup applied
  ansible.builtin.assert:
    that:
      - "(nvidia_verify.result.services.NvTelemetryContainer is none) or (nvidia_verify.result.services.NvTelemetryContainer.start_type == 'Disabled')"
      - "(nvidia_verify.result.services.NvContainerLocalSystem is none) or (nvidia_verify.result.services.NvContainerLocalSystem.start_type == 'Disabled')"
      - not nvidia_verify.result.crash_task
    fail_msg: "NVIDIA telemetry cleanup mismatch — got {{ nvidia_verify.result }}"
    success_msg: "NVIDIA telemetry services + crash task verified disabled/absent"
  tags: [drivers, all]
  when: nvidia_telemetry_cleanup
```

- [ ] **Step 4: Validate**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
ansible-playbook --syntax-check main_windows_playbook.yml
ansible-playbook --syntax-check playbooks/verify_gaming_optim.yml
```

- [ ] **Step 5: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/roles/windows_gaming/tasks/drivers.yml \
        Ansible/roles/windows_gaming/tasks/main.yml \
        Ansible/playbooks/verify_gaming_optim.yml
git commit -m "Add drivers.yml — AMD chipset, NVIDIA install strategy, telemetry cleanup

AMD chipset via winget when absent. NVIDIA driver strategy switchable
(winget | direct_url | skip), one-shot install only if no NVIDIA
display device detected — user updates manually afterwards. Telemetry
services (NvTelemetryContainer, NvContainer*, NVDisplay.Container*)
forced to Disabled+Stopped on every run, NvTmRep_CrashReport scheduled
task removed. Wired into main.yml under tags [softwares, drivers].

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 5 — Firefox extension swap (common role)

### Task 15: Add `firefox_extension_id_keepassxc` + extension entry in policies template

**Files:**

- Modify: `Ansible/inventory/group_vars/all/main.yml`
- Modify: `Ansible/roles/common/templates/firefox_policies.json`

- [ ] **Step 1: Add the extension ID variable**

Edit `Ansible/inventory/group_vars/all/main.yml`. Find the line containing `firefox_extension_id_downThemAll` and add **right after it**:

```yaml
firefox_extension_id_keepassxc: "keepassxc-browser@keepassxc.org"
```

- [ ] **Step 2: Add KeePassXC entry to `firefox_policies.json` template**

Read the file first to know exactly where to insert:

```bash
cat /Users/abusutil/github-perso/resources/Ansible/roles/common/templates/firefox_policies.json
```

Locate the closing brace of `ExtensionSettings` (the line `      },` right after the `downThemAll` block ending with `"install_url": "...downthemall-4.5.2.xpi"`). The block currently ends:

```json
        "{{ firefox_extension_id_downThemAll }}": {
            "installation_mode": "normal_installed",
            "install_url": "https://addons.mozilla.org/firefox/downloads/file/3983650/downthemall-4.5.2.xpi"
        }
      },
```

Modify to insert KeePassXC as a `force_installed` entry, adding a comma after `downThemAll` block and a new entry:

```json
        "{{ firefox_extension_id_downThemAll }}": {
            "installation_mode": "normal_installed",
            "install_url": "https://addons.mozilla.org/firefox/downloads/file/3983650/downthemall-4.5.2.xpi"
        },
        "{{ firefox_extension_id_keepassxc }}": {
            "installation_mode": "force_installed",
            "install_url": "https://addons.mozilla.org/firefox/downloads/latest/keepassxc-browser/latest.xpi",
            "default_area": "navbar"
        }
      },
```

(Also strips a stray trailing space after the downThemAll URL in the original.)

- [ ] **Step 3: Verify JSON is still valid after templating**

```bash
cd /Users/abusutil/github-perso/resources
# Render the template with placeholder values to check JSON validity
python3 -c "
import json
with open('Ansible/roles/common/templates/firefox_policies.json') as f:
    content = f.read()
# Replace Jinja vars with placeholders for JSON validity check
import re
rendered = re.sub(r'\{\{\s*\w+\s*\}\}', 'PLACEHOLDER', content)
json.loads(rendered)
print('JSON valid')
"
```

Expected: `JSON valid`

- [ ] **Step 4: Lint**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
```

- [ ] **Step 5: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/inventory/group_vars/all/main.yml \
        Ansible/roles/common/templates/firefox_policies.json
git commit -m "Add KeePassXC-Browser extension to Firefox policies

force_installed via Mozilla addons CDN, default_area=navbar. New var
firefox_extension_id_keepassxc in group_vars/all/main.yml. No Bitwarden
entries present to remove — spec mentioned a swap but only the addition
is needed. Applies to Linux + Windows (the common role is cross-platform).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 6 — Final integration

### Task 16: Add final reboot block + update CLAUDE.md tag table

**Files:**

- Modify: `Ansible/roles/windows_gaming/tasks/main.yml`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add the final reboot block to main.yml**

Edit `Ansible/roles/windows_gaming/tasks/main.yml`. Append at the very end (after the drivers include):

```yaml
- name: Reboot if any task flagged it
  ansible.windows.win_reboot:
    reboot_timeout: 600
    test_command: 'exit (Get-Service -Name WinRM).Status -ne "Running"'
  when: reboot_required | default(false)
```

- [ ] **Step 2: Update the tags table in CLAUDE.md**

Edit `CLAUDE.md`. Locate the `### Tags (rôle windows_gaming)` section. Add these 4 rows at the end of the table (before the closing of the section):

```markdown
| `defender` | Defender exclusions paths/processes/extensions + cloud reporting off |
| `gaming_optim` | VBS off + weekly safety-reset + kernel/network/storage tweaks + Game DVR/Mode |
| `console_ux` | Debloat (AppX, Cortana, Bing, Widgets, OneDrive, Edge neutral, Firefox default, telemetry, notifications) |
| `drivers` | AMD chipset + NVIDIA driver (one-shot) + NVIDIA telemetry services off |
```

- [ ] **Step 3: Validate**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
ansible-playbook --syntax-check main_windows_playbook.yml
```

- [ ] **Step 4: Commit**

```bash
cd /Users/abusutil/github-perso/resources
git add Ansible/roles/windows_gaming/tasks/main.yml CLAUDE.md
git commit -m "Add final reboot block + document new tags in CLAUDE.md

Single conditional win_reboot at the end of the role, triggered by any
task that set the reboot_required fact (currently only the VBS keys do,
via Task 4). New tags defender/gaming_optim/console_ux/drivers documented
in the tags table.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 17: First real run + verification (slow loop, requires PC on)

**Files:** (none — operational task)

> **Prerequisite:** The `aurelien-gaming` host must be powered on, reachable over the LAN, WinRM listener active (this is the same prereq as any existing `make windows`). The KeePass DB path must be reachable (NAS share `/Volumes/home` mounted on the controller).

- [ ] **Step 1: Disable Tamper Protection manually (one-shot)**

On `aurelien-gaming`:

- Open Windows Security
- Virus & threat protection → Manage settings
- **Tamper Protection** → OFF
- Confirm UAC prompt

This is required ONCE before the Defender exclusions can apply. Subsequent runs don't need this unless an update re-enables it.

- [ ] **Step 2: Run lint locally one final time**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make lint
```

Expected: 0 errors.

- [ ] **Step 3: Ping the host**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make ping-windows
```

Expected: `aurelien-gaming | SUCCESS => { "changed": false, "ping": "pong" }`. If not reachable, troubleshoot before proceeding.

- [ ] **Step 4: Dry-run each new tag**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make check-windows ARGS='--tags defender'
make check-windows ARGS='--tags gaming_optim'
make check-windows ARGS='--tags console_ux'
make check-windows ARGS='--tags drivers'
```

Expected: each prints the diff Ansible would apply. No errors.

- [ ] **Step 5: Apply for real, full run**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make windows
```

Expected: many `changed: yes` on first run. One reboot near the end (VBS toggle). After reboot, the playbook finishes the remaining tags.

- [ ] **Step 6: Run the verify playbook**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make verify-windows
```

Expected: All assertions pass, success messages printed for Defender / VBS / Kernel / Hibernation / console_ux / NVIDIA telemetry blocks.

- [ ] **Step 7: Run again to confirm idempotence**

```bash
cd /Users/abusutil/github-perso/resources/Ansible
make windows
```

Expected: `changed=0` in PLAY RECAP. If any task reports `changed`, it's a bug — open issue and fix before merging branch.

- [ ] **Step 8: Smoke-test Game Bar still works**

On `aurelien-gaming` after reboot: `Win+G` → Game Bar overlay opens. Game DVR off but overlay works. Quick capture is gone (intentional). FPS counter widget still works.

- [ ] **Step 9: Commit any fixes**

If steps 4-7 surface issues, fix them in the appropriate task file, lint, commit with a clear message like:

```bash
git commit -m "fix(gaming_optim): <specific issue> caught during first real run"
```

If everything passed first try, nothing to commit — proceed to Task 18.

---

### Task 18: Push and prepare merge

**Files:** (none — operational task)

- [ ] **Step 1: Push the branch**

```bash
cd /Users/abusutil/github-perso/resources
# If SSH on Catskan still doesn't work, use HTTPS + PAT as in the earlier session:
# (Get a fresh PAT — the previous one should be revoked.)
git push "https://Catskan:<NEW_PAT>@github.com/Catskan/resources.git" \
        feature/windows-gaming-optim-spec:feature/windows-gaming-optim-spec
# Otherwise (once SSH works):
# git push origin feature/windows-gaming-optim-spec
```

Expected: branch updated on origin.

- [ ] **Step 2: Compare with main**

```bash
cd /Users/abusutil/github-perso/resources
git log main..feature/windows-gaming-optim-spec --oneline
```

Expected: ~14-16 commits listed, starting with the original spec commit `5518363` and ending with the most recent fix or Task 16 commit.

- [ ] **Step 3: Decide merge strategy**

Options:

- **Direct merge** to main (fast, no review process): `git checkout main && git merge --no-ff feature/windows-gaming-optim-spec`
- **PR for self-review** on GitHub: open a PR `feature/windows-gaming-optim-spec` → `main`, scan the diff one last time, merge via GitHub UI
- **Squash merge** if the per-task commits feel too granular: `git merge --squash feature/windows-gaming-optim-spec`

User decides at this point — not part of the automated plan.

- [ ] **Step 4: Done**

If merged, optionally delete the branch:

```bash
git branch -d feature/windows-gaming-optim-spec
git push origin --delete feature/windows-gaming-optim-spec  # (or via HTTPS+PAT)
```

---

## Spec coverage check

| Spec section                | Plan task(s)                                                                                                                   |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| §2 BIOS prerequisites       | Mentioned in Task 17 step 1 (operational reminder) — out of Ansible scope                                                      |
| §3.1 File layout            | Tasks 3, 4-7, 8-13, 14 (create the 4 new files)                                                                                |
| §3.2 Tags                   | Wired into main.yml in Tasks 3, 7, 13, 14 — documented in Task 16 step 2                                                       |
| §3.3 Variables              | Task 1                                                                                                                         |
| §4.1 defender.yml           | Task 3                                                                                                                         |
| §4.2 gaming_optim.yml       | Tasks 4-7                                                                                                                      |
| §4.3 console_ux.yml         | Tasks 8-13                                                                                                                     |
| §4.4 drivers.yml            | Task 14                                                                                                                        |
| §4.5 main.yml orchestration | Tasks 3, 7, 13, 14, 16                                                                                                         |
| §4.6 Common role Firefox    | Task 15                                                                                                                        |
| §5 Tests & verification     | Task 2 (scaffold) + Tasks 3, 7, 13, 14 (incremental assert blocks) + Task 17 (real run)                                        |
| §6 Rollback                 | Implicit — every behaviour gated by a variable that can be flipped + re-run. Documented in spec, no separate plan task.        |
| §7 Risks & mitigations      | Addressed inline (Tamper Protection check in Task 3, `failed_when: false` on services in Tasks 13/14, try/catch in PS scripts) |
| §9 Acceptance criteria      | Task 17 covers all 5 criteria                                                                                                  |

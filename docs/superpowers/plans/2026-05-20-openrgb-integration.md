# OpenRGB Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OpenRGB to the `windows_gaming` role with a Startup shortcut for set-and-forget RGB control on `aurelien-gaming`.

**Architecture:** Winget install via existing `softwares_winget.yml` loop + new `openrgb_setup.yml` task file (same pattern as `keepassxc_setup.yml`). Gated on `openrgb_enabled` toggle + `inventory_hostname == "aurelien-gaming"`.

**Tech Stack:** Ansible (win_powershell, win_shortcut, community.windows), winget (`CalcProgrammer1.OpenRGB`)

**Spec:** `docs/superpowers/specs/2026-05-20-openrgb-integration-design.md`

---

### Task 1: Add `openrgb_enabled` toggle + winget package

**Files:**
- Modify: `Ansible/inventory/group_vars/windows_hosts/main.yml`
- Modify: `Ansible/inventory/host_vars/w11-vm-aurel/main.yml`

- [ ] **Step 1: Add `openrgb_enabled` variable to `group_vars/windows_hosts/main.yml`**

After the `rustdesk_enabled: true` line (around line 87), add:

```yaml
# --- RGB control (openrgb_setup.yml) ---
# Set & forget: OpenRGB launches minimized at startup, user configures
# their RGB profile once manually, OpenRGB maintains the SMBus claim so
# devices don't revert to firmware rainbow. ~20 Mo RAM resident, 0% CPU.
openrgb_enabled: true
```

- [ ] **Step 2: Add `CalcProgrammer1.OpenRGB` to `winget_packages` in `group_vars/windows_hosts/main.yml`**

After the `RustDesk.RustDesk` entry (around line 225), add:

```yaml
  # --- RGB control ---
  - CalcProgrammer1.OpenRGB  # Set & forget RGB — startup shortcut via openrgb_setup.yml
```

- [ ] **Step 3: Disable OpenRGB on VM in `host_vars/w11-vm-aurel/main.yml`**

At the end of the file, add:

```yaml
# --- No RGB hardware on VM ---
openrgb_enabled: false
```

- [ ] **Step 4: Commit**

```bash
git add Ansible/inventory/group_vars/windows_hosts/main.yml Ansible/inventory/host_vars/w11-vm-aurel/main.yml
git commit -m "feat(openrgb): add winget package + openrgb_enabled toggle"
```

---

### Task 2: Create `openrgb_setup.yml` task file

**Files:**
- Create: `Ansible/roles/windows_gaming/tasks/openrgb_setup.yml`

- [ ] **Step 1: Create `openrgb_setup.yml`**

```yaml
---
# Configure OpenRGB on aurelien-gaming:
#   1) Locate the installed binary (winget install path varies by scope).
#   2) Create a Startup shortcut so OpenRGB launches minimized at login
#      and maintains the SMBus claim on RGB devices.
#   3) Add a Defender exclusion for the install directory (prevents
#      realtime scan interference with SMBus/I2C access).
#
# Assumes OpenRGB has been installed by softwares_winget.yml
# (CalcProgrammer1.OpenRGB in winget_packages). Gated on aurelien-gaming
# because the VM has no RGB hardware.

- name: OpenRGB — locate installed binary
  ansible.windows.win_powershell:
    script: |
      $candidates = @(
        "$env:ProgramFiles\OpenRGB\OpenRGB.exe",
        "${env:ProgramFiles(x86)}\OpenRGB\OpenRGB.exe",
        "$env:LOCALAPPDATA\Programs\OpenRGB\OpenRGB.exe"
      )
      $exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
      if (-not $exe) { throw "OpenRGB.exe not found — softwares_winget.yml didn't install CalcProgrammer1.OpenRGB?" }
      $dir = Split-Path $exe -Parent
      $Ansible.Result = @{ path = $exe; directory = $dir }
      $Ansible.Changed = $false
  register: openrgb_exe
  changed_when: false
  check_mode: false

- name: OpenRGB — startup shortcut (launches minimized at user login)
  community.windows.win_shortcut:
    src: "{{ openrgb_exe.result.path }}"
    args: "--startminimized"
    dest: '{{ ansible_env.APPDATA }}\Microsoft\Windows\Start Menu\Programs\Startup\OpenRGB.lnk'
    description: OpenRGB — set & forget RGB control at login

- name: Defender — exclude OpenRGB install directory from realtime scan
  ansible.windows.win_powershell:
    parameters:
      path: "{{ openrgb_exe.result.directory }}"
    script: |
      param([string]$path)
      $current = (Get-MpPreference).ExclusionPath
      if ($current -notcontains $path) {
        Add-MpPreference -ExclusionPath $path
        $Ansible.Changed = $true
      } else {
        $Ansible.Changed = $false
      }
```

- [ ] **Step 2: Commit**

```bash
git add Ansible/roles/windows_gaming/tasks/openrgb_setup.yml
git commit -m "feat(openrgb): add setup task — startup shortcut + Defender exclusion"
```

---

### Task 3: Wire `openrgb_setup.yml` into `main.yml` orchestrator

**Files:**
- Modify: `Ansible/roles/windows_gaming/tasks/main.yml`

- [ ] **Step 1: Add `include_tasks` block in `main.yml`**

After the KeePassXC block (line 96) and before the Xbox Mode block (line 98), add:

```yaml
- name: Configure OpenRGB (startup minimized for RGB control)
  ansible.builtin.include_tasks:
    file: openrgb_setup.yml
    apply:
      tags: [openrgb]
  tags: [openrgb]
  when:
    - inventory_hostname == "aurelien-gaming"
    - openrgb_enabled | bool
```

- [ ] **Step 2: Commit**

```bash
git add Ansible/roles/windows_gaming/tasks/main.yml
git commit -m "feat(openrgb): wire into main.yml orchestrator with tag"
```

---

### Task 4: Lint validation

- [ ] **Step 1: Run ansible-lint + yamllint**

```bash
cd Ansible/ && make lint
```

Expected: no errors on the 4 modified/created files.

- [ ] **Step 2: Fix any lint issues if found, then commit**

```bash
git add -A && git commit -m "fix(openrgb): lint fixes"
```

Only if lint found issues — skip this step if lint passes clean.

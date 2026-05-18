# Claude session handoff — Aurel-Gaming Ansible role

> **Audience**: a fresh Claude Code session picking up this repo on another machine. Read this top-to-bottom before answering. Trust `git log` and the current state of files over anything in this doc if there's a conflict — this is a 2026-05-18 snapshot.

## TL;DR — what this repo is and where it stands

Personal infra monorepo. The center of gravity is `Ansible/`, which provisions Aurélien's machines (Windows gaming PC `aurelien-gaming`, Arch Linux laptop `arch-linux-laptop`, MacBook Air = controller, NAS, Win11 ARM VM `w11-vm-aurel`). Everything in `Containers/`, `Microsoft-Resources/`, `Linux-Resources/`, etc. is reference material or self-contained side projects.

The `windows_gaming` role has been **completely overhauled across 9 merged PRs (2026-05-13 → 2026-05-18)**. End state: a fully automated Win11 25H2 console-like setup for a Ryzen 9800X3D + Asus B850 + RTX 3080 watercooled rig, validated end-to-end on a Win11 ARM VM with perfect idempotency (`changed=0` on 2nd run).

**Only remaining outstanding work**: Task 17 — first real run on the physical 9800X3D machine. Blocked until the hardware is built. Everything else is done.

## PR history (chronological, all merged to main)

| #   | Title                                                                                   | Scope                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| --- | --------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | gaming-optim-spec (P0 + P1 + bulk gaming optim)                                         | VBS off + safety reset, kernel/network/storage tweaks, Defender exclusions, console UX bootstrap, NAS SMB drives, Firefox unpin, NVIDIA GFE removal, register-var rename, autounattend artifacts, idempotency fixes                                                                                                                                                                                                                                                                                                                                                                                                                |
| 2   | refactor(p2) — `user_folders.yml` cleanup                                               | 499→77 lines (loop over 8 active redirections), 2 VSS keys moved to `system_settings.yml`, ~40 lines of dead vars dropped, Playnite shortcut removed                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| 3   | chore — complete repo restructure                                                       | KeePass migration (replaced AWS Secrets), lowercase rename `Roles/`→`roles/` + `Inventory/`→`inventory/`, per-host split YAMLs `{connection,main,secrets}.yml`, legacy Vagrant/Docker purge, `Microsoft-Resources/Powershell Scripts/Enable_winrm.ps1` → `roles/windows_gaming/files/bootstrap_winrm.ps1`                                                                                                                                                                                                                                                                                                                          |
| 4   | refactor(p3) — full winget migration                                                    | Replaced `softwares_{check,download,install,uninstall}.yml` + `softwares_check_versions.yml` + `ms_store_apps.yml` (6 files) with single `softwares_winget.yml` + dedicated `appx_bloatware.yml`. `drivers.yml` rewritten: AMD chipset via `direct_url`, NVIDIA via NVCleanstall CLI (`-clean -nogfe -notlm -nophysx`)                                                                                                                                                                                                                                                                                                             |
| 5   | feat(keepassxc) — NAS-backed vault + Auto-Type                                          | KeePassXC installed via winget, opens vault directly from NAS via UNC `\\192.168.1.7\home\Drive\Vault\Aurel-Vault.kdbx`. Tray autostart. Defender exclusion for the kdbx. Auto-Type global shortcut Ctrl+Shift+V (Qt KeyboardModifier 100663296 + Qt::Key_V 86). New Python script `scripts/keepass_apply_autotype.py` adds Window Associations to launcher entries in the kdbx (Steam, Epic, Ubisoft, GOG, EA, Rockstar, Microsoft Account / Store / Xbox)                                                                                                                                                                        |
| 6   | feat(autounattend) — bare-metal Win11 USB workflow                                      | Pivoted from ISO build to USB-overlay. New `build-autounattend.sh` outputs `dist/usb-baremetal/` ready to drop on a Rufus-burned Win11 USB. Drivers slipstreamed via `$OEM$\$1\Drivers\` from gitignored `drivers-source/`. `<DiskConfiguration>` omitted → manual partition selection. FirstLogonCommands: pnputil drivers + WinRM bootstrap + quotas + Tamper off + IP dump to `C:\Aurel-Gaming-IP.txt`. **Python 3.13** added to `winget_packages`                                                                                                                                                                              |
| 7   | feat(gaming) — HAGS + PowerThrottling + VRR/AutoHDR + HPET + Xbox Mode + AMD power plan | Tier 1: HAGS (`HwSchMode=2`), `PowerThrottlingOff=1`, VRR + Auto HDR (`DirectXUserGlobalSettings`), Game Bar capture precision (keep `AppCaptureEnabled=1` for controller screenshots, kill `HistoricalCaptureEnabled`+`MicrophoneCaptureEnabled`), accessibility shortcuts off. Tier 2: AMD Ryzen Balanced power plan moved to end of `drivers.yml` (single-run convergence after chipset install), HPET disable via bcdedit + `tscsyncpolicy Enhanced`, Windows Update Active Hours 10-23h. Tier 3: Xbox Full-Screen Experience via DeviceForm spoof (0x2E) + GamingHomeApp = Xbox app AUMID. Toggleable via `xbox_mode_enabled` |
| 8   | feat(remote) — Sunshine + RustDesk (LAN-only)                                           | Sunshine self-hosted game streaming (NVENC HEVC, Moonlight library: Desktop + Steam Big Picture + Xbox FSE, Web UI LAN-only, firewall private profile). RustDesk desktop remoting (direct LAN IP, permanent password from KeePass, telemetry off). Both fully customised via templates. Initial WAN toggle attempt for Sunshine was reverted (commit `d6c27c9`) — kept strictly LAN-only                                                                                                                                                                                                                                           |
| 9   | feat(keepassxc) — Xbox app window in Auto-Type                                          | One-line addition: `Xbox*` wildcard window pattern on the Microsoft Account entry, so the Xbox app login (Game Pass library) is autotyped same as Microsoft Store                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |

Plus a small `Fix creds` commit (`adfe7ac`) on main directly: corrected KeePass lookup paths in `host_vars/aurelien-gaming/secrets.yml` to match the user's real kdbx entries (`Local/Aurel-Gaming`, `Microsoft Account`, `Uplay (Ubisoft)`, `Nas`, `Local/Sunshine`, `Local/RustDesk`).

## End-state architecture

### Role file layout (`Ansible/roles/windows_gaming/tasks/`)

| File                   | Role                                                                                                                                                                                                                                                                                                                          |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `main.yml`             | Orchestrator — includes each child file with `apply: { tags }` for proper tag propagation                                                                                                                                                                                                                                     |
| `system_settings.yml`  | WinRM, RDP, AutoLogon, hostname, NAS Credential Manager + mapped drives W:Aurelien + V:Apps, WoL, Nahimic disable, VSS access keys, UAC, Active Hours                                                                                                                                                                         |
| `user_folders.yml`     | 8 HKCU Shell Folders → `M:\Aurel` (Desktop, Documents, Downloads, Music, Pictures, Videos, Saved Games, Favorites)                                                                                                                                                                                                            |
| `defender.yml`         | Tamper guard, path/process/extension exclusions, cloud reporting off (MAPSReporting / SubmitSamplesConsent enum mapping int↔name)                                                                                                                                                                                             |
| `gaming_optim.yml`     | §4.2.1 VBS off + scheduled weekly safety-reset · §4.2.2-3 kernel + Nagle · §4.2.4 hibernate / pagefile / USB / PCIe power · §4.2.5 Game DVR off + Game Mode on · §4.2.6 HAGS + PowerThrottlingOff + VRR + Auto HDR · §4.2.7 Game Bar capture precision · §4.2.8 accessibility shortcuts off · §4.2.9 HPET disable via bcdedit |
| `console_ux.yml`       | AppX bloatware (delegates to `appx_bloatware.yml`), Cortana/Bing/Widgets policies, OneDrive uninstall, Edge neutralization, Firefox-as-default via DefaultAssociations.xml, telemetry policies, notifications off, background apps deny, startup apps disable                                                                 |
| `appx_bloatware.yml`   | Single source of truth for the 33-item `appx_bloatware` list (also consumed by `main_remove_softwares.yml`)                                                                                                                                                                                                                   |
| `softwares_winget.yml` | One `winget list` snapshot + per-package Ansible loop with Start-Job + Wait-Job (10-min timeout). Both `winget_packages` (default source) and `msstore_packages` (--source msstore)                                                                                                                                           |
| `drivers.yml`          | AMD chipset (direct_url from `amd_chipset_url`) + NVIDIA via NVCleanstall CLI + NVIDIA telemetry services off + power plan AMD Ryzen Balanced (or High Performance fallback)                                                                                                                                                  |
| `keepassxc_setup.yml`  | KeePassXC ini deployment + Startup shortcut + Defender exclusion (bare-metal only, gated `aurelien-gaming`)                                                                                                                                                                                                                   |
| `xbox_mode.yml`        | DeviceForm handheld spoof + GamingHomeApp = Xbox app AUMID. Toggleable via `xbox_mode_enabled` (bare-metal only)                                                                                                                                                                                                              |
| `sunshine_setup.yml`   | Sunshine creds + apps.json + service + LAN firewall                                                                                                                                                                                                                                                                           |
| `rustdesk_setup.yml`   | RustDesk service install + permanent password + LAN firewall                                                                                                                                                                                                                                                                  |

### Templates (`Ansible/roles/windows_gaming/templates/`)

- `firefox_default_associations.xml.j2` — sets Firefox as default browser
- `synology_config_win.json.j2` — Synology Drive Client config
- `keepassxc.ini.j2` — KeePassXC config: vault UNC, tray, Ctrl+Shift+V autotype
- `sunshine.conf.j2` — encoder, NVENC preset, Web UI scope, log level
- `sunshine_apps.json.j2` — Moonlight library (Desktop / Steam BP / Xbox FSE)
- `RustDesk2.toml.j2` — direct LAN, permanent password mode, telemetry off

### Inventory vars

**`group_vars/windows_hosts/main.yml`** — all generic Win11 vars (defender exclusions, VBS toggle, gaming_optim toggles, Game DVR/Mode, deep optim toggles HAGS/PowerThrottling/VRR/AutoHDR/GameCapture/Accessibility/HPET, Xbox Mode, Active Hours, console UX policies, appx_bloatware (33), NVIDIA telemetry cleanup, winget_packages (19), msstore_packages, Sunshine config, RustDesk config).

**`host_vars/aurelien-gaming/main.yml`** — hardware-specific: hibernation false, page_file fixed 32/48GB, USB suspend off, PCIe link off, amd_chipset_install + url (8.10.0827.6), nvidia_driver_install_strategy nvcleanstall, nas_url `192.168.1.7` (LAN static), keepassxc_vault_unc UNC path, nas_mapped_drives (W:Aurelien + V:Apps).

**`host_vars/w11-vm-aurel/main.yml`** — VM overrides: hibernation true, page_file system_managed, amd_chipset_install false, nvidia_driver_install_strategy skip, hpet_disabled false (hypervisor needs HPET), short `winget_packages` (5 ARM-native: Firefox / 7zip / Notepad++ / VLC / Terminal), `msstore_packages: []`.

### KeePass entry paths used (`host_vars/aurelien-gaming/secrets.yml`)

All resolved via `lookup('viczem.keepass.keepass', '<path>', '<field>')`:

| Var                                      | KeePass path         | Fields              |
| ---------------------------------------- | -------------------- | ------------------- |
| `remote_local_user_name_password`        | `Local/Aurel-Gaming` | password            |
| `microsoft_account_email` / `_password`  | `Microsoft Account`  | username + password |
| `ubisoft_connect_username` / `_password` | `Uplay (Ubisoft)`    | username + password |
| `nas_username` / `_password`             | `Nas`                | username + password |
| `sunshine_admin_user` / `_password`      | `Local/Sunshine`     | username + password |
| `rustdesk_permanent_password`            | `Local/RustDesk`     | password            |

The kdbx lives at `/Volumes/home/Drive/Vault/Aurel-vault.kdbx` (Mac) / `\\192.168.1.7\home\Drive\Vault\Aurel-Vault.kdbx` (Windows). `make test-keepass` resolves all entries at runtime to validate before any run.

### Tags (role `windows_gaming`)

Full table in `CLAUDE.md`. Quick summary: `bootstrap`, `system`, `rdp`, `wol`, `user_folders`, `defender`, `gaming_optim`, `console_ux`, `softwares_winget`, `firefox`, `drivers`, `keepassxc`, `xbox_mode`, `sunshine`, `rustdesk`. All include_tasks blocks use `apply: { tags: [...] }` so `--tags <X>` actually runs the inner tasks (without `apply:` only the include statement fires).

## Make commands cheatsheet (Mac controller)

```bash
cd Ansible/
make help                            # list all targets

# Real-host runs (prompt KeePass master pw via scripts/run.sh)
make windows                         # full role on aurelien-gaming + w11-vm-aurel
make windows-vm                      # full role on w11-vm-aurel only
make linux                           # arch-linux-laptop
make uninstall-bloat                 # AppX bloatware only (via appx_bloatware.yml)

# Dry-runs
make check-windows                   # --check --diff full
make check-windows-vm                # --check --diff on VM
make check-linux

# Subset by tag
make windows ARGS='--tags rdp,wol'
make windows ARGS='--tags softwares_winget'
make windows ARGS='--tags keepassxc'

# Diagnostics (no real-host changes)
make test-keepass                    # resolve every lookup, offline
make inspect-keepass                 # check expected paths + dump kdbx tree
make inspect-keepass ARGS='--tree'   # tree only

# KeePass Auto-Type associations
make keepass-autotype                # dry-run (preview)
make keepass-autotype ARGS='--apply' # write Window Associations to kdbx

# Verify gaming optim state (offline asserts)
make verify-windows

# Connectivity
make ping-windows                    # win_ping all windows_hosts
make ping-windows ARGS='--limit aurelien-gaming'

# Lint
make lint                            # yamllint + ansible-lint
```

Override KeePass DB path: `KEEPASS_LOCATION=/tmp/local-copy.kdbx make windows`.

## Fresh bare-metal install workflow (Aurel-Gaming)

This is the canonical sequence for the 9800X3D build (Task 17 of the original plan).

### Phase A — Prepare USB on the Mac

1. `git pull origin main` on the Mac to get the latest role state.
2. Download the Asus B850 motherboard driver bundle from Asus support. Extract the INF folders into `Microsoft-Resources/autounattend/drivers-source/` (gitignored — won't be committed).
3. `cd Microsoft-Resources/autounattend/ && ./build-autounattend.sh` — prompts the password to bake into `autounattend.xml` (this should match the KeePass `Local/Aurel-Gaming` entry's password). Output: `dist/usb-baremetal/`.
4. Burn Win11 25H2 x64 ISO to USB with Rufus.
5. Copy the contents of `dist/usb-baremetal/` (the `autounattend.xml` + `$OEM$/` tree) to the USB root.

### Phase B — Boot Aurel-Gaming

6. Boot from USB. Single manual step: pick the system NVMe on the partition page (data drives — M:\ — must NOT be wiped).
7. ~10 min: Setup finishes, AutoLogon as Aurel runs the FirstLogonCommands (pnputil drivers from `C:\Drivers\*.inf`, WinRM HTTPS bootstrap, quotas, Tamper off, IP dump).
8. Read the DHCP IP from the screen (`C:\Aurel-Gaming-IP.txt`).

### Phase C — Configure router (one-time)

9. Set a DHCP reservation for that IP on the box so it doesn't bounce.
10. Open Asus B850 / 9800X3D BIOS once to verify: TPM on, Resizable BAR on, AMD EXPO XMP enabled, fTPM stable.

### Phase D — Apply Ansible role from the Mac

11. Update `Ansible/inventory/host_vars/aurelien-gaming/connection.yml` with the IP.
12. `make ping-windows ARGS='--limit aurelien-gaming'` — confirm WinRM reachable.
13. `make test-keepass` — confirm all KeePass lookups resolve (`Local/Aurel-Gaming`, `Microsoft Account`, `Uplay (Ubisoft)`, `Nas`, `Local/Sunshine`, `Local/RustDesk` all need to exist in the kdbx beforehand).
14. `make windows` — full role run, ~15-20 min:
    - System settings (RDP, AutoLogon, NAS Credential + W:/V: mapped drives, WoL, VSS, Active Hours, UAC)
    - User Shell Folders → M:\Aurel
    - Defender exclusions + Tamper guard
    - Gaming optim (VBS off + all deep optims)
    - Console UX (AppX debloat, Cortana off, OneDrive uninstall, Edge neutralized, Firefox default, telemetry off, etc.)
    - Firefox cross-platform policies
    - winget chain (Steam, Epic, Ubisoft, GOG, EA, Rockstar, Firefox, MSI Afterburner, NVCleanstall, KeePassXC, Python 3.13, Sunshine, RustDesk, and 4 more) + Xbox Accessories from MS Store
    - AMD chipset install (8.10.0827.6) → AMD Ryzen Balanced power plan auto-selected
    - NVIDIA driver via NVCleanstall CLI (clean, no GFE, no telemetry) → NVIDIA telemetry services disabled
    - KeePassXC: ini deployment + Startup shortcut + Defender exclusion
    - Xbox FSE: DeviceForm + GamingHomeApp set
    - Sunshine + RustDesk: services + configs + LAN firewall
    - Final reboot if any task flagged `reboot_required`
15. Re-run `make windows` once more — should report `changed=0` (idempotency check).

### Phase E — First interactive session

16. Login as Aurel. KeePassXC opens from Startup → enter the master password ONCE (only manual secret left).
17. Settings → Gaming → Full-screen experience → toggle "Enter Xbox mode on startup" ON (the only Xbox Mode setting whose reg key Microsoft hasn't publicly documented — 1-click manual).
18. Reboot → boots directly into Xbox FSE console-like shell.
19. Test Auto-Type: click a launcher (Steam / Epic / Xbox app / etc.) → Ctrl+Shift+V → KeePassXC types creds + TOTP. Validates the kdbx Window Associations applied earlier via `make keepass-autotype --apply`.

### Phase F — Optional polish

20. Pair Moonlight clients (Apple TV / iPad / Steam Deck) with Sunshine: `https://aurel-gaming:47990` → Web UI login (KeePass `Local/Sunshine`) → enter PIN from each Moonlight client.
21. Install RustDesk client on Mac / iPad — connect via direct LAN IP, enter permanent password from KeePass `Local/RustDesk`.
22. Windows license: run `slmgr /dli` on the OLD PC if still functional to identify Retail vs OEM. If Retail + MS Account linked → activation troubleshooter on Aurel-Gaming. If OEM → buy new license (or accept the risk).

## Conventions worth knowing

- **APFS case insensitivity**: `Ansible/Roles/` and `Ansible/roles/` are the same dir on macOS but git tracks them as distinct. Always use the canonical lowercase paths (`roles/`, `inventory/`) per the post-PR-3 layout.
- **`include_tasks` + `--tags`**: ALWAYS use `apply: { tags: [...] }` form on `include_tasks` blocks. Without it, the include's tag fires but inner tasks aren't matched by `--tags <X>` (verified the hard way during P3/P4 sessions).
- **`win_powershell` exit codes**: For native CLI invocations needing exit-code checking + timeout (winget, NVCleanstall, pnputil), use `Start-Job` + `Wait-Job -Timeout 600` + `Receive-Job` pattern. `Start-Process -PassThru + WaitForExit(timeout)` returns null `ExitCode` on Win11 ARM even on success — DO NOT use it.
- **Check mode**: any read-only `win_powershell` task (e.g., snapshot, detect-installed) needs `check_mode: false` so `make check-windows*` doesn't crash on undefined registered vars downstream.
- **Power plan ordering**: AMD Ryzen Balanced plan only exists AFTER the AMD chipset installer runs → power plan task lives at the END of `drivers.yml`, NOT in `system_settings.yml`. Single-run convergence.
- **Idempotency: ALWAYS test on VM with 2 consecutive `make windows-vm` runs**. Second run MUST be `changed=0 failed=0`. If not, the task that reports changed is misbehaving (e.g., write-without-check-first, false-positive reg comparison, etc.).
- **Tamper Protection**: Win11 24H2+ silently refuses programmatic disable. Best-effort `Set-MpPreference -DisableTamperProtection $true` is in the autounattend FirstLogonCommands; if Defender still blocks WinRM bootstrap post-OOBE, manual Settings toggle once + rerun `bootstrap_winrm.ps1`.
- **Drivers source vs winget**: AMD chipset + NVIDIA GeForce driver are NOT in the winget catalog (verified empirically 2026-05-15). `drivers.yml` handles them: AMD via `direct_url`, NVIDIA via NVCleanstall (`TechPowerUp.NVCleanstall` IS in winget). Asus motherboard drivers (NIC, audio, USB) go via the autounattend USB `$OEM$\$1\Drivers\` + pnputil.
- **Path with spaces**: `Projects/Curl + Github Actions + Terraform`. Always quote.
- **Inventory hostnames in `when:`**: use `inventory_hostname == "aurelien-gaming"`, NEVER `ansible_hostname` or `ansible_facts['netbios_name']` — the netbios `Aurel-Gaming` doesn't match the inventory key `aurelien-gaming`.

## Pending / next steps

1. **Task 17 — bare-metal validation on 9800X3D**: end-to-end run on the physical machine. Covers AMD Ryzen Balanced switch, HPET off effect, AMD chipset install ordering, Xbox Mode FSE, NVCleanstall NVIDIA install, Sunshine pairing with real Moonlight clients, RustDesk LAN connection. Blocked until the user builds the machine.
2. **OpenVPN compatibility**: if Sunshine doesn't reach over the box's OpenVPN tunnel because the VPN subnet is classified `public` by Windows Firewall, two options: (a) configure OpenVPN to push the LAN route to clients, OR (b) re-introduce `sunshine_wan_enabled` (was committed then reverted in PR #8 — see commit `d6c27c9`).
3. **Tailscale (future)**: long-term WAN access for both Sunshine + RustDesk + NAS, no inbound port forwarding. Could be a `feat/tailscale` PR adding `tailscale_setup.yml` (winget `tailscale.tailscale` + `tailscale up --authkey <from KeePass>`).
4. **SSH on Catskan GitHub account broken**: pushes use HTTPS+PAT (`ghp_LGIz...`). Long-term: fix SSH config alias or rotate to a proper SSH key.
5. **`inventory/host_vars/macbook-air-aurelien/secrets.yml`** was vault-encrypted under the old AWS scheme — finish swap to KeePass when convenient.

## Hardware spec (target)

- **CPU**: AMD Ryzen 9800X3D (Zen 5, 3D V-cache)
- **Motherboard**: Asus B850 Max Gaming Wifi W
- **RAM**: 32 GB DDR5 CL30
- **System SSD**: Fanxiang M.2 NVMe (C:)
- **Data SSDs**: 1-2 SATA SSDs (M:\)
- **GPU**: NVIDIA RTX 3080 FE (watercooled, custom loop with CPU)
- **NIC**: Realtek 8125 2.5GbE (Ethernet) + WiFi 6E
- **Display**: HDR-capable gaming monitor (Auto HDR + VRR enabled in role)

## External resources

- **NAS**: Synology, LAN IP `192.168.1.7`, shares `home` (user) + `Aurelien` (public) + `Apps`. SMB Direct supported.
- **Vault**: `/Volumes/home/Drive/Vault/Aurel-Vault.kdbx` (Mac) / `\\192.168.1.7\home\Drive\Vault\Aurel-Vault.kdbx` (Windows). Backed by KeePassXC, opens read-write from any client with the master password.
- **Mac controller**: MacBook Air, `ansible_connection: local`. Runs all `make` targets.
- **VM**: `w11-vm-aurel` at `192.168.64.17` (UTM Win11 ARM on Apple Silicon). WinRM HTTPS port 5986. Used as integration-test mirror.

## Useful patterns / scripts

- `scripts/run.sh` — wraps any ansible binary, prompts KeePass master pw once via `read -rs`, sets `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` (fixes macOS fork() worker crash), `exec`s the command.
- `scripts/inspect_keepass.py` — offline diagnostic: lists expected paths from a yaml manifest, walks the kdbx, reports OK/MISSING per entry. Run via `make inspect-keepass`.
- `scripts/keepass_apply_autotype.py` — adds Window Associations to launcher entries (Steam, Epic, Ubisoft, GOG, EA, Rockstar, Microsoft Account / Store / Xbox app). Idempotent. Dry-run by default, `--apply` to write.

## Auto-memory location

Personal memories accumulated during these sessions live at:
`/Users/abusutil/.claude/projects/-Users-abusutil-github-perso-resources/memory/`

Key memory files:

- `MEMORY.md` — index pointing at the others
- `project_windows_gaming_role_cleanup_spec_written.md` — phases status (now ALL merged)
- `project_windows_gaming_optim_paused.md` — original gaming optim project state
- `feedback_ansible_winrm_patterns.md` — `apply:` and `Start-Job` lessons learned

A fresh Claude session on another laptop won't have these (they're local to the original Mac's Claude data dir). This handoff doc is the portable replacement.

# OpenRGB integration — design spec

> Date: 2026-05-20
> Scope: Add OpenRGB to the `windows_gaming` role for RGB control on `aurelien-gaming`

## Goal

Install OpenRGB via winget and configure it to launch minimized at startup, so the user can set a static RGB profile on first boot that persists across reboots. Zero gaming performance impact — no polling, no continuous effects, just "set & maintain claim on SMBus".

## Hardware targets

- Asus B850 motherboard (Aura SMBus + ARGB headers)
- CPU waterblock (ARGB header)
- GPU waterblock (ARGB header)

No SMBus conflict with MSI Afterburner: Afterburner reads GPU sensors via NVAPI, OpenRGB writes RGB via separate I2C addresses on the Asus Aura controller.

## Design decisions

- **Approach A (Startup shortcut)** chosen over Scheduled Task fire-and-forget (devices revert to firmware rainbow without active controller) and Windows Service (overkill, extra dependency).
- **No pre-deployed profile** — user configures RGB manually at first boot. OpenRGB persists the last-used profile in `%APPDATA%\OpenRGB\`.
- **Bare-metal only** — gated on `aurelien-gaming` + `openrgb_enabled` toggle. VM has no RGB hardware.

## Files changed

### 1. `inventory/group_vars/windows_hosts/main.yml`

Add toggle variable:

```yaml
# --- RGB control (openrgb_setup.yml) ---
openrgb_enabled: true
```

Add to `winget_packages` list:

```yaml
  # --- RGB control ---
  - CalcProgrammer1.OpenRGB  # Set & forget RGB — startup shortcut via openrgb_setup.yml
```

### 2. `inventory/host_vars/w11-vm-aurel/main.yml`

```yaml
# --- No RGB hardware on VM ---
openrgb_enabled: false
```

### 3. `roles/windows_gaming/tasks/openrgb_setup.yml` (new)

Follows the exact same pattern as `keepassxc_setup.yml`:

1. **Locate binary** — probe `Program Files`, `Program Files (x86)`, `LOCALAPPDATA\Programs` (winget install location varies by scope). Fail with clear message if not found.
2. **Startup shortcut** — `win_shortcut` to `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\OpenRGB.lnk` with args `--startminimized`. Idempotent (fixed dest path).
3. **Defender exclusion** — add OpenRGB install directory to `ExclusionPath` (prevents realtime scan interference with SMBus/I2C access). Check-before-write for idempotency.

No config template, no profile deployment.

### 4. `roles/windows_gaming/tasks/main.yml`

New `include_tasks` block after KeePassXC, before Xbox Mode:

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

Tag `openrgb` added — runnable via `make windows ARGS='--tags openrgb'`.

## Idempotency

| Task | Idempotent mechanism |
|---|---|
| winget install | `softwares_winget.yml` checks `winget list` before install |
| Startup shortcut | `win_shortcut` with fixed `dest` — no-op if unchanged |
| Defender exclusion | Check `ExclusionPath -notcontains` before `Add-MpPreference` |

Second run = `changed=0`.

## Tag summary update

| Tag | What it does |
|---|---|
| `openrgb` | OpenRGB startup shortcut + Defender exclusion (bare-metal only) |

## Runtime impact

- ~20 Mo RAM resident (tray icon maintaining SMBus claim)
- 0% CPU after initial profile load
- No SMBus polling — write-once, hold claim
- No conflict with MSI Afterburner (separate I2C addresses)

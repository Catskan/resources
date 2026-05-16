# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal infrastructure / dotfiles-style monorepo. There is **no application, no test suite, no build pipeline at the repo root**. The content is a collection of Ansible playbooks, PowerShell/bash scripts and small standalone projects used to provision and maintain Aurélien's own machines (Windows gaming PC, Arch Linux laptop, MacBook Air = controller, NAS, VMs).

The center of gravity is **`Ansible/`**. Everything else is reference material.

## Execution model

**Ansible runs locally on the MacBook controller.** No cloud orchestration, no container wrapper, no Vagrant. The user installs `ansible` + collections directly on macOS and launches playbooks via `make` targets that wrap a thin `scripts/run.sh` (prompts the KeePass master password once, then `exec`s `ansible-playbook`).

This is a recent simplification — the repo used to push playbooks through GitHub Actions → AWS Secrets Manager → Vagrant → a Debian-Ansible Docker container. All of that has been removed. The only remaining workflow is `.github/workflows/ansible-lint.yml` (hosted Ubuntu, syntax check only).

## Ansible structure

Standard Ansible role layout. Playbooks call real roles via `roles:`, vars load automatically from `inventory/{group_vars,host_vars}/`.

- **Entry points** at `Ansible/main_*_playbook.yml` are thin (hosts + one `roles:` entry):
  - `main_windows_playbook.yml` → role `windows_gaming` on `windows_hosts` (`aurelien-gaming`, `w11-vm-aurel`)
  - `main_linux_playbook.yml` → roles `linux_laptop` + `common` on `arch-linux-laptop`
  - `main_remove_softwares.yml` → `include_role tasks_from: appx_bloatware.yml` against `aurelien-gaming`
- **Standalone playbooks** at `Ansible/playbooks/`:
  - `blog_maman_deploy.yml` / `blog_maman_remove.yml` — Docker container `catskan/fonduededeco:v1` on the MacBook (uses `ansible_connection: local`)
- **Roles** at `Ansible/roles/`:
  - `windows_gaming/` — main Windows role. Owns `tasks/main.yml` (orchestrator with tags), `templates/synology_config_win.json.j2`, `files/bootstrap_winrm.ps1`.
  - `common/` — Firefox policies (cross-platform).
  - `linux_laptop/` — Arch Linux laptop tasks.
- **Inventory** at `Ansible/inventory/`:
  - `hosts.yaml` — groups `linux_hosts` / `windows_hosts`.
  - `group_vars/all/{main,secrets}.yml` — common to every host.
  - `group_vars/windows_hosts/{connection,main}.yml` — WinRM + Windows-common vars.
  - `host_vars/<host>/{connection,main,secrets}.yml` — `aurelien-gaming`, `w11-vm-aurel`, `arch-linux-laptop`, `macbook-air-aurelien` (this last one is the controller — `ansible_connection: local`). The remaining hosts (`arch-linux-vm`) are still flat `host_vars/<host>` files.
- **Secrets — KeePass-backed**: every `secrets.yml` and the `ansible_password` line in `connection.yml` use `lookup('viczem.keepass.keepass', '<group>/<entry>', '<password|username>')`. The DB path defaults to `/Volumes/home/Drive/Vault/Aurel-vault.kdbx` — the Synology NAS share `home` mounted via SMB (the share must be mounted before any run, otherwise `scripts/run.sh` aborts with "KeePass DB introuvable"). Override via `KEEPASS_LOCATION` to point at a local copy. The master password is prompted at run-time by `scripts/run.sh` (no caching). Required collection: `viczem.keepass`. Python deps: `pykeepass`, `pyyaml` (the latter only for `scripts/inspect_keepass.py`).

> **Migration in progress**: secrets were previously sourced from AWS Secrets Manager (`lookup('amazon.aws.aws_secret', ...)`). The lookup expressions in `*/secrets.yml` and `*/connection.yml` may still reference the AWS variant — finish the swap to KeePass when migrating remaining entries. The `inventory/host_vars/macbook-air-aurelien/secrets.yml` was vault-encrypted under the old scheme and may still be a `$ANSIBLE_VAULT` blob until migrated.

### Tags (rôle `windows_gaming`)

| Tag                | What it does                                                                                                         |
| ------------------ | -------------------------------------------------------------------------------------------------------------------- |
| `bootstrap`        | WinRM startup, UAC, AdminAutoLogon (1ʳᵉ install only)                                                                |
| `system`           | power plan, services, NAS mounts, MS account credential                                                              |
| `rdp`, `wol`       | the corresponding subsystems                                                                                         |
| `user_folders`     | redirect User Shell Folders to `M:\Aurel`                                                                            |
| `defender`         | Defender exclusions paths/processes/extensions + cloud reporting off                                                 |
| `gaming_optim`     | VBS off + weekly safety-reset + kernel/network/storage tweaks + Game DVR/Mode                                        |
| `console_ux`       | Debloat (AppX bloatware, Cortana, Bing, Widgets, OneDrive, Edge neutral, Firefox default, telemetry, notifications)  |
| `softwares_winget` | Install user apps + tooling via winget (Steam, Epic, Firefox, MSI Afterburner, NVCleanstall, …) + MS Store Xbox Acc. |
| `firefox`          | Firefox policies (cross-platform, from `common` role)                                                                |
| `drivers`          | AMD chipset (direct_url) + NVIDIA driver via NVCleanstall CLI + NVIDIA telemetry services off                        |
| `keepassxc`        | KeePassXC pointed at NAS vault UNC + tray autostart + Ctrl+Shift+V Auto-Type + Defender exclusion (bare-metal only)  |

### Running things

The Makefile is the canonical entry point. All targets prompt the KeePass master pw once via `scripts/run.sh`.

```bash
cd Ansible/
make windows                       # full run, Windows hosts
make linux                         # Arch laptop
make uninstall-bloat               # AppX bloatware only
make check-windows                 # dry-run --check --diff
make ping-windows                  # win_ping validation
make windows ARGS='--tags rdp,wol' # subset by tag
make windows ARGS='--tags softwares_winget' # winget chain only
make test-keepass                  # offline: every lookup must resolve
make inspect-keepass               # offline diagnostic + full DB tree dump
make inspect-keepass ARGS='--tree' # only dump the DB tree
make lint                          # yamllint + ansible-lint
```

Override the KeePass DB location (e.g. fall back to a local copy when the NAS isn't reachable): `KEEPASS_LOCATION=~/Vault/Aurel-vault.kdbx make windows`.

The Makefile uses `./scripts/run.sh <binary> <args>` so any Ansible binary can be wrapped (currently `ansible-playbook` and `ansible` for ad-hoc).

## `ansible.cfg`

Plain config now — `inventory=./inventory/hosts.yaml`, `roles_path=./roles`, the rest is the default scaffold. No more tokens, no more `cschleiden/replace-tokens`. Edit it like any normal Ansible config.

## CI

`.github/workflows/ansible-lint.yml` runs `yamllint` + `ansible-lint` on hosted Ubuntu against any push touching `Ansible/**`. Same thing locally with `make lint`. This is the only GHA workflow left in the repo.

## Other top-level directories (independent)

- `Containers/Linux/` — `blog-maman.dockerfile`, `build-nginx-ingress-image.sh`. Independent from Ansible.
- `Containers/Windows/{Aurelien-Soft,Fleet-agent}/` — Windows Docker images (LogMonitor, Fleet agent).
- `Microsoft-Resources/` — standalone PowerShell + Azure Logic Apps + ADO pipelines. Reference material. Two notable sub-trees:
  - `Microsoft-Resources/autounattend/` — bare-metal Win11 zero-touch install. `build-autounattend.sh` prompts the Aurel password, encodes it MS-style, renders `w11-baremetal.xml`, stages a `dist/usb-baremetal/` folder ready to copy-paste at the root of a Rufus-burned Win11 USB. Drop the extracted Asus B850 motherboard driver pack in `drivers-source/` (gitignored) — the builder bundles it into `$OEM$/$1/Drivers/`, the autounattend's first FirstLogonCommand runs `pnputil /add-driver C:\Drivers\*.inf /subdirs /install`. Setup itself asks only one question: the target partition (no `<DiskConfiguration>` block — protects existing M:\ data drives).
  - `Enable_winrm.ps1` previously lived here too — moved to `Ansible/roles/windows_gaming/files/bootstrap_winrm.ps1` as the source of truth for ad-hoc WinRM bootstrapping.
- `Linux-Resources/` — standalone scripts (GitHub runner installer, `exim4` echo service, code-server) and Arch Linux laptop settings.
- `softwares_configs/config-files/` — verbatim app config snapshots (Firefox, Synology Drive, GOG, Ubisoft Connect). The Bitwarden snapshot is legacy (user moved to KeePassXC). The Firefox `policies.json` is duplicated into `Ansible/roles/common/templates/firefox_policies.json` (source of truth for Ansible runs).
- `Projects/Curl + Github Actions + Terraform/` — a small self-contained side project. Treat as a separate codebase; the rest of this CLAUDE.md does not apply to it.

## Conventions worth knowing

- Path with spaces: `Projects/Curl + Github Actions + Terraform`. Always quote.
- Host names in playbooks/`when:` are real machines. Use `inventory_hostname` for host conditionals, **not** `ansible_hostname` or `ansible_facts['netbios_name']` — those got normalized during the refactor (the netbios `Aurel-Gaming` doesn't match the inventory key `aurelien-gaming`).
- Case-insensitive filesystem warning: macOS APFS treats `Roles` and `roles` as the same name. `git mv` case-only renames need a tmp step (`git mv Foo Foo_tmp && git mv Foo_tmp foo`).
- `.gitignore` covers `.DS_STORE`, `**/.vagrant` (legacy), `Containers/Linux/Debian-Ansible/.ssh` (legacy), `Vagrant/Ansible/*/.env` (legacy). These `.vagrant` / Vagrant entries can be pruned now that Vagrant is gone.

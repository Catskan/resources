# drivers-source/

Drop the **extracted** Asus B850 motherboard driver pack here before running
`./build-autounattend.sh`. The builder copies everything in this folder
recursively into `dist/usb-baremetal/$OEM$/$1/Drivers/`. Windows Setup then
copies that to `C:\Drivers\` during install, and the autounattend's first
FirstLogonCommand runs:

```cmd
pnputil /add-driver C:\Drivers\*.inf /subdirs /install
```

So any `.inf` we drop here — at any depth — gets installed automatically.

## Where to get the drivers

1. <https://www.asus.com/motherboards-amd-am5/tuf-gaming-b850-plus-wifi/helpdesk_download/>
   (or whatever your exact B850 model page is)
2. Download the full driver bundle (Chipset, LAN, Audio, USB, etc.).
3. Each downloaded `.exe` is typically a self-extracting installer that
   **also** contains the raw INF folders inside. Two options:
   - Run the `.exe` once to a temp dir; rummage in `C:\Asus\...` for the
     INF subfolders, then copy those subfolders here.
   - OR use 7-Zip's "Extract here" on the `.exe` directly — most Asus
     setups expose the INF tree without needing to actually install.
4. Drop the resulting INF subfolders here. Layout suggestion:

```
drivers-source/
├── chipset/
│   └── (AMD chipset INF files)
├── lan/
│   └── (Realtek / Intel 2.5G NIC INF files)
├── audio/
└── usb/
```

The folder structure itself doesn't matter — pnputil scans recursively for
`.inf` files. Just keep it readable.

## What NOT to include

- The raw `.exe` installers — pnputil ignores them, and they bloat the USB.
- Anything that requires running an installer to function (rare on modern
  Asus boards; the chipset bundle in particular is INF-driven).
- NVIDIA driver — handled by Ansible's `drivers.yml` via NVCleanstall
  post-install. No need here.
- AMD CPU/GPU drivers — same, AMD chipset itself IS handled by Ansible
  `drivers.yml`, but slipstreaming the INFs here is a nice belt-and-braces
  on a freshly-built machine that hasn't yet been on the network.

## Gitignored

This folder's contents are excluded from git (large + licensed). Only this
README is tracked.

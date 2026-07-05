# Checklist BIOS & pilote — ASUS B850 / AM5 (9800X3D + RX 9070 XT)

> **Pourquoi ce fichier ?** Les optimisations plateforme les plus impactantes ne
> sont **pas automatisables par Ansible** (réglages firmware/BIOS et blob pilote
> Adrenalin). Le rôle `windows_gaming` fait tout le reste côté OS. Cette
> checklist couvre le manuel, à repasser après un flash BIOS ou un bare-metal.
>
> La tâche `gaming_optim.yml` « report ReBAR / EXPO / write-cache » vérifie
> a posteriori (au run Ansible) que ReBAR et EXPO sont bien actifs.

## BIOS — ASUS B850 (⚙️ = à activer/vérifier)

### Perf (gros gains)

- [ ] **Re-Size BAR Support = Enabled** + **Above 4G Decoding = Enabled**
      (`Advanced → PCI Subsystem Settings`). Smart Access Memory : +5-15 % sur RDNA4.
      Vérif Windows : Adrenalin → Performance → « Smart Access Memory: Enabled ».
- [ ] **EXPO I = Enabled** (`AI Tweaker`) → DDR5-6000, FCLK auto. Le plus gros
      écart si la RAM tourne encore en JEDEC 4800.
- [ ] _(avancé, optionnel)_ **PBO → Curve Optimizer** all-core **-15** en point de
      départ, puis validation longue (CoreCycler/OCCT). -5-10 °C, boost soutenu.
      ⚠️ Instabilité sournoise si non testé — ne pas déployer sans campagne.

### Fiabilité / réveil (indispensables pour ce setup)

- [ ] **ErP Ready = Disabled** — sinon coupe l'alim en veille/arrêt et **casse le
      Wake-on-LAN** (essentiel pour vinted-bot + réveil Moonlight).
- [ ] **Restore AC Power Loss = Last State** (`Advanced → APM Configuration`) —
      après coupure secteur, le PC reprend son état (comportement console).
- [ ] **Wake on LAN / Power On By PCI-E = Enabled** — réveil réseau depuis l'arrêt.
- [ ] Secure Boot + fTPM activés (prérequis Win11, normalement déjà OK).

## Pilote AMD Adrenalin (manuel — blob non scriptable proprement)

- [ ] **Radeon Anti-Lag 2 = Enabled** (Gaming → Graphics) — latence input réduite
      (Adrenalin ≥ 26.5.1).
- [ ] **Advanced Shader Delivery = ON** — shaders pré-compilés cloud → fini le
      stutter de compilation (très « esprit console »).
- [ ] Vérifier **Smart Access Memory: Enabled** (reflète ReBAR côté BIOS).
- [ ] **Enhanced Sync = Enabled** (Gaming → Graphics, global) — réduit la latence
      d'~1 frame en streaming Sunshine (reco AMD). Stocké dans `gmdb.blb` (blob
      binaire, vérifié : modifié pile à l'activation) → **non scriptable**, à
      ré-cocher après un DDU / reset pilote.
- [ ] Ne **PAS** activer Radeon Chill ni Radeon Boost (ajoutent de la latence input ;
      les clés `KMD_ChillEnabled` / `KMD_RadeonBoostEnabled` sont déjà à `0`).

## Déjà géré par Ansible (rien à faire au BIOS/manuel)

Driver chipset AMD, GPU Adrenalin (install), plan d'alim Balanced (optimal X3D),
HPET off + `tscsyncpolicy Enhanced`, VBS/HVCI off, USB selective suspend off,
PCIe ASPM off, NIC Realtek anti-éco, Nagle off, NTFS, Win32PrioritySeparation,
Fast Startup off (via hibernation off) — cf. rôle `windows_gaming`.

## À NE PAS faire (tranché par la recherche perf 2026)

Core parking / CPPC preferred cores (inutile : 9800X3D mono-CCD), `bcdedit
disabledynamictick`, MPO off (`OverlayTestMode=5` ignoré sur 25H2 + peut
augmenter la latence borderless), ISLC / purge standby list, timer resolution
forcée.

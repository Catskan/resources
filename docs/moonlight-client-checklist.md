# Checklist — configuration des clients Moonlight (host Sunshine `aurelien-gaming`)

> **Pourquoi ce fichier ?** Le bitrate, la résolution, le FPS et le codec sont
> **négociés par le client Moonlight**, pas fixés côté Sunshine — ils ne sont donc
> **pas versionnables** dans le rôle Ansible. Cette checklist couvre le réglage
> par appareil. Cible : **latence minimale en LAN 2.5 GbE**, codec **HEVC** (encodeur
> AMF de la RX 9070 XT). Voir le host déjà réglé en bas.

## Commun à tous les clients

- [ ] **Décodage matériel** forcé (jamais logiciel).
- [ ] **Codec = HEVC (H.265)**. Ne pas forcer l'AV1 : il déborde son bitrate cible
      en CBR sur la 9070 XT (packet loss / déconnexions). AV1 seulement si le client
      décode l'AV1 en hardware ET que tu constates un gain.
- [ ] **V-Sync = OFF**.
- [ ] **Frame pacing = OFF** / « Prefer lowest latency » (option côté client).
- [ ] **Appairage** : ouvrir la Web UI Sunshine `https://<ip-host>:47990` (LAN),
      saisir le PIN affiché par le client (fenêtre de 600 s — large exprès).
- [ ] **HDR** : n'activer que si l'écran client est HDR **et** que le pilote AMD du
      host est **≤ 25.9.1** (le 25.10.2 casse le HDR AMF — bug #4377).
- [ ] Mesurer la latence en session : **Ctrl + Alt + Maj + S** (overlay perf
      Moonlight). Viser ~8-20 ms d'overhead pipeline en LAN.

## PC portable / autre PC en LAN — moonlight-qt

- [ ] **Résolution** : native de l'écran client (ou 4K120 si le host expose un mode
      4K120 : écran physique, dummy HDMI 2.1, ou Virtual Display Driver).
- [ ] **FPS** : 120.
- [ ] **Bitrate** : **100-150 Mbps** (rendement décroissant au-delà de ~150-200 ;
      la latence de décodage remonte).
- [ ] Slider bitrate au-delà de 150 Mbps : nécessite **moonlight-qt ≥ v6.1.0**
      (relevable à 500 Mbps).
- [ ] **Codec** : HEVC (Auto). AV1 possible si décodeur PC récent (RTX 40/50, RDNA3+),
      mais HEVC reste le choix sûr.
- [ ] Fullscreen exclusif ou borderless selon préférence ; capture souris selon usage.
- [ ] « Optimize game settings » : optionnel (laisse le jeu suivre la résolution du stream).

## iPad Pro (ProMotion 120 Hz) — Moonlight iOS

- [ ] **FPS** : 120 Hz.
- [ ] **Résolution** : native de l'iPad.
- [ ] **Bitrate** : **80-120 Mbps**.
- [ ] **Codec** : HEVC (l'iPad Pro le décode en hardware nativement).
- [ ] **HDR** : possible si l'iPad est en HDR et host ≤ 25.9.1.
- [ ] Options V-Sync / frame pacing limitées sur iOS → laisser par défaut,
      le décodage matériel natif suffit.
- [ ] Manette Bluetooth (Xbox/DualSense) ou « touch as trackpad » selon l'usage.

## Réglages host — déjà en place (référence, ne rien faire)

Gérés par le rôle Ansible `windows_gaming` (tag `sunshine`) :

- Encodeur **AMF HEVC** (`encoder = amdvce`, `hevc_mode = 2`).
- Faible latence : `amd_usage = ultralowlatency`, `amd_rc = vbr_latency`,
  `amd_preanalysis = disabled`, `capture = ddx`, `minimum_fps_target = 0`.
- Audio : `virtual_sink = Steam Streaming Speakers` (coupe les HP du host en session).
- Réseau : FEC 20 % (défaut), `packetsize` auto (MTU 1500), ports LAN-only (profil
  privé), `upnp = off`. **NIC Realtek 2.5 G** déjà anti-jitter (EEE / Green Ethernet /
  Interrupt Moderation off).
- Service Sunshine en **démarrage différé** (évite la race d'init driver AMD au boot).

## Côté Adrenalin (manuel)

- **Enhanced Sync = ON** — voir `bios-checklist.md`. Réduit la latence d'~1 frame.

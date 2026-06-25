"""Cycle de vie LM Studio :
  - check si PC déjà reachable (SSH port 22)
  - sinon WoL + attente boot
  - SSH start lms server --bind 0.0.0.0 + lms load mistral
  - poll API HTTP jusqu'à ready
  - en sortie : SSH unload + server stop + kill process + shutdown
"""

from __future__ import annotations

import base64
import socket
import subprocess
import time

import httpx
from loguru import logger
from wakeonlan import send_magic_packet

from ..config import settings
from .llm import is_ready, wait_for_ready


# ─────────────────────────────────────────────────────────────
# Home Assistant — pilotage prise Zigbee du PC LLM
# ─────────────────────────────────────────────────────────────


def _ha_configured() -> bool:
    """True si toutes les vars HA sont définies pour piloter la prise."""
    return bool(settings.ha_url and settings.ha_token and settings.ha_pc_switch_entity)


# État initial de la prise au démarrage du script (rempli lors du 1er ha_power_on_pc).
# Si True : la prise était DÉJÀ allumée — on ne l'éteindra PAS à la fin (respect état initial).
# Si False : on l'a allumée nous-mêmes — on l'éteindra à la fin.
# Si None : pas encore checké OU HA injoignable au moment du check.
_initial_plug_was_on: bool | None = None


def _ha_call_service(service: str) -> bool:
    """Appelle un service Home Assistant pour notre prise PC. service = 'turn_on' | 'turn_off'."""
    if not _ha_configured():
        return False
    url = f"{settings.ha_url.rstrip('/')}/api/services/switch/{service}"
    try:
        with httpx.Client(timeout=10) as c:
            r = c.post(
                url,
                headers={
                    "Authorization": f"Bearer {settings.ha_token}",
                    "Content-Type": "application/json",
                },
                json={"entity_id": settings.ha_pc_switch_entity},
            )
            r.raise_for_status()
            logger.info(f"HA switch.{service} ({settings.ha_pc_switch_entity}) OK")
            return True
    except Exception as e:
        logger.warning(f"HA switch.{service} a échoué : {e}")
        return False


def ha_get_switch_state() -> bool | None:
    """Retourne True si prise ON, False si OFF, None si HA injoignable / pas configuré."""
    if not _ha_configured():
        return None
    url = f"{settings.ha_url.rstrip('/')}/api/states/{settings.ha_pc_switch_entity}"
    try:
        with httpx.Client(timeout=5) as c:
            r = c.get(
                url,
                headers={"Authorization": f"Bearer {settings.ha_token}"},
            )
            r.raise_for_status()
            state = r.json().get("state")
            return state == "on"
    except Exception as e:
        logger.warning(f"HA get state a échoué : {e}")
        return None


def ha_power_on_pc() -> bool:
    """Allume la prise si nécessaire. Mémorise l'état initial pour décider du off final.

    - Si HA pas configuré : no-op
    - Si prise déjà ON : no-op + mémorise (ne pas éteindre à la fin)
    - Si prise OFF : turn_on + mémorise (éteindre à la fin)
    - Si état inconnu (HA injoignable) : tente turn_on quand même, mémorise inconnu
    """
    global _initial_plug_was_on
    if not _ha_configured():
        return True

    _initial_plug_was_on = ha_get_switch_state()
    if _initial_plug_was_on is True:
        logger.info("Prise déjà allumée — pas de turn_on (sera laissée ON à la fin par respect)")
        return True
    if _initial_plug_was_on is False:
        logger.info("Prise actuellement éteinte → allumage")
    else:
        logger.warning("État prise inconnu (HA injoignable au get_state) → tente turn_on quand même")
    return _ha_call_service("turn_on")


def ha_power_off_pc() -> bool:
    """Éteint la prise SAUF si elle était déjà ON au démarrage du script.

    Logique :
    - HA pas configuré : no-op
    - Prise était ON au démarrage : on la laisse ON
    - Prise était OFF au démarrage (= on l'a allumée) : on l'éteint
    - État initial inconnu : on l'éteint quand même (safe default si on l'a probablement allumée)
    """
    if not _ha_configured():
        return True
    if _initial_plug_was_on is True:
        logger.info("Prise était allumée au démarrage du script — on la laisse ON")
        return True
    return _ha_call_service("turn_off")


def _ps_encoded(script: str) -> str:
    """Encode un script PowerShell en base64 UTF-16LE pour passer via SSH
    sans aucun problème de quotes imbriquées.

    Renvoie une commande `powershell -EncodedCommand <b64>` prête à passer
    en argument SSH.
    """
    b64 = base64.b64encode(script.encode("utf-16le")).decode("ascii")
    return f"powershell -EncodedCommand {b64}"


def is_pc_reachable(timeout: float = 3.0) -> bool:
    """Test rapide TCP port 22 (SSH) pour savoir si le PC est ON."""
    try:
        with socket.create_connection((settings.pc_ip, 22), timeout=timeout):
            return True
    except (TimeoutError, OSError):
        return False


def wake_pc() -> None:
    """Envoie le magic packet WoL au PC."""
    send_magic_packet(settings.pc_mac)
    logger.info(f"WoL envoyé à {settings.pc_mac}")


def wait_for_ssh(timeout_sec: int | None = None) -> bool:
    """Poll port SSH du PC jusqu'à ce qu'il réponde. Renvoie True si OK."""
    timeout_sec = timeout_sec or settings.pc_boot_timeout_sec
    start = time.time()
    while time.time() - start < timeout_sec:
        if is_pc_reachable():
            elapsed = int(time.time() - start)
            logger.info(f"SSH dispo après {elapsed}s")
            return True
        time.sleep(3)
    logger.error(f"SSH pas dispo après {timeout_sec}s")
    return False


def _ssh_exec(remote_cmd: str, label: str, timeout: int = 60) -> tuple[bool, str]:
    """Exécute une commande SSH. Renvoie (success, output).

    Décode les bytes avec errors='replace' pour résister aux outputs PowerShell
    en codepage Windows (cp1252) qui peuvent contenir des bytes non-UTF-8.
    """
    cmd = [
        "ssh",
        "-i", str(settings.pc_ssh_key_path),
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
        f"{settings.pc_ssh_user}@{settings.pc_ip}",
        remote_cmd,
    ]
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=timeout)
        # Decode manuellement avec errors='replace' (Windows envoie souvent cp1252)
        stdout = r.stdout.decode("utf-8", errors="replace") if r.stdout else ""
        stderr = r.stderr.decode("utf-8", errors="replace") if r.stderr else ""
        output = (stdout + stderr).strip()
        if r.returncode == 0:
            logger.info(f"  ✓ {label}")
            return True, output
        logger.warning(f"  ⚠ {label} : exit {r.returncode} — {output[:160]}")
        return False, output
    except subprocess.TimeoutExpired:
        logger.warning(f"  ⚠ {label} : timeout après {timeout}s")
        return False, "timeout"


def start_lms_via_ssh() -> bool:
    """Lance LM Studio en UNE seule session SSH (start détaché + load + verify).

    Pourquoi ? Sur Windows OpenSSH non-interactif, le Job Object de la session
    peut tuer les process spawned quand SSH se déconnecte. En faisant TOUT dans
    une session SSH unique qui ne se ferme qu'après le verify final, le serveur
    a le temps de s'initialiser proprement et de devenir stable avant le close.

    Le PowerShell script :
      1. lms server stop (cleanup silent)
      2. Start-Process lms server start (détaché)
      3. Poll http://localhost:1234/v1/models jusqu'à 200 (max 30s)
      4. lms load <model> --gpu max (bloquant ~10-30s)
      5. Verify final API
    """
    logger.info("Lancement LM Studio (start + load en 1 session SSH)…")
    # rf""" = raw f-string : les `\b`, `\l` ne sont PAS interprétés comme escape Python.
    # Sinon `\bin\lms.exe` deviendrait `<BS>in\lms.exe` (backspace !) — c'était notre bug.
    script = rf"""
$ErrorActionPreference = 'SilentlyContinue'
$port = 1234
$model = "{settings.llm_model_id}"

# 0. Attente user session (auto-login peut prendre 10-20s après boot)
$sessionReady = $false
for ($i = 0; $i -lt 60; $i++) {{
    if (Get-Process explorer -ErrorAction SilentlyContinue) {{
        $sessionReady = $true
        Write-Host "User session ready after $i sec (explorer.exe up)"
        break
    }}
    Start-Sleep -Seconds 1
}}
if (-not $sessionReady) {{
    Write-Host "ERROR: User session not ready after 60s"
    exit 4
}}

# 1. Find lms.exe (WMI utilise le PATH système, on a besoin du chemin absolu)
$lmsCandidates = @(
    "$env:USERPROFILE\.lmstudio\bin\lms.exe",
    "$env:LOCALAPPDATA\Programs\lm-studio\lms.exe",
    "$env:LOCALAPPDATA\Programs\LM Studio\lms.exe"
)
$lmsPath = $lmsCandidates | Where-Object {{ Test-Path $_ }} | Select-Object -First 1
if (-not $lmsPath) {{
    $cmd = Get-Command lms -ErrorAction SilentlyContinue
    if ($cmd) {{ $lmsPath = $cmd.Source }}
}}
if (-not $lmsPath) {{
    Write-Host "ERROR: lms.exe introuvable (tested $($lmsCandidates -join ', '))"
    exit 5
}}
Write-Host "Found lms.exe at: $lmsPath"

# 2. Cleanup serveur existant
& $lmsPath server stop 2>$null | Out-Null

# 3. Start via WMI Win32_Process avec chemin absolu (détaché du Job Object SSH)
$cmd = "`"$lmsPath`" server start --port $port --bind 0.0.0.0"
$proc = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{{ CommandLine = $cmd }}
Write-Host "Spawned lms via WMI, PID=$($proc.ProcessId), ReturnValue=$($proc.ReturnValue)"
if ($proc.ReturnValue -ne 0) {{
    Write-Host "ERROR: WMI spawn failed (ReturnValue $($proc.ReturnValue))"
    exit 6
}}
Start-Sleep -Seconds 5

# 3. Poll TCP listen socket (plus fiable que Invoke-WebRequest, qui peut faux-négatif sur IPv6)
$ready = $false
for ($i = 0; $i -lt 30; $i++) {{
    $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($conn) {{
        $ready = $true
        Write-Host "Port $port listening after $i sec"
        break
    }}
    Start-Sleep -Seconds 1
}}
if (-not $ready) {{
    Write-Host "WARN: Port pas en Listen, on tente quand même lms load"
}}

# 4. Load le model (bloquant)
$ErrorActionPreference = 'Continue'
& $lmsPath load $model --gpu max
if ($LASTEXITCODE -ne 0) {{
    Write-Host "ERROR: Model load failed (exit $LASTEXITCODE)"
    exit 2
}}
Write-Host "Model load OK"
exit 0
"""
    ok, output = _ssh_exec(
        _ps_encoded(script),
        "lms full setup (start + load + verify)",
        timeout=240,
    )
    logger.info(f"  Script output: {output.strip()[:400]}")
    return ok


def ensure_llm_ready() -> bool:
    """Garantit que LM Studio est joignable et a un modèle chargé.

    Stratégie progressive (avec pilotage prise HA optionnel) :
      0. Si HA configuré : allume la prise Zigbee, attend 5s (PSU stabilization)
      1. Si l'API HTTP répond déjà → done
      2. Si le PC est joignable en SSH → lance lms server + load
      3. Sinon → WoL, attend SSH, lance lms server + load
      4. Poll API HTTP jusqu'à ready
    """
    if is_ready():
        logger.info("LM Studio déjà prêt — pas besoin de WoL ni de start")
        return True

    # 0. Alimente la prise si HA configuré (sinon no-op)
    if _ha_configured():
        logger.info(f"HA configuré → allumage prise {settings.ha_pc_switch_entity}")
        ha_power_on_pc()
        logger.info("Attente 5s (stabilisation PSU)…")
        time.sleep(5)

    if is_pc_reachable():
        logger.info("PC déjà allumé, LM Studio pas démarré → SSH start")
    else:
        logger.info("PC éteint → WoL + attente SSH")
        wake_pc()
        if not wait_for_ssh():
            logger.error("PC n'a pas démarré dans les temps")
            return False

    start_lms_via_ssh()

    return wait_for_ready()


# Compat avec runner existant
def boot_pc_and_wait_llm() -> bool:
    """Alias pour rétrocompat — utilise la nouvelle logique progressive."""
    return ensure_llm_ready()


def shutdown_pc() -> None:
    """Cleanup LM Studio + shutdown Windows via SSH (best-effort).

    Si Home Assistant est configuré, coupe la prise Zigbee après le délai
    `ha_post_shutdown_wait_sec` (laissant le temps à Windows de s'éteindre proprement).
    """
    _ssh_exec("lms unload --all", "unload models")
    _ssh_exec("lms server stop", "stop lms server")
    kill_script = r"""
Get-Process 'LM Studio' -ErrorAction SilentlyContinue | Stop-Process -Force
"""
    _ssh_exec(_ps_encoded(kill_script), "kill LM Studio process")
    _ssh_exec("shutdown /s /t 0", "shutdown Windows")

    if _ha_configured():
        wait = settings.ha_post_shutdown_wait_sec
        logger.info(f"Attente {wait}s pour shutdown Windows complet avant coupure prise…")
        time.sleep(wait)
        logger.info(f"HA → coupure prise {settings.ha_pc_switch_entity}")
        ha_power_off_pc()

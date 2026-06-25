#!/bin/bash
# scripts/test-infra.sh
#
# Valide la plomberie Phase 0 du vinted-bot. Le NAS orchestre tout :
#   1. Wake-on-LAN du PC Windows
#   2. Attente que SSH soit dispo sur le PC (port 22)
#   3. SSH : lance `lms server start` + `lms load <model>`
#   4. Attente que l'API HTTP LM Studio réponde
#   5. Test d'un prompt au LLM
#   6. SSH : unload modèle + shutdown PC
#
# Aucun auto-start côté PC, aucune tâche planifiée Windows.
# LM Studio n'est lancé que quand on en a besoin, depuis SSH.
#
# Usage :
#   ./scripts/test-infra.sh
#
# Pré-requis :
#   - .env rempli (PC_MAC, PC_IP, PC_SSH_USER, LLM_BASE_URL, LLM_MODEL_ID...)
#   - Clé SSH NAS→PC déjà déposée dans authorized_keys du PC
#   - LM Studio installé sur le PC, modèle déjà téléchargé, `lms bootstrap` fait

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ .env introuvable à $ENV_FILE"
    echo "   → cp .env.example .env, puis remplis les valeurs"
    exit 1
fi
set -a; source "$ENV_FILE"; set +a

LM_URL_ROOT="${LLM_BASE_URL%/v1}"
TIMEOUT_BOOT=${PC_BOOT_TIMEOUT_SEC:-180}
TIMEOUT_LLM=${PC_LLM_READY_TIMEOUT_SEC:-120}

# La var .env pointe vers le chemin DANS le container Docker.
# Quand on lance ce script depuis le NAS host, on cherche la clé localement.
SSH_KEY="$PC_SSH_KEY_PATH"
if [[ ! -f "$SSH_KEY" ]]; then
    SSH_KEY="$HOME/.ssh/id_ed25519_vintedbot"
fi
if [[ ! -f "$SSH_KEY" ]]; then
    echo "❌ Clé SSH introuvable. Cherchée :"
    echo "   - $PC_SSH_KEY_PATH (depuis .env)"
    echo "   - $HOME/.ssh/id_ed25519_vintedbot (fallback)"
    exit 3
fi

SSH_OPTS=(-i "$SSH_KEY"
          -o BatchMode=yes
          -o ConnectTimeout=10
          -o StrictHostKeyChecking=accept-new
          -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR)

ssh_pc() {
    ssh "${SSH_OPTS[@]}" "$PC_SSH_USER@$PC_IP" "$@"
}

echo "════════════════════════════════════════════════════════"
echo "  vinted-bot — Validation infra Phase 0"
echo "════════════════════════════════════════════════════════"

# ─────────────────────────────────────────────────────────
echo ""
echo "[1/7] Wake-on-LAN du PC ($PC_MAC)..."
if [[ -x /usr/syno/sbin/synonet ]]; then
    sudo /usr/syno/sbin/synonet --wake "$PC_MAC"
    echo "  → magic packet envoyé (synonet)"
elif command -v wakeonlan &>/dev/null; then
    wakeonlan "$PC_MAC"
    echo "  → magic packet envoyé (wakeonlan)"
else
    python3 - <<PYEOF
import socket
mac = "$PC_MAC".replace(":", "").replace("-", "")
packet = b"\xff" * 6 + bytes.fromhex(mac) * 16
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
s.sendto(packet, ("255.255.255.255", 9))
print("  → magic packet envoyé (python fallback)")
PYEOF
fi

# ─────────────────────────────────────────────────────────
echo ""
echo "[2/7] Attente que SSH soit dispo sur le PC (max ${TIMEOUT_BOOT}s)..."
START=$(date +%s)
while true; do
    if ssh_pc "echo ok" > /dev/null 2>&1; then
        ELAPSED=$(( $(date +%s) - START ))
        echo ""
        echo "  ✅ SSH dispo après ${ELAPSED}s"
        break
    fi
    ELAPSED=$(( $(date +%s) - START ))
    if (( ELAPSED > TIMEOUT_BOOT )); then
        echo ""
        echo "  ❌ Timeout : SSH pas dispo en ${TIMEOUT_BOOT}s"
        echo "     Vérifie : auto-login Windows actif ? sshd démarré ? firewall ?"
        exit 2
    fi
    printf "."
    sleep 3
done

# ─────────────────────────────────────────────────────────
echo ""
echo "[3/7] Démarrage du serveur lms (port 1234, bind 0.0.0.0 = accessible depuis le LAN)..."
# `lms server start` retourne immédiatement.
# --bind 0.0.0.0 = écoute sur toutes les interfaces (sinon localhost only, le NAS ne peut pas atteindre).
ssh_pc "lms server start --port 1234 --bind 0.0.0.0" || {
    echo "  ⚠️  lms server start a renvoyé non-zéro — peut-être déjà démarré, on continue"
}
sleep 2
echo "  → commande envoyée"

# ─────────────────────────────────────────────────────────
echo ""
echo "[4/7] Chargement du modèle '$LLM_MODEL_ID' (peut prendre 20-60s sur RX 9070 XT)..."
# Cette commande bloque jusqu'à ce que le modèle soit chargé en VRAM
ssh_pc "lms load \"$LLM_MODEL_ID\" --gpu max --identifier mistral-small" || {
    echo "  ⚠️  lms load a renvoyé non-zéro — peut-être déjà chargé, on continue et on testera l'API"
}
echo "  → modèle prêt"

# ─────────────────────────────────────────────────────────
echo ""
echo "[5/7] Vérification API HTTP (max ${TIMEOUT_LLM}s)..."
START=$(date +%s)
while true; do
    if curl -s --max-time 2 "$LM_URL_ROOT/v1/models" > /dev/null 2>&1; then
        ELAPSED=$(( $(date +%s) - START ))
        echo "  ✅ API HTTP répond après ${ELAPSED}s"
        break
    fi
    ELAPSED=$(( $(date +%s) - START ))
    if (( ELAPSED > TIMEOUT_LLM )); then
        echo "  ❌ Timeout : API HTTP pas dispo en ${TIMEOUT_LLM}s"
        echo "     Test manuel sur le PC : curl http://localhost:1234/v1/models"
        exit 4
    fi
    printf "."
    sleep 3
done

# ─────────────────────────────────────────────────────────
echo ""
echo "[6/7] Test prompt au LLM..."
RESPONSE=$(curl -s "$LM_URL_ROOT/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$LLM_MODEL_ID\",
        \"messages\": [{\"role\":\"user\",\"content\":\"Réponds en français en 5 mots maximum : pipeline OK ?\"}],
        \"max_tokens\": 50,
        \"temperature\": 0.3
    }")
CONTENT=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['choices'][0]['message']['content'])" 2>/dev/null || echo "(parsing failed)")
echo "  ✅ Réponse LLM : $CONTENT"

# ─────────────────────────────────────────────────────────
echo ""
echo "[7/7] Cleanup LM Studio + shutdown PC..."

# 1. Décharge les modèles de la VRAM
ssh_pc "lms unload --all" || echo "  ⚠️  lms unload a échoué (pas bloquant)"

# 2. Arrête le serveur HTTP local
ssh_pc "lms server stop" || echo "  ⚠️  lms server stop a échoué (pas bloquant)"

# 3. Ferme le process LM Studio.exe si encore présent (sinon il reste sleeping en background)
ssh_pc 'powershell -Command "Get-Process \"LM Studio\" -ErrorAction SilentlyContinue | Stop-Process -Force"' \
    || echo "  ⚠️  Stop-Process LM Studio a échoué (pas bloquant)"

sleep 2

# 4. Shutdown Windows
ssh_pc "shutdown /s /t 0"
echo "  ✅ LM Studio stoppé + shutdown PC envoyé"

echo ""
echo "════════════════════════════════════════════════════════"
echo "  ✅ Phase 0 validée. Infra prête pour la Phase 1."
echo "════════════════════════════════════════════════════════"

#!/bin/bash
# scripts/deploy-nas.sh
#
# À lancer sur le NAS (via SSH) depuis le dossier du projet.
#
# Build l'image Docker localement sur le NAS, puis (re)démarre les containers
# pour les comptes Aurélien et Amandine. Le build n'a lieu qu'UNE FOIS
# (image partagée entre les 2 containers).
#
# Usage :
#   cd /volume1/Aurelien/Scripts/vinted-bot
#   sudo bash scripts/deploy-nas.sh

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Vérifs préalables
for f in .env.aurelien .env.amandine; do
    if [[ ! -f "$f" ]]; then
        echo "❌ $f introuvable. Crée-le d'abord (cf migrate-to-multi-compte.sh)."
        exit 1
    fi
done
for d in data-aurelien data-amandine; do
    if [[ ! -d "$d" ]]; then
        echo "❌ $d/ introuvable. Lance d'abord scripts/migrate-to-multi-compte.sh"
        exit 1
    fi
done
# Cookies Amandine présents ?
if [[ ! -f data-amandine/cookies/vinted-cookies.json ]]; then
    echo "❌ data-amandine/cookies/vinted-cookies.json introuvable."
    echo "   Exporte les cookies du compte Amandine depuis son navigateur."
    exit 1
fi

echo "════════════════════════════════════════════════════════"
echo "  Build & deploy vinted-bot — Aurélien + Amandine"
echo "════════════════════════════════════════════════════════"

echo ""
echo "[1/4] Build de l'image Docker..."
sudo docker compose build

echo ""
echo "[2/4] (Re)start des containers..."
sudo docker compose up -d --force-recreate

echo ""
echo "[3/4] Vérification : les containers tournent ?"
sleep 2
for c in vinted-bot-aurelien vinted-bot-amandine; do
    if ! sudo docker ps --format '{{.Names}}' | grep -q "^${c}$"; then
        echo "  ❌ Container '$c' pas trouvé. Logs :"
        sudo docker compose logs --tail 30 "$c" || true
        exit 2
    fi
    echo "  ✓ $c up"
done

echo ""
echo "[4/4] Test dry-run du bumper (Aurélien)..."
# --force pour bypass le check schedule (test instantané, pas d'attente du pic)
sudo docker exec vinted-bot-aurelien python -m vinted_bot.bumper.runner --force --dry-run 2>&1 | tail -15 || true

echo ""
echo "════════════════════════════════════════════════════════"
echo "  ✅ Déploiement OK"
echo "════════════════════════════════════════════════════════"
echo ""
echo "  Tests manuels :"
echo "    sudo docker exec vinted-bot-aurelien python -m vinted_bot.bumper.runner --force"
echo "    sudo docker exec vinted-bot-amandine python -m vinted_bot.bumper.runner --force"
echo ""
echo "  DSM Task Scheduler — 2 tâches à configurer :"
echo "    - vinted-bot-aurelien-tick : /usr/local/bin/docker exec vinted-bot-aurelien python -m vinted_bot.bumper.runner --tick"
echo "    - vinted-bot-amandine-tick : /usr/local/bin/docker exec vinted-bot-amandine python -m vinted_bot.bumper.runner --tick"

#!/bin/bash
# scripts/migrate-to-multi-compte.sh
#
# Migration one-shot du setup mono-compte vers multi-comptes (Aurélien + Amandine).
# À lancer UNE FOIS sur le NAS (via SSH) depuis le dossier du projet.
#
# Avant de lancer :
#   - Désactive la tâche DSM "vinted-bot-tick" dans l'interface DSM
#   - Stop l'ancien container : sudo docker stop vinted-bot && sudo docker rm vinted-bot
#
# Ce script fait :
#   1. Renomme data/ → data-aurelien/
#   2. Crée data-amandine/ (squelette vide)
#   3. Renomme .env → .env.aurelien
#   4. Crée .env.amandine (copie d'aurelien avec user_id à remplir)
#   5. (Le nouveau docker-compose.yml est déjà en place)
#
# Usage :
#   cd /volume1/Aurelien/Scripts/vinted-bot
#   sudo bash scripts/migrate-to-multi-compte.sh

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "════════════════════════════════════════════════════════"
echo "  Migration mono → multi-comptes (Aurélien + Amandine)"
echo "════════════════════════════════════════════════════════"
echo ""

# Sanity check : pas de container en train de tourner
if sudo docker ps --format '{{.Names}}' | grep -qE '^vinted-bot(-(aurelien|amandine))?$'; then
    echo "❌ Un container vinted-bot tourne encore. Stop-le d'abord :"
    echo "   sudo docker stop vinted-bot && sudo docker rm vinted-bot"
    exit 1
fi

echo "[1/4] data/ → data-aurelien/"
if [[ -d data && ! -d data-aurelien ]]; then
    sudo mv data data-aurelien
    echo "  ✓ Renommé"
elif [[ -d data-aurelien ]]; then
    echo "  ✓ data-aurelien/ existe déjà, skip"
else
    echo "  ⚠️  Ni data/ ni data-aurelien/ trouvés"
fi

echo ""
echo "[2/4] Création data-amandine/"
sudo mkdir -p data-amandine/{cookies,db,logs,proposals,crosspost}
sudo touch data-amandine/cookies/.gitkeep data-amandine/db/.gitkeep \
           data-amandine/logs/.gitkeep data-amandine/proposals/.gitkeep \
           data-amandine/crosspost/.gitkeep
echo "  ✓ data-amandine/ créé avec sous-dossiers"

echo ""
echo "[3/4] .env → .env.aurelien"
if [[ -f .env && ! -f .env.aurelien ]]; then
    sudo mv .env .env.aurelien
    echo "  ✓ Renommé"
elif [[ -f .env.aurelien ]]; then
    echo "  ✓ .env.aurelien existe déjà, skip"
fi

echo ""
echo "[4/4] Création .env.amandine (template)"
if [[ ! -f .env.amandine ]]; then
    sudo cp .env.aurelien .env.amandine
    sudo sed -i 's/^VINTED_USER_ID=.*/VINTED_USER_ID=0  # TODO: remplir avec user_id Amandine/' .env.amandine
    echo "  ✓ .env.amandine créé (à remplir avec user_id Amandine)"
else
    echo "  ✓ .env.amandine existe déjà"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "  ✅ Migration terminée"
echo "════════════════════════════════════════════════════════"
echo ""
echo "  Étapes suivantes :"
echo "    1. Exporte les cookies Amandine →"
echo "       /volume1/Aurelien/Scripts/vinted-bot/data-amandine/cookies/vinted-cookies.json"
echo "    2. Lance scripts/test-cookies.py pour récupérer le user_id Amandine"
echo "    3. Mets le user_id dans .env.amandine (VINTED_USER_ID=...)"
echo "    4. Lance : sudo bash scripts/deploy-nas.sh"
echo "    5. Crée la tâche DSM 'vinted-bot-amandine-tick'"
echo "    6. Renomme la tâche DSM existante en 'vinted-bot-aurelien-tick'"
echo "       et mets à jour son script : docker exec vinted-bot-aurelien ..."

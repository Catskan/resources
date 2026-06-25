#!/bin/bash
# scripts/deploy-to-nas.sh
#
# Sync du code Mac → NAS via rsync over SSH, puis rebuild du container.
#
# Usage :
#   NAS_HOST=192.168.1.10 NAS_USER=aurelien ./scripts/deploy-to-nas.sh

set -euo pipefail

NAS_HOST="${NAS_HOST:?définis NAS_HOST=192.168.1.X}"
NAS_USER="${NAS_USER:?définis NAS_USER=ton_user}"
NAS_PATH="${NAS_PATH:-/volume1/docker/vinted-bot}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "→ Sync $PROJECT_ROOT/ → $NAS_USER@$NAS_HOST:$NAS_PATH/"

rsync -avz --delete \
    --exclude='.git/' \
    --exclude='__pycache__/' \
    --exclude='.venv/' \
    --exclude='.env' \
    --exclude='data/db/*' \
    --exclude='data/logs/*' \
    --exclude='data/cookies/*.json' \
    --exclude='data/proposals/*.json' \
    --exclude='data/crosspost/queue.json' \
    "$PROJECT_ROOT/" \
    "$NAS_USER@$NAS_HOST:$NAS_PATH/"

echo ""
echo "→ Rebuild & restart du container sur le NAS..."
ssh "$NAS_USER@$NAS_HOST" "cd $NAS_PATH && sudo docker compose build && sudo docker compose up -d"

echo ""
echo "✅ Déploiement terminé."

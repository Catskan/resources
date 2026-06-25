#!/bin/bash
# scripts/run-optimizer-all.sh
#
# Génère les propositions LLM pour les 2 comptes en SEQUENCE.
# Un seul cycle WoL/boot/shutdown du PC pour optimiser le temps.
#
# Aurélien (1er) : WoL → start LM Studio → générer → garder PC allumé
# Amandine (2e)  : LM Studio déjà UP → générer → shutdown PC
#
# À appeler depuis DSM Task Scheduler (1× par mois) :
#   /bin/bash /volume1/Aurelien/Scripts/vinted-bot/scripts/run-optimizer-all.sh

set -e

DOCKER=/usr/local/bin/docker
LOG_DIR=/volume1/Aurelien/Scripts/vinted-bot/data-aurelien/logs
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/run-optimizer-all.log"

echo "════════════════════════════════════════════════════════" | tee -a "$LOG"
echo "  Run optimizer pour les 2 comptes — $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "════════════════════════════════════════════════════════" | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "→ [1/2] Aurélien (WoL + LM Studio + génération)…" | tee -a "$LOG"
sudo $DOCKER exec vinted-bot-aurelien python -m vinted_bot.optimizer.runner --generate --no-shutdown 2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "→ [2/2] Amandine (LM Studio déjà UP, génération + shutdown)…" | tee -a "$LOG"
sudo $DOCKER exec vinted-bot-amandine python -m vinted_bot.optimizer.runner --generate 2>&1 | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "════════════════════════════════════════════════════════" | tee -a "$LOG"
echo "  ✅ Run optimizer terminé — $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "════════════════════════════════════════════════════════" | tee -a "$LOG"

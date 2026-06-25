#!/bin/bash
# scripts/run-optimizer-apply.sh
#
# Applique les propositions validées dans la WebUI sur Vinted, pour les 2 comptes.
# Idempotent : si rien n'est validé, ne fait rien (tous les items pending → skip).
#
# Le runner --apply lit le dernier proposals-YYYYMMDD.json et :
#   - user_action=apply  → PUT title_after + description_after
#   - user_action=edit   → PUT edited_title + edited_description
#   - user_action=skip   → skip
#   - user_action=null   → skip (pas encore validé)
#
# DSM Task Scheduler — quotidien à 23h (après la dernière heure de bump 22h) :
#   /bin/bash /volume1/Aurelien/Scripts/vinted-bot/scripts/run-optimizer-apply.sh
#
# Note : pas besoin du PC Windows / LM Studio pour --apply (juste l'API Vinted).

set -e

DOCKER=/usr/local/bin/docker
LOG_DIR=/volume1/Aurelien/Scripts/vinted-bot/data-aurelien/logs
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/run-optimizer-apply.log"

echo "════════════════════════════════════════════════════════" | tee -a "$LOG"
echo "  Apply propositions — $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"
echo "════════════════════════════════════════════════════════" | tee -a "$LOG"

for COMPTE in aurelien amandine; do
    echo "" | tee -a "$LOG"
    echo "→ Apply $COMPTE…" | tee -a "$LOG"
    sudo $DOCKER exec vinted-bot-$COMPTE python -m vinted_bot.optimizer.runner --apply 2>&1 | tee -a "$LOG" || {
        echo "  ⚠ Apply $COMPTE a échoué (continue avec les autres)" | tee -a "$LOG"
    }
done

echo "" | tee -a "$LOG"
echo "✅ Apply terminé — $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

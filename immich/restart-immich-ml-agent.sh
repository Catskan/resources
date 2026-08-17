#!/bin/zsh
# Redémarre le service machine-learning Immich (com.user.immichml).
#
# Appelé quotidiennement par com.user.immichml.daily. Le rafraîchissement du code
# (git pull + uv sync) est fait par start-immich-ml-agent.sh à chaque démarrage :
# redémarrer le service suffit donc à le mettre à jour.
#
# `kickstart -k` tue l'instance en cours puis la relance. L'UID est résolu à
# l'exécution plutôt que codé en dur, pour ne pas dépendre du compte.
set -u

exec /bin/launchctl kickstart -k "gui/$(id -u)/com.user.immichml"

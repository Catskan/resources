#!/bin/zsh
# Service machine-learning Immich, déporté du NAS vers ce Mac.
#
# Lancé et surveillé par launchd (com.user.immichml, KeepAlive). Ne pas lancer à la
# main : launchd garantit déjà l'unicité de l'instance, et un second exemplaire
# échouerait de toute façon sur le port 3003 déjà lié.
#
# La mise à jour du code se fait ICI, au démarrage. Le job com.user.immichml.daily
# redémarre ce service à 3 h, ce qui suffit donc à le rafraîchir quotidiennement —
# pas besoin d'une tâche de mise à jour séparée.
set -u

# launchd n'herite PAS du PATH du shell : il fournit /usr/bin:/bin:/usr/sbin:/sbin.
# `git` passe (il est dans /usr/bin) mais `uv` vit dans /opt/homebrew/bin et reste
# introuvable -> le service sortait en erreur 1 a chaque demarrage
# (« command not found: uv » dans ~/Library/Logs/immichml.err).
# Un script zsh non interactif ne lit pas non plus ~/.zshrc : le PATH doit etre
# pose ici explicitement.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

REPO="/Users/aurel/git/immich/machine-learning"

cd "$REPO" || { echo "repo introuvable : $REPO" >&2; exit 1; }

# --ff-only : jamais de merge automatique sur une machine non surveillée. Un échec
# (pas de réseau, historique divergent) ne doit pas empêcher le service de démarrer
# avec le code déjà présent.
git pull --ff-only || echo "git pull ignoré — démarrage sur le code local" >&2

uv sync --extra cpu --python=3.12 || exit 1

source .venv/bin/activate

# exec : python remplace le shell, si bien que launchd surveille le service lui-même.
# Sans cela il ne verrait que le shell parent et son KeepAlive relancerait mal.
exec python -m immich_ml

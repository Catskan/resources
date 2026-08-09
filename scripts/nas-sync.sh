#!/bin/zsh
# Copie sûre d'un dossier vers un partage NAS monté en SMB, depuis le Mac.
#
# POURQUOI PAS rsync-over-SSH : le binaire rsync de DSM est setuid root et enveloppé
# par Synology. Le mode --server est refusé (« rsync error: rsync service is no
# running », code 43), ce qui se manifeste côté client par un trompeur « Permission
# denied, please try again » APRÈS une authentification SSH pourtant réussie. Activer
# le service rsync dans DSM ne suffit pas. On fait donc du rsync PUREMENT LOCAL sur un
# montage SMB : le binaire du NAS n'est jamais sollicité. Même parade que
# Ansible/roles/claude_code_host/templates/claude-backup.sh.j2.
#
# Usage :
#   zsh nas-sync.sh <source> <destination>
#   zsh nas-sync.sh /Volumes/Untitled/DCIM/Camera01 /Volumes/Photos/Slovenie2026
#
# Ne supprime jamais rien : pas de --delete. C'est un ajout, pas une synchronisation.

set -u

RSYNC="/opt/homebrew/bin/rsync"

SRC="${1:-}"
DST="${2:-}"

if [[ -z "$SRC" || -z "$DST" ]]; then
  print -u2 "usage: zsh $0 <source> <destination>"
  exit 2
fi

# Le rsync d'Apple est openrsync : options incomplètes, -e mal géré. On exige celui
# de Homebrew (brew install rsync).
if [[ ! -x "$RSYNC" ]]; then
  print -u2 "ABORT: $RSYNC absent — installer avec : brew install rsync"
  exit 1
fi

# Garde-fou 1 : source présente ET non vide. Une source vide donnerait un transfert
# « réussi » qui n'a rien copié.
if [[ ! -d "$SRC" ]]; then
  print -u2 "ABORT: source absente : $SRC"
  exit 1
fi
if [[ -z "$(ls -A "$SRC" 2>/dev/null)" ]]; then
  print -u2 "ABORT: source vide : $SRC"
  exit 1
fi

# Garde-fou 2 : la destination doit être sous un volume RÉELLEMENT monté. Si le partage
# SMB a décroché, /Volumes/<part> redevient un dossier ordinaire du disque local et on
# remplirait le Mac sans s'en apercevoir — 50 Go passent inaperçus jusqu'au disque plein.
if [[ "$DST" == /Volumes/* ]]; then
  VOL="/Volumes/${${DST#/Volumes/}%%/*}"
  if ! mount | grep -q " on ${VOL} "; then
    print -u2 "ABORT: $VOL n'est pas monté — monter le partage dans le Finder d'abord."
    exit 1
  fi
fi

mkdir -p "$DST" || exit 1

# -rlt et non -a : SMB ne porte ni permissions POSIX, ni ACL, ni attributs étendus ;
#   -a échouerait sur chaque fichier. On garde ce qui compte : contenu, dates, arbo.
# --modify-window=2 : les cartes SD sont en exFAT, dont les horodatages ont une
#   granularité de 2 s. Sans cette tolérance, chaque relance croit tout modifié.
# @eaDir : dossiers d'index que Synology sème partout ; les recopier fausse la
#   vérification finale.
OPTS=(
  -rlt
  --no-perms --no-owner --no-group --omit-link-times
  --modify-window=2
  --exclude '@eaDir' --exclude '.DS_Store'
)

print "→ $SRC"
print "→ $DST"
print ""

"$RSYNC" "${OPTS[@]}" --partial --info=progress2 "$SRC/" "$DST/" || exit 1

print ""
print "Vérification par empreinte (aucune ligne = tout est identique)…"

DIFF="$("$RSYNC" "${OPTS[@]}" --checksum --dry-run "$SRC/" "$DST/")"

if [[ -n "$DIFF" ]]; then
  print -u2 "ÉCARTS DÉTECTÉS :"
  print -u2 "$DIFF"
  exit 1
fi

print "OK — transfert vérifié, octet pour octet."

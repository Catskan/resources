#!/bin/zsh
LOCKFILE="/tmp/immich_ml.lock"
if [ -e "$LOCKFILE" ] && kill -0 "$(cat $LOCKFILE)" 2>/dev/null; then
    echo "immich_ml is already running"
    exit 1
fi
echo $$ > "$LOCKFILE"
trap "rm -f $LOCKFILE" EXIT

cd /Users/aurel/git/immich/machine-learning
git pull
uv sync --extra cpu --python=3.12
source .venv/bin/activate
python -m immich_ml

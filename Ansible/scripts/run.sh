#!/usr/bin/env bash
# Prompte le master password KeePass une fois puis exécute la commande passée.
# Tout est passé tel quel : la commande peut être ansible-playbook, ansible, etc.
#
# Exemples :
#   ./scripts/run.sh ansible-playbook main_windows_playbook.yml
#   ./scripts/run.sh ansible-playbook main_linux_playbook.yml --tags rdp,wol
#   ./scripts/run.sh ansible windows_hosts -m ansible.windows.win_ping

set -euo pipefail

# macOS fork() safety — sans ça, les workers Ansible crashent avec
# "A worker was found in a dead state" à cause des frameworks Objective-C
# qui refusent de fork() côté Python 3.x.
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

export KEEPASS_LOCATION="${KEEPASS_LOCATION:-/Volumes/home/Drive/Vault/Aurel-vault.kdbx}"

if [[ ! -f "$KEEPASS_LOCATION" ]]; then
  echo "KeePass DB introuvable : $KEEPASS_LOCATION" >&2
  echo "Override possible : export KEEPASS_LOCATION=/autre/chemin.kdbx" >&2
  exit 1
fi

if [[ -z "${KEEPASS_PSW:-}" ]]; then
  read -rs -p "KeePass master password ($KEEPASS_LOCATION) : " KEEPASS_PSW
  echo
  export KEEPASS_PSW
fi

cd "$(dirname "$0")/.."
exec "$@"

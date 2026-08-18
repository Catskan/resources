#!/usr/bin/env bash
# Prompte le master password KeePass une fois puis exécute la commande passée.
# Tout est passé tel quel : la commande peut être ansible-playbook, ansible, etc.
#
# Exemples :
#   ./scripts/run.sh ansible-playbook main_windows_playbook.yml
#   ./scripts/run.sh ansible-playbook main_linux_playbook.yml --tags rdp,wol
#   ./scripts/run.sh ansible windows_hosts -m ansible.windows.win_ping

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <ansible-binary> [args…]" >&2
  echo "  ex: $0 ansible-playbook main_windows_playbook.yml" >&2
  exit 64
fi

# macOS fork() safety — sans ça, les workers Ansible crashent avec
# "A worker was found in a dead state" à cause des frameworks Objective-C
# qui refusent de fork() côté Python 3.x.
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

# Base KeePass de RÉFÉRENCE : partage « Aurelien » du NAS, PAS le partage « home ».
#
# ⚠️ Il existe plusieurs copies de ce fichier sur le NAS, et l'ancien défaut pointait vers
# l'une d'elles (/Volumes/home/Drive/Vault/) qui n'est PLUS mise à jour. Le 2026-08-17,
# cela a failli faire redéployer un certificat périmé de dix jours : le run « réussit »,
# mais avec les anciens secrets, et la panne ne se découvre qu'à l'expiration.
# Les autres copies connues (backups de machines, versions datées, un fichier de conflit
# Synology Drive de mai 2026) ne doivent JAMAIS servir de source.
export KEEPASS_LOCATION="${KEEPASS_LOCATION:-/Volumes/Aurelien/Vault/Aurel-vault.kdbx}"

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

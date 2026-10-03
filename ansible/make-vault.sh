#!/usr/bin/env bash
# make-vault.sh - (re)create ~/.ak-become.vault.yml without hand-editing YAML (E3).
#   ./make-vault.sh
# Asks for akadmin's sudo password on each host (hidden), checks it with a real
# `sudo -v` on that host and only accepts it if sudo does, then writes the YAML with
# correct quoting and encrypts it with ansible-vault (asks for a new vault password).
# The plain text exists only in a 0600 temp file that is shredded on exit.
set -euo pipefail
cd "$(dirname "$0")"
VAULT=${AK_VAULT:-$HOME/.ak-become.vault.yml}
umask 077
tmp=$(mktemp)
trap 'shred -u "$tmp" 2>/dev/null || rm -f "$tmp"' EXIT

declare -A PW
ask() {
  local h=$1 p
  while :; do
    read -rsp "akadmin sudo password on $h: " p; echo
    if [[ $h == mon01 ]]; then
      printf '%s\n' "$p" | sudo -S -k -v -p '' 2>/dev/null && break
    else
      printf '%s\n' "$p" | ssh -o BatchMode=yes "$h" "sudo -S -k -v -p ''" 2>/dev/null && break
    fi
    echo "  sudo on $h rejected it - try again (Ctrl+C to stop)"
  done
  echo "  accepted by sudo on $h"
  PW[$h]=$p
}
ask web01
ask mon01

q() { local s=${1//\'/\'\'}; printf "'%s'" "$s"; }    # YAML single-quoted, ' doubled
{
  echo "ak_become:"
  echo "  web01: $(q "${PW[web01]}")"
  echo "  mon01: $(q "${PW[mon01]}")"
} > "$tmp"

[[ -f $VAULT ]] && mv -f "$VAULT" "$VAULT.old"
echo "Now choose the VAULT password (it protects the file; asked twice):"
ansible-vault encrypt "$tmp" --output "$VAULT"
chmod 600 "$VAULT"
rm -f "$VAULT.old"
echo "Wrote $VAULT"

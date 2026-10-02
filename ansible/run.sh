#!/usr/bin/env bash
# run.sh - run Ansible with the per-host become passwords from the vault (E3).
#   ./run.sh site.yml --check --diff     -> ansible-playbook
#   ./run.sh all -m ping                 -> ansible (ad-hoc), when the first argument isn't a .yml file
#
# The vault lives in akadmin's home on mon01, never in the repo:
#   ansible-vault create ~/.ak-become.vault.yml
# with exactly this content (your two akadmin passwords):
#   ak_become:
#     web01: "<web01 akadmin password>"
#     mon01: "<mon01 akadmin password>"
# group_vars/lab.yml maps ak_become[inventory_hostname] to ansible_become_password.
set -euo pipefail
cd "$(dirname "$0")"
VAULT=${AK_VAULT:-$HOME/.ak-become.vault.yml}
[[ -f $VAULT ]] || { echo "missing $VAULT - create it with: ansible-vault create $VAULT"; exit 1; }
if [[ ${1:-} == *.yml ]]; then
  exec ansible-playbook -e "@$VAULT" --ask-vault-pass "$@"
else
  exec ansible -e "@$VAULT" --ask-vault-pass "$@"
fi

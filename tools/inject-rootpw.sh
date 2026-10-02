#!/usr/bin/env bash
# inject-rootpw.sh - INC-009 drill: set root's password to a random value nobody keeps (web01).
#   sudo bash ~/ak-infra-lab/tools/inject-rootpw.sh
# After this, nobody knows root's password: the emergency-mode prompt can't be answered.
# Recover on the VirtualBox console with docs/runbooks/root-password-reset.md (rd.break).
# akadmin's sudo is unaffected, so SSH administration keeps working throughout.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
# /dev/urandom, not openssl: Rocky Minimal doesn't ship the openssl CLI (the first run failed on that).
head -c 18 /dev/urandom | base64 | passwd --stdin root >/dev/null
echo "== INC-009 injected at $(date '+%F %T'): root password is now unknown."
passwd -S root
# RHEL/Rocky hide the GRUB menu after a successful boot (menu_auto_hide). Show it once
# for the next boot so it can be interrupted for rd.break:
grub2-editenv - unset menu_auto_hide
grub2-editenv - list

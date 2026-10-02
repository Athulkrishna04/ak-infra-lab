#!/usr/bin/env bash
# inject-fstab.sh - INC-008 drill: break the /srv/app UUID in /etc/fstab, then reboot (web01).
#   sudo bash ~/ak-infra-lab/tools/inject-fstab.sh
# Changes ONE character of the /srv/app UUID (no `mount -a`, exactly the mistake the
# runbook warns about), keeps a backup in /root, and reboots. web01 then stops in
# emergency mode after the 90 s device timeout. Recover on the VirtualBox console with
# docs/runbooks/emergency-mode-fstab.md. Needs the root password.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
cp -a /etc/fstab /root/fstab.pre-INC-008
# Flip the last hex digit of the /srv/app UUID (0->1, anything else->0), so it's a typo, not garbage.
awk '$2=="/srv/app" && $1 ~ /^UUID=/ {
       last = substr($1, length($1), 1); new = (last == "0") ? "1" : "0"
       $1 = substr($1, 1, length($1) - 1) new }
     { print }' /root/fstab.pre-INC-008 > /etc/fstab
restorecon /etc/fstab
echo "== diff (backup vs broken):"
diff /root/fstab.pre-INC-008 /etc/fstab || true
cmp -s /root/fstab.pre-INC-008 /etc/fstab && { echo "nothing changed - aborting"; exit 1; }
echo "== INC-008 injected at $(date '+%F %T'). Rebooting in 10 s. Open the VirtualBox console now."
sleep 10
systemctl reboot

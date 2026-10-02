#!/usr/bin/env bash
# lock-backup-key.sh - restrict web01's backup key on mon01 (E1.6).
# Run on mon01:  sudo bash ~/ak-infra-lab/tools/lock-backup-key.sh
#
# Before: the key in /home/akbackup/.ssh/authorized_keys can open a full shell as akbackup.
# After:  it can only run rrsync, write-only (-wo), inside /srv/backups/web01.
#         'restrict' also disables port/agent/X11 forwarding and PTY allocation.
# web01's ak-backup.sh must then send to "akbackup@192.168.56.10:./" (a path relative
# to the directory rrsync allows) instead of the absolute /srv/backups/web01/ path.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

AK=/home/akbackup/.ssh/authorized_keys
DIR=/srv/backups/web01
RR=/usr/bin/rrsync
[[ -x $RR ]] || { echo "rrsync not found at $RR"; exit 1; }
[[ -f $AK ]] || { echo "$AK not found"; exit 1; }

cp -a "$AK" "$AK.bak.$(date +%F_%H%M)"
prefix="restrict,command=\"$RR -wo $DIR\" "

# Rewrite every key line that isn't restricted yet; leave comments and already-restricted lines alone
awk -v p="$prefix" '/^ssh-|^ecdsa-/ { print p $0; next } { print }' "$AK" > "$AK.new"
chown akbackup:akbackup "$AK.new"; chmod 600 "$AK.new"
mv "$AK.new" "$AK"

echo "authorized_keys for akbackup now:"
cut -c1-90 "$AK"

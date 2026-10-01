#!/usr/bin/env bash
# ak-backup.sh - back up this node's config and content to mon01.
# Install: /usr/local/sbin/ak-backup.sh (0700, root). Run by ak-backup.service / ak-backup.timer.
#
# Why a tar archive and not a plain rsync mirror: the receiver (akbackup on mon01) is not
# root, so it can't keep ownership or SELinux labels. The archive keeps them (--acls
# --xattrs --selinux) and the restore puts them back.
set -euo pipefail

HOST=$(hostname -s)
STAMP=$(date +%F_%H%M)
DIR=/var/backups/ak                              # local staging copy (kept 3 days)
STATE=/var/lib/ak-backup                         # last_success timestamp for Zabbix
NAME="${HOST}_${STAMP}.tar.gz"
KEY=/root/.ssh/backup_ed25519
# E1 locks the key to rrsync on mon01; then change DEST to "akbackup@192.168.56.10:./"
DEST="akbackup@192.168.56.10:/srv/backups/${HOST}/"
PATHS=(/etc /srv/www /srv/app)

mkdir -p "$DIR" "$STATE"
chmod 700 "$DIR"

(
  # The archive contains /etc/shadow, so it must be readable by root only.
  umask 077
  rc=0
  tar --acls --xattrs --selinux -czpf "$DIR/$NAME" "${PATHS[@]}" || rc=$?
  # tar exits 1 when a file changed while being read: note it, don't fail the backup.
  if (( rc > 1 )); then exit "$rc"; fi
  if (( rc == 1 )); then logger -t ak-backup "WARN tar exit 1 (a file changed while being read)"; fi
  cd "$DIR" && sha256sum "$NAME" > "$NAME.sha256"
)

rsync -a -e "ssh -i $KEY -o BatchMode=yes" "$DIR/$NAME" "$DIR/$NAME.sha256" "$DEST"
find "$DIR" -name "${HOST}_*.tar.gz*" -mtime +3 -delete

# Zabbix runs as user 'zabbix' and must be able to read this file (0644).
date +%s > "$STATE/last_success.tmp"
chmod 644 "$STATE/last_success.tmp"
mv "$STATE/last_success.tmp" "$STATE/last_success"
logger -t ak-backup "OK $NAME"

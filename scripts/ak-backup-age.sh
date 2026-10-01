#!/usr/bin/env bash
# ak-backup-age.sh - seconds since the last successful backup (Zabbix item ak.backup.age).
# Install: /usr/local/bin/ak-backup-age.sh (0755). Prints 999999 if no backup has ever succeeded.
f=/var/lib/ak-backup/last_success
if [[ -r $f ]]; then
  echo $(( $(date +%s) - $(cat "$f") ))
else
  echo 999999
fi

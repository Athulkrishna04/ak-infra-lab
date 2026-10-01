#!/usr/bin/env bash
# healthcheck.sh - one-shot node health check.  Install: /usr/local/bin/healthcheck.sh (0755)
# Exit codes: 0 OK, 1 WARN, 2 CRIT.  Zabbix reads the exit code as item ak.health.status,
# and ak-health.timer runs it every 5 minutes so the result also lands in the journal.
set -uo pipefail
status=0
warn(){ echo "WARN: $*"; if (( status < 1 )); then status=1; fi; }
crit(){ echo "CRIT: $*"; status=2; }

# 1) Disk usage on real filesystems
#    (squashfs = Ubuntu snaps, always 100% by design; efivarfs = firmware variables)
while read -r use mnt; do
  use=${use%\%}
  [[ $use =~ ^[0-9]+$ ]] || continue
  if   (( use >= 90 )); then crit "disk $mnt at ${use}%"
  elif (( use >= 80 )); then warn "disk $mnt at ${use}%"; fi
done < <(df -P -x tmpfs -x devtmpfs -x overlay -x squashfs -x efivarfs | awk 'NR>1 {print $5, $6}')

# 2) 1-minute load vs CPU count (straight from /proc)
cores=$(nproc); load1=$(cut -d' ' -f1 /proc/loadavg)
if awk -v l="$load1" -v c="$cores" 'BEGIN{exit !(l > c)}'; then warn "load1 $load1 > cores $cores"; fi

# 3) Available memory
avail=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)
if (( avail < 150 )); then warn "MemAvailable ${avail}MiB"; fi

# 4) Failed systemd units
failed=$(systemctl --failed --no-legend --plain | awk '{print $1}' | xargs)
if [[ -n $failed ]]; then crit "failed units: $failed"; fi

# 5) SELinux must be enforcing on RHEL-family nodes
if command -v getenforce >/dev/null && [[ $(getenforce) != Enforcing ]]; then crit "SELinux is $(getenforce)"; fi

# 6) Time sync
if command -v chronyc >/dev/null && ! chronyc tracking | grep -Eq 'Leap status +: Normal'; then warn "chrony not synchronised"; fi

(( status == 0 )) && echo "OK: $(hostname -s) healthy"
exit "$status"

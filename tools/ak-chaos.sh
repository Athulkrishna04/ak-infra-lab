#!/usr/bin/env bash
# ak-chaos.sh - blind fault injector for web01 (build guide E2.3).
#
# You injected the fault yourself, so you already know the answer, and the write-up
# reads like an answer key. This script picks a fault at random, applies it and shows
# you only the "ticket" (the symptom a user or the monitoring would report). Diagnose
# from that. Reveal the answer only after you've written your root cause.
#
#   sudo ./ak-chaos.sh inject          # random fault not done yet; prints the ticket only
#   sudo ./ak-chaos.sh inject <name>   # a specific fault (not blind)
#   sudo ./ak-chaos.sh reveal          # which fault it was
#   sudo ./ak-chaos.sh restore         # undo it and mark it done. Run it after your own fix
#                                      # too: it is safe on an already-fixed system
#   sudo ./ak-chaos.sh list            # all faults, with the ones already done marked
#   sudo ./ak-chaos.sh reset           # forget which faults are done
#
# Take a VirtualBox snapshot before the first run. Boot-level faults (fstab typo,
# forgotten root password) aren't here: inject those by hand (docs/incidents/README.md).
set -euo pipefail

STATE_DIR=/root/.ak-chaos
STATE=$STATE_DIR/state
DONE=$STATE_DIR/done
FAULTS=(disk-full deleted-open-log nginx-config selinux-context firewall-http account-expired)

die(){ echo "ak-chaos: $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "run as root (sudo)"
mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"

# Size in MiB needed to push /srv/app to the given percent full
fill_mib(){
  local pct=$1 size used
  read -r size used < <(df -B1 --output=size,used /srv/app | tail -1)
  echo $(( (size * pct / 100 - used) / 1048576 ))
}

# Random fault that hasn't been done yet
pick(){
  local c=() f
  for f in "${FAULTS[@]}"; do grep -qx "$f" "$DONE" 2>/dev/null || c+=("$f"); done
  (( ${#c[@]} > 0 )) || die "all faults done; start over with: $0 reset"
  echo "${c[RANDOM % ${#c[@]}]}"
}

ticket(){
  case $1 in
    disk-full|deleted-open-log) echo "TICKET: Monitoring alert - filesystem /srv/app on web01 is almost full." ;;
    nginx-config|selinux-context|firewall-http) echo "TICKET: Users report that http://web01.lab.local/ is not working." ;;
    account-expired) echo "TICKET: Developer akdev can't log in to web01 since this morning." ;;
  esac
}

inject(){
  local f=$1
  case $f in
    disk-full)
      local mib; mib=$(fill_mib 95); (( mib > 0 )) || die "/srv/app is already above 95%"
      fallocate -l "${mib}M" /srv/app/public/.upload-tmp-$RANDOM.bin ;;
    deleted-open-log)
      local mib; mib=$(fill_mib 93); (( mib > 0 )) || die "/srv/app is already above 93%"
      systemd-run --quiet --unit=ak-logship --description="AK log shipper" /usr/bin/python3 -c "
import os, time
p = '/srv/app/.logship.buf'
with open(p, 'wb') as f:
    chunk = b'\0' * 1048576
    for _ in range($mib):
        f.write(chunk)
    f.flush()
    os.unlink(p)
    while True:
        time.sleep(3600)
" ;;
    nginx-config)
      cp -a /etc/nginx/conf.d/app.conf "$STATE_DIR/app.conf.orig"
      sed -i 's|proxy_pass http://127.0.0.1:8080/;|proxy_pass http://127.0.0.1:8080/ |' /etc/nginx/conf.d/app.conf
      cmp -s /etc/nginx/conf.d/app.conf "$STATE_DIR/app.conf.orig" && die "app.conf not in the expected form; nothing changed"
      systemctl restart nginx 2>/dev/null || true ;;
    selinux-context)
      local tmpf; tmpf=$(mktemp /tmp/index.XXXX)
      cp /srv/www/index.html "$tmpf"
      mv -f "$tmpf" /srv/www/index.html          # mv keeps the /tmp label (user_tmp_t)
      chmod 644 /srv/www/index.html ;;
    firewall-http)
      firewall-cmd --quiet --zone=mgmt --remove-service=http
      firewall-cmd --quiet --permanent --zone=mgmt --remove-service=http ;;
    account-expired)
      chage -E 0 akdev ;;
    *) die "unknown fault '$f' (try: list)" ;;
  esac
  echo "$f $(date '+%F %T')" > "$STATE"
}

restore(){
  [[ -f $STATE ]] || die "no active fault"
  local f; f=$(cut -d' ' -f1 "$STATE")
  case $f in
    disk-full)        rm -f /srv/app/public/.upload-tmp-*.bin ;;
    deleted-open-log) systemctl stop ak-logship 2>/dev/null || true ;;
    nginx-config)     cp -a "$STATE_DIR/app.conf.orig" /etc/nginx/conf.d/app.conf; systemctl restart nginx ;;
    selinux-context)  restorecon -v /srv/www/index.html ;;
    firewall-http)    firewall-cmd --quiet --zone=mgmt --add-service=http
                      firewall-cmd --quiet --permanent --zone=mgmt --add-service=http ;;
    account-expired)  chage -E -1 akdev ;;
  esac
  rm -f "$STATE"
  grep -qx "$f" "$DONE" 2>/dev/null || echo "$f" >> "$DONE"
  echo "restored: $f (marked done)"
}

case ${1:-} in
  inject)
    [[ -f $STATE ]] && die "a fault is already active; fix it, then run: $0 restore"
    f=${2:-$(pick)}
    inject "$f"
    echo "Fault injected at $(date '+%F %T')."
    ticket "$f"
    echo "Write the symptom in your incident report before you touch anything." ;;
  reveal)  [[ -f $STATE ]] && echo "fault: $(cat "$STATE")" || echo "no active fault" ;;
  restore) restore ;;
  list)    printf '%s\n' "${FAULTS[@]}" ;;
  *)       sed -n '2,19p' "$0" ;;
esac

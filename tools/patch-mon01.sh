#!/usr/bin/env bash
# patch-mon01.sh - apt patching on mon01 as one logged change (runbooks/patching.md).
#   sudo bash ~/ak-infra-lab/tools/patch-mon01.sh CHG-002
# Refreshes the lists, upgrades (keeping our edited config files), checks that the Zabbix
# stack and log receiver survive, then reboots. Stops before the reboot if a check fails.
# Zabbix comes from the 7.0 repo, so only 7.0.x minor updates are possible here.
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
CHG=${1:?usage: patch-mon01.sh CHG-0NN}
LOG=/home/akadmin/${CHG}-mon01.log
: > "$LOG"; chmod 644 "$LOG"
exec > >(tee "$LOG") 2>&1
step(){ echo; echo "== $* ($(date +%T))"; }
export DEBIAN_FRONTEND=noninteractive
VERS='linux-image-generic|zabbix-server-mysql|zabbix-agent2|mariadb-server|nginx|openssh-server'

step "$CHG start on $(hostname) - before"
uname -r
dpkg-query -W -f='${Package} ${Version}\n' | grep -E "^($VERS) "

step "what unattended-upgrades already did (last 10 lines)"
tail -n 10 /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null || echo "(no log)"

step "apt-get update + pending"
apt-get -q update || { echo "ABORT: apt update failed, no reboot"; exit 1; }
apt list --upgradable 2>/dev/null

step "apply: apt-get upgrade (keep local config files)"
apt-get -y -o Dpkg::Options::=--force-confold upgrade || { echo "ABORT: upgrade failed, no reboot"; exit 1; }
grep -E ' (install|upgrade) ' /var/log/dpkg.log | tail -n 20

step "post-checks before reboot"
ok=1
sshd -t && echo "sshd -t: config OK" || { echo "sshd -t: FAILED"; ok=0; }
for s in ssh zabbix-server zabbix-agent2 mariadb nginx rsyslog; do
  printf '%-14s %s\n' "$s" "$(systemctl is-active "$s")"
  systemctl is-active -q "$s" || ok=0
done
ss -tln | grep -q ':20514 ' && echo "rsyslog listening on 20514" || { echo "20514 NOT listening"; ok=0; }
code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1/)
echo "Zabbix UI / -> $code"; [[ $code =~ ^(200|302)$ ]] || ok=0
dpkg-query -W -f='${Package} ${Version}\n' | grep -E "^($VERS) "

step "reboot needed?"
if [[ -f /var/run/reboot-required ]]; then echo "REBOOT REQUIRED by:"; cat /var/run/reboot-required.pkgs 2>/dev/null
else echo "no reboot-required flag (rebooting anyway, as planned, to prove the boot)"; fi

if (( ok )); then
  step "all post-checks OK - rebooting in 10 s (planned in $CHG)"
  sleep 10
  systemctl reboot
else
  step "a post-check FAILED - NOT rebooting. See the rollback plan in docs/changes/$CHG-*.md"
  exit 1
fi

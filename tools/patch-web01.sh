#!/usr/bin/env bash
# patch-web01.sh - security patching on web01 as one logged change (runbooks/patching.md).
#   sudo bash ~/ak-infra-lab/tools/patch-web01.sh CHG-001
# Applies security advisories only, checks that sshd/nginx/ak-app/agent survive, then
# reboots so every updated library is loaded and the boot is proven again.
# Stops before the reboot if any post-check fails. The log is readable by akadmin.
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
CHG=${1:?usage: patch-web01.sh CHG-0NN}
LOG=/home/akadmin/${CHG}-web01.log
: > "$LOG"; chmod 644 "$LOG"
exec > >(tee "$LOG") 2>&1
step(){ echo; echo "== $* ($(date +%T))"; }
PKGS="kernel-core openssh-server expat"

step "$CHG start on $(hostname) - before"
uname -r
rpm -q $PKGS | sort -u

step "pending security advisories"
dnf -q updateinfo list --security

step "apply: dnf upgrade --security"
dnf -y upgrade --security || { echo "ABORT: dnf failed, no reboot"; exit 1; }

step "transaction record (dnf history info last)"
dnf history info last | sed -n '1,30p'

step "post-checks before reboot"
ok=1
sshd -t && echo "sshd -t: config OK" || { echo "sshd -t: FAILED"; ok=0; }
for s in sshd nginx ak-app zabbix-agent2 rsyslog auditd; do
  printf '%-14s %s\n' "$s" "$(systemctl is-active "$s")"
  systemctl is-active -q "$s" || ok=0
done
code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://127.0.0.1/app/)
echo "local /app/ -> $code"; [[ $code == 200 ]] || ok=0
rpm -q $PKGS | sort -u

step "reboot needed?"
dnf needs-restarting -r; echo "needs-restarting -r exit=$? (1 = reboot required)"
echo "services using old libraries:"; dnf needs-restarting -s

if (( ok )); then
  step "all post-checks OK - rebooting in 10 s (planned in $CHG)"
  sleep 10
  systemctl reboot
else
  step "a post-check FAILED - NOT rebooting. See the rollback plan in docs/changes/$CHG-*.md"
  exit 1
fi

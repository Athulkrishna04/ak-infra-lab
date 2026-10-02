#!/usr/bin/env bash
# e1-mon01.sh - apply the E1 changes on mon01 in one run (build guide E1.2-E1.6).
# Run on mon01 FIRST (web01's log forwarding and backups depend on it):
#   sudo bash ~/ak-infra-lab/tools/e1-mon01.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
R=/home/akadmin/ak-infra-lab
step(){ echo; echo "== $*"; }

step "E1.2 kernel hardening (sysctl)"
install -m 0644 $R/configs/common/sysctl.d/90-ak.conf /etc/sysctl.d/
sysctl --system >/dev/null
sysctl kernel.dmesg_restrict kernel.kptr_restrict net.ipv4.tcp_syncookies vm.swappiness

step "E1.3 central log receiver (rsyslog imtcp :20514 + logrotate)"
install -d -o syslog -g adm -m 0750 /var/log/remote
install -m 0644 $R/configs/mon01/rsyslog.d/10-remote.conf /etc/rsyslog.d/
install -m 0644 $R/configs/mon01/logrotate.d/remote /etc/logrotate.d/
rsyslogd -N1 2>&1 | tail -1
systemctl restart rsyslog
sleep 1
ss -tln | grep -q ':20514 ' && echo "listening on tcp/20514" || { echo "NOT listening on 20514"; exit 1; }
logrotate -d /etc/logrotate.d/remote >/dev/null 2>&1 && echo "logrotate config OK"

step "E1.4 password aging defaults + SSH login banner"
sed -i -E 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t90/; s/^PASS_WARN_AGE.*/PASS_WARN_AGE\t7/' /etc/login.defs
grep -E '^PASS_(MAX_DAYS|WARN_AGE)' /etc/login.defs
install -m 0644 $R/configs/common/issue.net /etc/issue.net
install -m 0644 $R/configs/common/sshd_config.d/11-banner.conf /etc/ssh/sshd_config.d/
sshd -t && systemctl reload ssh && echo "banner enabled (ssh reloaded)"

step "E1.6 lock web01's backup key to rrsync"
bash $R/tools/lock-backup-key.sh

echo; echo "== mon01 E1 done. Now run e1-web01.sh on web01."

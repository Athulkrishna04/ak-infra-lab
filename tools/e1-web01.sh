#!/usr/bin/env bash
# e1-web01.sh - apply the E1 changes on web01 in one run (build guide E1.2-E1.6).
# Run AFTER e1-mon01.sh:   sudo bash ~/ak-infra-lab/tools/e1-web01.sh
# (E1.1 auditd is a separate step: it needs the audit-rules package.)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
R=/home/akadmin/ak-infra-lab
step(){ echo; echo "== $*"; }

step "E1.2 kernel hardening (sysctl)"
install -m 0644 $R/configs/common/sysctl.d/90-ak.conf /etc/sysctl.d/
sysctl --system >/dev/null
sysctl kernel.dmesg_restrict kernel.kptr_restrict net.ipv4.tcp_syncookies vm.swappiness

step "E1.3 forward logs to mon01 (SELinux port label first)"
if semanage port -l | grep syslogd_port_t | grep tcp | grep -qw 20514; then
  echo "20514/tcp already labelled syslogd_port_t"
else
  semanage port -a -t syslogd_port_t -p tcp 20514 && echo "added 20514/tcp to syslogd_port_t"
fi
install -m 0644 $R/configs/common/rsyslog.d/90-forward.conf /etc/rsyslog.d/
rsyslogd -N1 2>&1 | tail -1
systemctl restart rsyslog
logger -t t14 "hello-from-web01 $(date +%T)" && echo "test message sent (tag t14)"

step "E1.4 password aging defaults + SSH login banner"
sed -i -E 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t90/; s/^PASS_WARN_AGE.*/PASS_WARN_AGE\t7/' /etc/login.defs
grep -E '^PASS_(MAX_DAYS|WARN_AGE)' /etc/login.defs
install -m 0644 $R/configs/common/issue.net /etc/issue.net
install -m 0644 $R/configs/common/sshd_config.d/11-banner.conf /etc/ssh/sshd_config.d/
sshd -t && systemctl reload sshd && echo "banner enabled (sshd reloaded)"

step "E1.6 backup through the locked key"
install -m 0700 $R/scripts/ak-backup.sh /usr/local/sbin/
grep '^DEST=' /usr/local/sbin/ak-backup.sh
systemctl start ak-backup.service
journalctl -u ak-backup -n 1 --no-pager -o cat
echo "shell attempt with the backup key (must be refused):"
ssh -i /root/.ssh/backup_ed25519 -o BatchMode=yes akbackup@192.168.56.10 id 2>&1 | tail -2 || true

step "AVC check (SELinux denials in the last 10 minutes)"
n=$(ausearch -m AVC -ts recent 2>/dev/null | grep -c 'avc:' || true)
echo "${n:-0} denials"

echo; echo "== web01 E1 done."

#!/usr/bin/env bash
# checks-web01.sh - local checks on web01. Run as root:  sudo bash checks-web01.sh
# Normally started by tests/verify.sh on mon01, which copies it over and runs it with sudo.
# Prints one line per test: PASS / FAIL / SKIP <id> <what>.
set -uo pipefail

pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; }
skip(){ echo "SKIP $*"; }

if [[ $EUID -ne 0 ]]; then echo "run as root (sudo)"; exit 2; fi

# T03 sudo scope for developers
out=$(sudo -l -U akdev 2>&1)
if [[ $out == *"/usr/bin/systemctl restart nginx"* && $out != *"(ALL) ALL"* && $out != *"(ALL : ALL) ALL"* ]]; then
  pass "T03 web01 akdev may only restart nginx / read its journal"
else
  fail "T03 web01 sudo scope for akdev (got: $(echo "$out" | tail -3 | xargs))"
fi

# T04 SELinux enforcing
mode=$(getenforce 2>/dev/null || echo missing)
[[ $mode == Enforcing ]] && pass "T04 web01 SELinux Enforcing" || fail "T04 web01 SELinux is $mode"

# T06 public zone serves http only
svc=$(firewall-cmd --zone=public --list-services 2>&1 | xargs)
[[ $svc == "http" ]] && pass "T06 web01 public zone services = http" || fail "T06 web01 public zone services = '$svc'"

# T07 LVM volume mounted from the right device and filesystem
mnt=$(findmnt -n -o SOURCE,FSTYPE /srv/app 2>/dev/null | xargs)
[[ $mnt == "/dev/mapper/vg_data-lv_app xfs" ]] && pass "T07 web01 /srv/app on vg_data-lv_app (xfs)" || fail "T07 web01 /srv/app mount = '$mnt'"

# T08 cgroup limits applied to ak-app
mem=$(systemctl show ak-app -p MemoryMax --value 2>/dev/null)
cpu=$(systemctl show ak-app -p CPUQuotaPerSecUSec --value 2>/dev/null)
if [[ $mem == 134217728 && $cpu == 250ms ]]; then
  pass "T08 web01 ak-app MemoryMax=128M CPUQuota=25%"
else
  fail "T08 web01 ak-app MemoryMax=$mem CPUQuotaPerSecUSec=$cpu"
fi

# T11 backup timer enabled + active, and at least one success recorded
en=$(systemctl is-enabled ak-backup.timer 2>/dev/null); ac=$(systemctl is-active ak-backup.timer 2>/dev/null)
if [[ $en == enabled && $ac == active && -r /var/lib/ak-backup/last_success ]]; then
  pass "T11 web01 ak-backup.timer enabled/active, last success $(date -d @"$(cat /var/lib/ak-backup/last_success)" '+%F %T')"
else
  fail "T11 web01 ak-backup.timer is-enabled=$en is-active=$ac last_success=$( [[ -r /var/lib/ak-backup/last_success ]] && echo present || echo missing )"
fi

# T12b restore: extract sshd_config from the newest local archive, compare content and SELinux label
newest=$(ls -1t /var/backups/ak/*.tar.gz 2>/dev/null | head -1)
if [[ -z $newest ]]; then
  fail "T12b web01 no archive in /var/backups/ak"
else
  tmp=$(mktemp -d)
  if tar --acls --xattrs --selinux -xzpf "$newest" -C "$tmp" etc/ssh/sshd_config 2>/dev/null \
     && cmp -s "$tmp/etc/ssh/sshd_config" /etc/ssh/sshd_config \
     && [[ $(stat -c %C "$tmp/etc/ssh/sshd_config") == $(stat -c %C /etc/ssh/sshd_config) ]]; then
    pass "T12b web01 restore of etc/ssh/sshd_config matches live file and label ($(basename "$newest"))"
  else
    fail "T12b web01 restored sshd_config differs from live file or label (from $(basename "$newest"); changed since the backup?)"
  fi
  rm -rf "$tmp"
fi

# T13 (E1) audit trail for identity changes
# Capture first, then grep: with pipefail, `ausearch | grep -q` fails when grep exits on the
# first match and ausearch dies of SIGPIPE mid-write (the false FAIL seen on 2026-10-02).
if grep -q -- '-k identity\|key=identity' <<<"$(auditctl -l 2>/dev/null)"; then
  # (Rocky 10's useradd rejects -K CREATE_MAIL_SPOOL=no: "unknown item", so clean up instead.)
  useradd -M -s /sbin/nologin akprobe13 && userdel akprobe13
  rm -f /var/spool/mail/akprobe13   # useradd creates a mail spool and plain userdel leaves it
  sleep 1
  if grep -q akprobe13 <<<"$(ausearch -k identity -ts recent -i 2>/dev/null)"; then
    pass "T13 web01 useradd/userdel recorded under key identity"
  else
    fail "T13 web01 no identity audit event for akprobe13"
  fi
else
  skip "T13 web01 audit rules not loaded yet (E1)"
fi

# T15 health check
hc=$(/usr/local/bin/healthcheck.sh 2>&1); rc=$?
[[ $rc -eq 0 ]] && pass "T15 web01 healthcheck: $hc" || fail "T15 web01 healthcheck exit $rc: $(echo "$hc" | xargs)"

# T18 time sync
if chronyc tracking 2>/dev/null | grep -Eq 'Leap status +: Normal'; then
  pass "T18 web01 chrony synchronised"
else
  fail "T18 web01 chrony not synchronised"
fi

# T19 negative: developers cannot stop nginx
if sudo -l -U akdev /usr/bin/systemctl stop nginx >/dev/null 2>&1; then
  fail "T19 web01 akdev IS allowed to stop nginx"
else
  pass "T19 web01 akdev cannot stop nginx"
fi

# T20 (E1) kernel hardening via sysctl
if [[ -f /etc/sysctl.d/90-ak.conf ]]; then
  v=$(sysctl -n kernel.dmesg_restrict)
  [[ $v == 1 ]] && pass "T20 web01 kernel.dmesg_restrict = 1" || fail "T20 web01 kernel.dmesg_restrict = $v"
else
  skip "T20 web01 /etc/sysctl.d/90-ak.conf not installed yet (E1)"
fi

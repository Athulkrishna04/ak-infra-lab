#!/usr/bin/env bash
# checks-mon01.sh - local checks on mon01. Run as root:  sudo bash tests/checks-mon01.sh [T14-token]
# Normally started by tests/verify.sh, which first logs the T14 token on web01.
set -uo pipefail

pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; }
skip(){ echo "SKIP $*"; }

if [[ $EUID -ne 0 ]]; then echo "run as root (sudo)"; exit 2; fi
token=${1:-}

# T12a backup integrity: newest archive from web01 matches its sha256 file
dir=/srv/backups/web01
newest=$(ls -1t "$dir"/*.tar.gz 2>/dev/null | head -1)
if [[ -z $newest ]]; then
  fail "T12a mon01 no archive in $dir"
elif out=$(cd "$dir" && sha256sum -c "$(basename "$newest").sha256" 2>&1); then
  pass "T12a mon01 $out"
else
  fail "T12a mon01 checksum mismatch: $out"
fi

# T14 (E1) central logging: the token logged on web01 arrived in its per-host file
if [[ ! -f /etc/rsyslog.d/10-remote.conf ]]; then
  skip "T14 mon01 central log receiver not configured yet (E1)"
elif [[ -z $token ]]; then
  skip "T14 mon01 no token given"
elif grep -qs -- "$token" /var/log/remote/web01/t14.log; then
  pass "T14 mon01 '$token' found in /var/log/remote/web01/t14.log"
else
  fail "T14 mon01 '$token' not in /var/log/remote/web01/t14.log"
fi

# Zabbix server itself
[[ $(systemctl is-active zabbix-server) == active ]] && pass "T09s mon01 zabbix-server active" || fail "T09s mon01 zabbix-server not active"

# T15 health check (if installed on mon01)
if [[ -x /usr/local/bin/healthcheck.sh ]]; then
  hc=$(/usr/local/bin/healthcheck.sh 2>&1); rc=$?
  [[ $rc -eq 0 ]] && pass "T15 mon01 healthcheck: $hc" || fail "T15 mon01 healthcheck exit $rc: $(echo "$hc" | xargs)"
else
  skip "T15 mon01 healthcheck.sh not installed"
fi

# T18 time sync
if chronyc tracking 2>/dev/null | grep -Eq 'Leap status +: Normal'; then
  pass "T18 mon01 chrony synchronised"
else
  fail "T18 mon01 chrony not synchronised"
fi

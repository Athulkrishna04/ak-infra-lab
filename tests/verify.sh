#!/usr/bin/env bash
# verify.sh - run the automated part of the test plan (tests/test-plan.md).
#
# Run on mon01 as akadmin, from the repo copy:   cd ~/ak-infra-lab && bash tests/verify.sh
# You are asked for akadmin's sudo password twice: once on web01, once on mon01.
# Exit code 0 only if nothing FAILed. SKIP = feature not built yet (E1 tests during the MVP).
# T10 (alerting) is manual: see the test plan.
set -uo pipefail

# Use the name, not the IP: mon01's known_hosts entry for web01 was created under this name
# (ssh-copy-id akadmin@web01), and BatchMode refuses a host key it hasn't seen for that name.
WEB=${WEB:-web01}
here=$(cd "$(dirname "$0")" && pwd)
results=$(mktemp)
trap 'rm -f "$results"' EXIT

pass(){ echo "PASS $*" | tee -a "$results"; }
fail(){ echo "FAIL $*" | tee -a "$results"; }
skip(){ echo "SKIP $*" | tee -a "$results"; }
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=5)

echo "== cross-node checks (from $(hostname -s)) =="

# T01 root SSH refused
out=$(ssh "${ssh_opts[@]}" root@"$WEB" true 2>&1)
[[ $out == *"Permission denied"* ]] && pass "T01 root SSH refused: $out" || fail "T01 root SSH not refused as expected: $out"

# T02 password authentication not offered
out=$(ssh "${ssh_opts[@]}" -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive akadmin@"$WEB" true 2>&1)
[[ $out == *"Permission denied (publickey)"* ]] && pass "T02 password auth off: $out" || fail "T02 password auth: $out"

# T05 web page and app through nginx (management side)
c1=$(curl -s -o /dev/null -m 5 -w '%{http_code}' -H 'Host: web01.lab.local' "http://$WEB/")
c2=$(curl -s -o /dev/null -m 5 -w '%{http_code}' -H 'Host: web01.lab.local' "http://$WEB/app/")
[[ $c1 == 200 && $c2 == 200 ]] && pass "T05 / = $c1, /app/ = $c2" || fail "T05 / = $c1, /app/ = $c2"

# T09 Zabbix agent on web01 answers passive checks
if command -v zabbix_get >/dev/null; then
  v=$(zabbix_get -s "$WEB" -k agent.ping 2>&1)
  [[ $v == 1 ]] && pass "T09 zabbix_get agent.ping = 1" || fail "T09 zabbix_get agent.ping: $v"
else
  fail "T09 zabbix_get not installed on this node (apt install zabbix-get)"
fi

# T16 / T17 public zone, tested from the labnet (10.0.10.0/24) side
pub=$(ssh "${ssh_opts[@]}" akadmin@"$WEB" "ip -4 -o addr show scope global" 2>/dev/null \
      | awk '$4 ~ /^10\.0\.10\./ {split($4,a,"/"); print a[1]; exit}')
if [[ -z $pub ]]; then
  fail "T16 could not find web01's labnet (10.0.10.x) address"
  fail "T17 could not find web01's labnet (10.0.10.x) address"
else
  if timeout 5 bash -c "exec 3<>/dev/tcp/$pub/22" 2>/dev/null; then
    fail "T16 SSH to web01 via public zone ($pub:22) is OPEN"
  else
    pass "T16 SSH to web01 via public zone ($pub:22) refused"
  fi
  c=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$pub/")
  [[ $c == 200 ]] && pass "T17 HTTP via public zone ($pub) = 200" || fail "T17 HTTP via public zone ($pub) = $c"
fi

echo
echo "== web01 local checks (sudo password for akadmin@web01) =="
scp -q "$here/checks-web01.sh" akadmin@"$WEB":/tmp/ak-checks-web01.sh
# Straight into tee (it never buffers). A `tr -d '\r'` here held back the sudo prompt until
# web01 closed the connection (sudo then timed out), and stripping \r staircased the output.
# The \r left in $results is harmless: the summary only counts lines starting with PASS/FAIL.
ssh -t akadmin@"$WEB" "sudo bash /tmp/ak-checks-web01.sh; rm -f /tmp/ak-checks-web01.sh" \
  | tee -a "$results"

echo
echo "== mon01 local checks (sudo password for akadmin@mon01) =="
token="t14-$(date +%s)"
ssh "${ssh_opts[@]}" akadmin@"$WEB" "logger -t t14 '$token'" && sleep 3
sudo bash "$here/checks-mon01.sh" "$token" | tee -a "$results"

echo
echo "INFO T10 (Zabbix alert on nginx stop) is manual: see tests/test-plan.md"
p=$(grep -c '^PASS' "$results"); f=$(grep -c '^FAIL' "$results"); s=$(grep -c '^SKIP' "$results")
echo "== SUMMARY: $p PASS, $f FAIL, $s SKIP =="
[[ $f -eq 0 ]]

#!/usr/bin/env bash
# zbx8-nginx-merge.sh - CHG-004 rehearsal, step 2 on mon01: adopt the 8.0 nginx.conf
# (.dpkg-dist: new frontend path /usr/share/zabbix/ui) and re-apply our two M3 edits
# (listen 80, server_name). Then test, reload, prove the UI. Appends to the rehearsal log.
#   sudo bash ~/ak-infra-lab/tools/zbx8-nginx-merge.sh
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
exec > >(tee -a /home/akadmin/CHG-004-rehearsal.log) 2>&1
step(){ echo; echo "== $* ($(date +%T))"; }
C=/etc/zabbix/nginx.conf

step "MERGE: 8.0 nginx.conf.dpkg-dist + our listen/server_name"
cp -a $C $C.7.0-kept
sed -E -e 's|^#\s*listen\s+8080;|        listen          80;|' \
       -e 's|^#\s*server_name\s+example\.com;|        server_name     mon01.lab.local 192.168.56.10;|' \
       $C.dpkg-dist > $C
diff $C.dpkg-dist $C
nginx -t 2>&1 | tail -n 2 && systemctl reload nginx && echo "nginx reloaded"
sleep 3   # rehearsal finding 2: old workers keep serving the old config for a moment after a graceful reload

step "PROOF: the 8.0 frontend"
code=$(curl -s -o /tmp/zbx-index.html -m 10 -w '%{http_code}' http://127.0.0.1/)
echo "frontend / -> HTTP $code"
grep -oE '<title>[^<]*</title>' /tmp/zbx-index.html | head -n 1
api=$(curl -s -m 10 -H 'Content-Type: application/json-rpc' -d '{"jsonrpc":"2.0","method":"apiinfo.version","params":{},"id":1}' http://127.0.0.1/api_jsonrpc.php)
echo "API apiinfo.version -> $api"

step "SERVER CONFIG: our zabbix_server.conf vs the 8.0 default (values masked)"
diff <(grep -vE '^\s*(#|$)' /etc/zabbix/zabbix_server.conf | sed -E 's/(DBPassword=).*/\1********/' | sort) \
     <(grep -vE '^\s*(#|$)' /etc/zabbix/zabbix_server.conf.dpkg-dist | sort)
echo "(lines starting < are our settings; > are 8.0 defaults we don't use)"

step "MERGE done"

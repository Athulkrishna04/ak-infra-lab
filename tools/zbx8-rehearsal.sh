#!/usr/bin/env bash
# zbx8-rehearsal.sh - CHG-004 dress rehearsal on mon01: Zabbix 7.0.31 -> 8.0 pre-release.
#   sudo bash ~/ak-infra-lab/tools/zbx8-rehearsal.sh
# ONLY behind an offline VirtualBox snapshot (pre-zabbix8): the DB schema upgrade is one-way,
# and the rollback is "restore the snapshot". Logs to /home/akadmin/CHG-004-rehearsal.log.
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
LOG=/home/akadmin/CHG-004-rehearsal.log
: > "$LOG"; chmod 644 "$LOG"
exec > >(tee "$LOG") 2>&1
step(){ echo; echo "== $* ($(date +%T))"; }
export DEBIAN_FRONTEND=noninteractive
PKGS="zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2 zabbix-get"
db(){ mysql -N -B zabbix -e "$1"; }
last_web01(){ db "SELECT FROM_UNIXTIME(MAX(h.clock)) FROM history_uint h JOIN items i ON i.itemid=h.itemid JOIN hosts ho ON ho.hostid=i.hostid WHERE ho.host='web01'"; }
vers(){ dpkg-query -W -f='${Package} ${Version}\n' $PKGS 2>/dev/null; }

step "BEFORE: versions, DB schema, freshest web01 data"
vers
zabbix_server -V | head -n 1
echo "dbversion (mandatory optional): $(db 'SELECT mandatory, optional FROM dbversion')"
echo "latest web01 history value: $(last_web01)"
systemctl is-active zabbix-server zabbix-agent2 nginx mariadb | paste -sd' '

step "BACKUP: database dump + config (rollback path 1, in addition to the snapshot)"
STAMP=$(date +%F_%H%M)
systemctl stop zabbix-server
mysqldump --single-transaction --routines zabbix | gzip > /srv/backups/zabbix-7.0.31-$STAMP.sql.gz
tar czf /srv/backups/zabbix-conf-7.0.31-$STAMP.tgz /etc/zabbix 2>/dev/null
ls -lh /srv/backups/zabbix-*-$STAMP.* | awk '{print $5, $9}'
gunzip -c /srv/backups/zabbix-7.0.31-$STAMP.sql.gz | grep -c '^CREATE TABLE' | sed 's/^/tables in dump: /'

step "REPO: install the official 8.0 repository package (enables release + unstable channels)"
curl -s -m 60 -o /tmp/zabbix-release-8.0.deb https://repo.zabbix.com/zabbix/8.0/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_8.0+ubuntu24.04_all.deb
dpkg -i /tmp/zabbix-release-8.0.deb
ls /etc/apt/sources.list.d/
apt-get -q update 2>&1 | grep -i zabbix
apt list --upgradable 2>/dev/null | grep -i zabbix

step "UPGRADE: Zabbix packages only (keep our edited config files)"
apt-get -y -o Dpkg::Options::=--force-confold install --only-upgrade $PKGS 2>&1 | grep -E '^(Setting up|Unpacking) zabbix|upgraded,|E:'
vers

step "START: the server migrates the database schema on first start"
systemctl start zabbix-server
for i in $(seq 1 60); do
  grep -q 'database upgrade fully completed' /var/log/zabbix/zabbix_server.log && break
  grep -qE 'database upgrade failed|cannot upgrade' /var/log/zabbix/zabbix_server.log && break
  sleep 10
done
grep -E 'Starting Zabbix Server|current database version|required (mandatory|optional) version|starting automatic database upgrade|database upgrade fully completed|database upgrade failed|cannot' /var/log/zabbix/zabbix_server.log | tail -n 12

step "AFTER: versions, schema, services"
zabbix_server -V | head -n 1
echo "dbversion (mandatory optional): $(db 'SELECT mandatory, optional FROM dbversion')"
systemctl restart php8.3-fpm nginx
systemctl is-active zabbix-server zabbix-agent2 nginx mariadb php8.3-fpm | paste -sd' '

step "PROOF: frontend answers, agents answer, new data arrives"
code=$(curl -s -o /tmp/zbx-index.html -m 10 -w '%{http_code}' http://127.0.0.1/)
echo "frontend / -> HTTP $code; page mentions: $(grep -oE 'Zabbix [0-9]+\.[0-9]+[^<"]{0,12}' /tmp/zbx-index.html | sort -u | head -n 3 | paste -sd' ')"
echo "zabbix_get web01 agent.version = $(zabbix_get -s 192.168.56.11 -k agent.version 2>&1)"
echo "zabbix_get web01 agent.ping    = $(zabbix_get -s 192.168.56.11 -k agent.ping 2>&1)"
echo "waiting 120 s for the server to poll web01..."
sleep 120
echo "latest web01 history value: $(last_web01)   (now: $(date '+%F %T'))"
grep -iE 'error|failed' /var/log/zabbix/zabbix_server.log | tail -n 5

step "REHEARSAL done - next: power off and restore the snapshot pre-zabbix8 (rollback)"

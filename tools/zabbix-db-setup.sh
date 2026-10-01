#!/usr/bin/env bash
# zabbix-db-setup.sh - set up (or repair) the Zabbix database on mon01 in one consistent step.
# Run as root on mon01:   sudo bash ~/ak-infra-lab/tools/zabbix-db-setup.sh
#
# - generates a random DB password, so nothing is typed by hand and nothing can mismatch
# - creates the database/user if missing and sets the password on the MariaDB user
# - writes the SAME password into /etc/zabbix/zabbix_server.conf (DBPassword=)
# - imports the schema only if the database has no tables yet
# - restarts zabbix-server and shows its log
# The password is never printed. Read it later (for the web setup wizard) with:
#   sudo grep ^DBPassword= /etc/zabbix/zabbix_server.conf
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

CONF=/etc/zabbix/zabbix_server.conf
SCHEMA=/usr/share/zabbix-sql-scripts/mysql/server.sql.gz
[[ -f $CONF && -f $SCHEMA ]] || { echo "Zabbix packages not installed (missing $CONF or $SCHEMA)"; exit 1; }

pw=$(openssl rand -hex 16)          # 32 hex characters: no quotes or symbols to break SQL or sed

mysql <<SQL
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS zabbix@localhost;
ALTER USER zabbix@localhost IDENTIFIED BY '$pw';
GRANT ALL PRIVILEGES ON zabbix.* TO zabbix@localhost;
FLUSH PRIVILEGES;
SQL
echo "DB user zabbix: password set"

# Replace any DBPassword line (commented or not) with the new one; add it if none exists
if grep -qE '^#?\s*DBPassword=' "$CONF"; then
  sed -i -E "s|^#?\s*DBPassword=.*|DBPassword=$pw|" "$CONF"
else
  echo "DBPassword=$pw" >> "$CONF"
fi
echo "zabbix_server.conf: DBPassword updated ($(grep -c '^DBPassword=' "$CONF") line)"

tables=$(mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='zabbix';")
if [[ $tables -eq 0 ]]; then
  echo "Importing schema (2-5 minutes, no output until done)..."
  mysql -e "SET GLOBAL log_bin_trust_function_creators = 1;"
  zcat "$SCHEMA" | MYSQL_PWD="$pw" mysql --default-character-set=utf8mb4 -uzabbix zabbix
  mysql -e "SET GLOBAL log_bin_trust_function_creators = 0;"
  echo "Schema imported: $(mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='zabbix';") tables"
else
  echo "Schema already present ($tables tables), import skipped"
fi

# enable as well as restart: without 'enable' the server runs now but stays off after the next reboot
systemctl enable zabbix-server >/dev/null 2>&1
systemctl restart zabbix-server
sleep 8
echo "zabbix-server: $(systemctl is-active zabbix-server), at boot: $(systemctl is-enabled zabbix-server)"
tail -n 4 /var/log/zabbix/zabbix_server.log
echo
echo "For the web setup wizard, show the DB password with:"
echo "  sudo grep ^DBPassword= $CONF"

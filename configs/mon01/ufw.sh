#!/usr/bin/env bash
# ufw rules for mon01. Reference list: type these one at a time (build guide M1.9).
# Everything is allowed only from the host-only management network.
# Outbound (apt, Zabbix passive checks to web01:10050) is allowed by default.
set -euo pipefail

sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow from 192.168.56.0/24 to any port 22    proto tcp comment 'ssh (admins + akbackup rsync)'
sudo ufw allow from 192.168.56.0/24 to any port 80    proto tcp comment 'Zabbix web UI'
sudo ufw allow from 192.168.56.0/24 to any port 10051 proto tcp comment 'Zabbix active checks'
sudo ufw allow from 192.168.56.0/24 to any port 20514 proto tcp comment 'rsyslog from web01 (E1)'

# SSH is allowed above, so enabling can't cut off your session
sudo ufw enable
sudo ufw status numbered

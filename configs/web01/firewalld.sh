#!/usr/bin/env bash
# firewalld zones for web01. This is a reference list, not a script to run blindly:
# type the commands one block at a time (build guide M1.8) and keep a
# second SSH session open until the last check passes.
#
# Design
#   mgmt   = source 192.168.56.0/24 (host-only). Every admin client lives here:
#            the Windows host (.1) and mon01 (.10). firewalld matches source zones
#            first and does not fall through to the interface zone, so mgmt needs
#            ssh, http and the Zabbix passive-check port.
#   public = everything else, in practice the labnet side (10.0.10.0/24).
#            http only: no ssh, no cockpit, no dhcpv6-client.
set -euo pipefail

# 1) Build the management zone
sudo firewall-cmd --permanent --new-zone=mgmt
sudo firewall-cmd --permanent --zone=mgmt --add-source=192.168.56.0/24
sudo firewall-cmd --permanent --zone=mgmt --add-service=ssh
sudo firewall-cmd --permanent --zone=mgmt --add-service=http
sudo firewall-cmd --permanent --zone=mgmt --add-port=10050/tcp      # Zabbix passive checks from mon01

# 2) Public keeps only http
sudo firewall-cmd --permanent --zone=public --add-service=http

# 3) Activate and CONFIRM mgmt is active before removing anything
sudo firewall-cmd --reload
sudo firewall-cmd --get-active-zones        # expect: mgmt  sources: 192.168.56.0/24

# 4) Only now: strip public down to http (open a NEW ssh session first to prove mgmt works)
sudo firewall-cmd --permanent --zone=public --remove-service=ssh
sudo firewall-cmd --permanent --zone=public --remove-service=cockpit || true
sudo firewall-cmd --permanent --zone=public --remove-service=dhcpv6-client || true
sudo firewall-cmd --reload

# 5) Check
sudo firewall-cmd --zone=mgmt --list-all
sudo firewall-cmd --zone=public --list-services    # expect: http

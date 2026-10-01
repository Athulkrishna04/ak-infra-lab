# Runbook: patching

Every patch run is a change and gets a change record ([template](../changes/TEMPLATE.md)) **before** it starts.

## Rocky Linux (web01)

```bash
# 0) Change record opened; VirtualBox snapshot "pre-patch-latest" taken (VM powered on is fine)
bash tests/verify.sh                               # on mon01: baseline must be green BEFORE patching

# 1) What's pending?
sudo dnf check-update
sudo dnf updateinfo list --security               # advisories: RLSA-..., severity
sudo dnf updateinfo info --security | less

# 2) Apply security updates only (a full `dnf upgrade` is a separate, planned change)
sudo dnf upgrade --security -y

# 3) Reboot needed?  (exit code 1 = yes)
sudo dnf needs-restarting -r || echo "REBOOT REQUIRED"
sudo dnf needs-restarting -s                       # services to restart if no reboot

# 4) Reboot inside the change window, then verify
sudo systemctl reboot
# after ~1 min, on mon01:
bash tests/verify.sh
```

Also check that Zabbix shows no new problems. Then close the change record with the `dnf history info last` output.

**Rollback:** first choice `sudo dnf history undo last`. If the system doesn't boot or is badly broken, revert the VirtualBox snapshot `pre-patch-latest`. If only the new kernel misbehaves, choose the previous kernel in the GRUB menu.

## Ubuntu (mon01)

```bash
sudo apt update
apt list --upgradable
sudo apt upgrade -y                                # or: sudo unattended-upgrade --dry-run -d
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required.pkgs
sudo systemctl reboot                              # if required
```

After the reboot, check that the Zabbix UI loads, `systemctl is-active zabbix-server mariadb nginx` all say active, and `verify.sh` is green.

**Zabbix packages are pinned to the 7.0 repo**, so `apt upgrade` gives 7.0.x minor updates only. A major version upgrade (8.0) is its own change (E5).

## Ubuntu automatic security updates (optional)

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
cat /etc/apt/apt.conf.d/20auto-upgrades
```

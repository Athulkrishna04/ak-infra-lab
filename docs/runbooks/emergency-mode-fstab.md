# Runbook: boot stops in emergency mode (bad /etc/fstab)

**Symptom:** on the console, web01 stops with *"You are in emergency mode… Give root password for maintenance"*. SSH doesn't answer, and Zabbix shows the host as unreachable.

## 1. Get a shell

Type the **root password**. This is why a root password was set during the install, even though root SSH is disabled.

## 2. Find the failed mount

```bash
systemctl --failed                                  # e.g. srv-app.mount
journalctl -xb | grep -iE 'mount|fstab|timed out' | tail -20
cat /etc/fstab
blkid                                               # the real UUIDs
lsblk -f
```

Typical causes: a mistyped UUID, a device that no longer exists (a disk was removed), or a wrong filesystem type.

## 3. Fix

```bash
mount -o remount,rw /                               # root may be read-only here
vi /etc/fstab                                       # correct the UUID or type; add "nofail" for non-critical data disks
systemctl daemon-reload                             # systemd generates .mount units from fstab
mount -a                                            # must print nothing
findmnt --verify                                    # must report 0 errors
systemctl default                                   # continue to multi-user.target (or reboot)
```

## 4. Prevention

- Always run `sudo mount -a && sudo findmnt --verify` after editing fstab, **before** a reboot.
- Mount by UUID, never `/dev/sdX`, because disk names can change when disks are added.
- Use `nofail` on data volumes the OS can boot without (the trade-off: services that depend on them must declare `RequiresMountsFor=`, like `ak-app.service` does).

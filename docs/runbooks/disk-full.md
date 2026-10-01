# Runbook: a filesystem is full or filling

**Triggered by:** the Zabbix "Space is low" trigger (80% warning, 90% high), healthcheck `WARN/CRIT: disk /srv/app at N%`, or an app writing errors like "No space left on device".

## 1. Which filesystem, and is it blocks or inodes?

```bash
df -h                       # blocks
df -i                       # inodes: 100% IUse% with free blocks = millions of tiny files
```

## 2. What is using it?

```bash
sudo du -xh --max-depth=1 /srv/app | sort -h | tail        # -x: stay on this filesystem
sudo find /srv/app -xdev -type f -size +100M -exec ls -lh {} +
```

## 3. `df` says full but `du` doesn't add up? Look for deleted files that are still open

A file deleted while a process still holds it open keeps its blocks until that process closes it.

```bash
sudo lsof +L1                       # link count 0 = deleted but open; shows PID and size
sudo lsof +L1 /srv/app
ps -o pid,user,cmd -p <PID>
systemctl status <PID>              # which unit owns it
```

**Fix:** restart or stop the owning service. If it can't be restarted, truncate the file through its fd: `sudo truncate -s 0 /proc/<PID>/fd/<FD>`.

## 4. Fix options, in this order

1. Remove what shouldn't be there: temp files, old archives, runaway logs. **Never** delete a file you can't explain; move it out first.
2. Rotate or compress logs (`logrotate -f` the matching config).
3. Grow the volume **online** if the data is legitimate:
   ```bash
   sudo vgs                                     # free space in vg_data?
   sudo lvextend -r -L +1G /dev/vg_data/lv_app  # -r grows the XFS filesystem too
   ```
   With no free extents, add a disk first: `pvcreate` + `vgextend`. XFS can grow but **cannot shrink**.

## 5. Verify and prevent

- `df -h /srv/app` is back under 80%, and the Zabbix problem has resolved.
- Prevention: a logrotate rule, an app-side cleanup job, or a capacity note in the incident report.

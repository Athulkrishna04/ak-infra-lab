# INC-008: web01 boots into emergency mode, one-character typo in the /srv/app UUID in fstab

| Field | Value |
|---|---|
| Node | web01 (Rocky Linux 10.2) |
| Detected by | drill: host down (SSH `Connection timed out`, `verify.sh` `No route to host`); the console shows emergency mode |
| Severity | P1: the whole host down, with no network services in emergency mode |
| Date / time | 2026-10-02 ~23:25 IST (injected) → 23:40:12 (fstab fixed) → clean boot |
| Time to resolve | about 15 min, including one fix attempt that skipped the actual edit |
| How blind | injected by hand: `tools/inject-fstab.sh` flips the last character of the `/srv/app` UUID and reboots **without** `mount -a` |
| Rollback point | snapshot `pre-boot-drills` (web01, offline, 21:42) |

## 1. Symptom

- From Windows: `ssh: connect to host 192.168.56.11 port 22: Connection timed out`. From mon01, `verify.sh`: `FAIL T01 … No route to host`, `4 PASS, 7 FAIL`. In emergency mode the network services don't run.
- The console ([screenshot](../screenshots/INC-008-emergency-mode.png)):

```text
[ TIME ] Timed out waiting for device dev-disk-by\x2duuid-00065e8e\x2d2656\x2d45ea\x2d…978a8508a0.device - /dev/disk/by-uuid/00065e8e-2656-45ea-8635-6897…
[DEPEND] Dependency failed for srv-app.mount - /srv/app.
[DEPEND] Dependency failed for ak-app.service - AK demo app (Python http.server behind nginx).
[DEPEND] Dependency failed for local-fs.target - Local File Systems.
[DEPEND] Dependency failed for selinux-autorelabel-mark.service - Mark the need to relabel after reboot.
[  OK  ] Reached target emergency.target - Emergency Mode.
You are in emergency mode. After logging in, type "journalctl -xb" to view
system logs, "systemctl reboot" to reboot, or "exit" to continue bootup.
Give root password for maintenance
```

What it told me: systemd waited the default **90 s** for a block device with that UUID and gave up. Because `/srv/app` has no `nofail`, `srv-app.mount` is required by `local-fs.target`, so its failure stops the boot and drops to `emergency.target`. `ak-app.service` failed with it (`RequiresMountsFor=/srv/app`). This is where the root password from INC-009 was needed. Several `Login incorrect` attempts preceded the correct one.

## 2. Diagnosis (emergency shell, [screenshot](../screenshots/INC-008-diagnosis-fstab-vs-blkid.png))

```text
[root@web01 ~]# systemctl --failed
  UNIT LOAD ACTIVE SUB DESCRIPTION
0 loaded units listed.
[root@web01 ~]# grep srv/app /etc/fstab
UUID=00065e8e-2656-45ea-8635-68978a8508a0 /srv/app xfs defaults 0 0
[root@web01 ~]# blkid | grep -v sdaa
/dev/mapper/vg_data-lv_app: UUID="00065e8e-2656-45ea-8635-68978a8508a5" BLOCK_SIZE="512" TYPE="xfs"
...
```

What it told me:
- `systemctl --failed` showed **0 units**. A dependency failure isn't a *failed* unit (the mount never ran), so the boot messages above are the real evidence, not `--failed`. Worth knowing.
- Compared character by character, fstab says `…8508a`**`0`** and the real filesystem (`blkid`) is `…8508a`**`5`**: **one character wrong at the end of the UUID**. The volume itself is healthy (`vg_data-lv_app`, xfs). Only the reference to it is wrong.

## 3. A fix attempt that skipped the edit ([screenshot](../screenshots/INC-008-mount-a-fails-before-fix.png))

```text
[root@web01 ~]# systemctl daemon-reload; mount -a; findmnt --verify;
mount: /srv/app: can't find UUID=00065e8e-2656-45ea-8635-68978a8508a0.
/srv/app
   [E] unreachable on boot required source: UUID=00065e8e-2656-45ea-8635-68978a8508a0
0 parse errors, 1 error, 0 warnings
[root@web01 ~]# systemctl default
Failed to connect to system scope bus via local transport: No such file or directory
```

The verification commands were run **before** the file was edited. That's useful in itself: it shows exactly what `mount -a` and `findmnt --verify` report for this mistake, and why the runbook says to run them **before** rebooting. Run after editing fstab on a running system, they catch this typo in a second, with no outage.

## 4. Root cause

`/etc/fstab` referenced `/srv/app` by a UUID with **one wrong character** (`…a0` instead of `…a5`), and nobody ran `mount -a` / `findmnt --verify` before rebooting. At boot no device with that UUID appeared. After 90 s, `srv-app.mount` failed, `local-fs.target` failed with it (the entry has no `nofail`), and systemd stopped in emergency mode: no network, no SSH, no services.

## 5. Fix

On the console, as root, the line was corrected to the real UUID from `blkid` (at **23:40:12**, the fstab modification time), then tested and rebooted:

```bash
sed -i 's/68978a8508a0 /68978a8508a5 /' /etc/fstab    # or vi: put the cursor on the character, `r`, `5`, `:wq`
grep srv/app /etc/fstab                               # UUID=…68978a8508a5 /srv/app xfs defaults 0 0
systemctl daemon-reload; mount -a; findmnt --verify   # silent; 0 errors
systemctl reboot
```

## 6. Verification

```text
$ grep srv/app /etc/fstab
UUID=00065e8e-2656-45ea-8635-68978a8508a5 /srv/app xfs defaults 0 0
$ uptime -p; systemctl is-system-running
up 1 minute
running
$ findmnt /srv/app; systemctl is-active ak-app nginx
TARGET   SOURCE                     FSTYPE OPTIONS
/srv/app /dev/mapper/vg_data-lv_app xfs    rw,relatime
active
active
```

- A clean unattended boot (`running`, no failed units); `/srv/app` mounted; ak-app and nginx up.
- Regression (`verify.sh`, about 23:43): **23 PASS / 0 FAIL / 0 SKIP**, including T07 (`/srv/app` on `vg_data-lv_app`) and T08 (ak-app).
- GRUB menu auto-hide restored (`grub2-editenv - set menu_auto_hide=1`, from the INC-009 drill).

## 7. Prevention

1. **Never reboot after an fstab edit without `sudo mount -a && sudo findmnt --verify`.** Section 3 shows they flag this exact typo instantly: `can't find UUID=…`, `[E] unreachable on boot required source`.
2. **`nofail` for data volumes the OS can boot without.** With `defaults,nofail`, web01 would have booted with networking and SSH, only `/srv/app` and `ak-app` failing. That's a P2 you can fix over SSH, not a P1 console job. `ak-app.service` already declares `RequiresMountsFor=/srv/app`, so it won't start against an empty directory. (A trade-off, so it's not applied silently: proposed as a change for E3.)
3. **Keep the root password in the vault.** Emergency mode needs it, and INC-009 showed what happens otherwise.
4. Manage fstab with configuration management (E3, `ansible.posix.mount` with the UUID from facts), so it's never hand-typed.

## 8. Timeline

| Time | Event |
|---|---|
| ~23:25 | `inject-fstab.sh`: last UUID character `5` → `0`; reboot without `mount -a` |
| +90 s | `Timed out waiting for device …8508a0` → `srv-app.mount`, `local-fs.target` failed → emergency mode |
| ~23:30 | Root login (after several wrong attempts); `grep fstab` vs `blkid`: `…a0` vs `…a5` |
| ~23:35 | `mount -a` / `findmnt --verify` before editing: `can't find UUID`, 1 error |
| 23:40:12 | fstab corrected to `…a5`; reboot |
| ~23:42 | Clean boot (`running`); `/srv/app` mounted; ak-app, nginx active |
| ~23:43 | `verify.sh` 23/0/0 |

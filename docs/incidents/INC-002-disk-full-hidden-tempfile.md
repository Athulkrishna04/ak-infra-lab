# INC-002: /srv/app at 95%, a hidden 4.6 GB temp file

| Field | Value |
|---|---|
| Node | web01 |
| Detected by | Zabbix filesystem alert (per ticket); the exact trigger name and time weren't recorded |
| Severity | P2 degraded: nothing was down yet, but a full filesystem stops app writes and restores |
| Date / time detected | 2026-10-02 20:44 IST (`ak-chaos.sh` injection at 20:44:18) |
| Time to resolve | about 3 min (fault 20:44:18 → space back and healthcheck OK before the 20:47 `verify.sh`) |
| How blind | `ak-chaos.sh` random: the fault was unknown until `reveal`, after the root cause was written |

## 1. Symptom

*Written before touching the CLI.*

- **Reported / alert text:** "TICKET: Monitoring alert - filesystem /srv/app on web01 is almost full."
- **Baseline just before:** `verify.sh` 23/0/0 at about 20:38; `/srv/app` was 130M used of 5.0G (3%) at 20:30.
- **What works:** the filesystem is mounted and writable, and inodes are fine (1%).
- **What doesn't:** `/srv/app` is at **95%** (4.7G of 5.0G, 254M free). Any larger write by the app, or a restore into it, would fail with "No space left on device".
- **Scope:** `/srv/app` (LVM `vg_data/lv_app`, XFS, 5 GB) on web01 only.
- **Failing test(s):** T15 healthcheck (disk threshold); the Zabbix filesystem space trigger.

## 2. Hypotheses (most likely first)

1.
2.
3.

## 3. Diagnosis: commands run

### 3.1 Triage round 1: how full, and what is using the space?

```text
$ df -h /srv/app
Filesystem                  Size  Used Avail Use% Mounted on
/dev/mapper/vg_data-lv_app  5.0G  4.7G  254M  95% /srv/app
======
$ df -i /srv/app
Filesystem                 Inodes IUsed  IFree IUse% Mounted on
/dev/mapper/vg_data-lv_app 519504     6 519498    1% /srv/app
======
$ sudo du -xh --max-depth=2 /srv/app | sort -h | tail -n 8
4.6G    /srv/app/public
4.6G    /srv/app
======
$ sudo ls -la /srv/app/public
total 4785156
drwxrwxr-x+ 2 root root         52 Oct  2 20:44 .
drwxr-xr-x. 3 root root         20 Oct  1 18:10 ..
-rw-r--r--. 1 root root         10 Oct  1 18:10 index.html
-rw-rw-r--+ 1 root root 4899995648 Oct  2 20:44 .upload-tmp-3356.bin
```

What it told me: **`df` (4.7G used) and `du` (4.6G counted) agree**, so the space is held by files that are visible in the directory tree, not by something hidden from `du` such as a deleted-but-open file. The 0.1G gap is XFS metadata and log; it was already there at the 3% baseline (130M used with only `index.html`). Inodes are at 1%, so this isn't inode exhaustion. One **hidden** file, `.upload-tmp-3356.bin`, holds **4.56 GiB**. It was created at 20:44 (the time of the alert) and is owned by root. Its name suggests a leftover temp file from an upload.

### 3.2 Round 2: is it safe to delete? (`stat`, `lsof`, content, auditd, `vgs`)

```text
$ F=/srv/app/public/.upload-tmp-3356.bin
$ sudo stat $F
  Size: 4899995648      Blocks: 9570304    IO Block: 4096   regular file
Access: (0664/-rw-rw-r--)  Uid: (    0/    root)   Gid: (    0/    root)
Context: unconfined_u:object_r:var_t:s0
Modify: 2026-10-02 20:44:18.617439400 +0530
 Birth: 2026-10-02 20:44:18.611439453 +0530
======
$ sudo lsof $F; echo lsof-exit=$?
lsof-exit=1
======
$ sudo head -c 64 $F | od -A d -c | head -n 3
0000000  \0  \0  \0  \0  \0  \0  \0  \0  \0  \0  \0  \0  \0  \0  \0  \0
*
0000064
======
$ sudo ausearch -k root_cmds -ts today -i | grep -A8 upload-tmp | grep -e proctitle -e auid=
type=PROCTITLE msg=audit(10/02/2026 20:44:18.608:1264) : proctitle=fallocate -l 4673M /srv/app/public/.upload-tmp-3356.bin
type=SYSCALL msg=audit(10/02/2026 20:44:18.608:1264) : ... syscall=execve success=yes ... ppid=3016 pid=3030
    auid=akadmin uid=root ... tty=pts1 ses=36 comm=fallocate exe=/usr/bin/fallocate ... key=root_cmds
======
$ sudo vgs vg_data
  VG      #PV #LV #SN Attr   VSize VFree
  vg_data   2   1   0 wz--n- 6.99g 1.99g
```

What it told me:
- **No process has it open** (`lsof` exit 1), so deleting it frees the space immediately and breaks nothing.
- **It holds no data**: the content is all zero bytes. `Blocks` × 512 = 4.56 GiB, so it is fully allocated, not sparse. It really occupies the space.
- **It was created on purpose:** `fallocate -l 4673M` by root at 20:44:18.608, under login `akadmin` (session 36), the same second as the alert. `fallocate` reserves space instantly without writing anything, which is why a 4.6 GB file appeared in milliseconds. The size was chosen to push the filesystem to about 95%.
- **Fix choice: delete, don't grow.** `lvextend -r` could only add the VG's last 1.99 GB: 4.7G of 7.0G = 67%. That would keep 4.6 GB of junk and leave no headroom for a real growth need. Growing a volume is the right fix only when the data is legitimate.

## 4. Root cause

A 4.56 GiB zero-filled file, `/srv/app/public/.upload-tmp-3356.bin`, was created with `fallocate` by root (login akadmin) at 20:44:18 and pushed `/srv/app` from 3% to 95%. Its leading dot hid it from a plain `ls`, and its `.upload-tmp` name made it look like a leftover upload. Nothing had it open, so it was pure dead weight. `df` and `du` agreed, because the space was held by a visible, linked file, not by a deleted-but-open one.

## 5. Fix

```bash
sudo rm -v /srv/app/public/.upload-tmp-3356.bin
df -h /srv/app            # back to about 3%
```

## 6. Verification

```text
removed '/srv/app/public/.upload-tmp-3356.bin'
Filesystem                  Size  Used Avail Use% Mounted on
/dev/mapper/vg_data-lv_app  5.0G  130M  4.9G   3% /srv/app
======
OK: web01 healthy
health-exit=0
```

- Failing test re-run: `/srv/app` back to the 3% baseline (130M, the same as before the fault); T15 healthcheck `OK`, exit 0.
- Regression smoke set (`bash tests/verify.sh`, about 20:47): **23 PASS / 0 FAIL / 0 SKIP**
- Zabbix problem resolved: not recorded.

## 7. Prevention

1. **Clean up temp files automatically, by name only.** A daily timer running `find /srv/app/public -xdev -type f -name '.upload-tmp-*' -mmin +1440 -delete` removes abandoned upload temp files after a day. (A directory-wide `systemd-tmpfiles` age rule on `/srv/app/public` would be wrong: it would also delete real content such as `index.html`.) Better still, the app should write uploads to a temp directory *outside* the data volume and move them in only when they're complete.
2. **Alert on the rate, not only the level.** This file took the volume from 3% to 95% in one second. A Zabbix trigger on a sudden jump in `vfs.fs.size[/srv/app,pused]` (for example, +20% within 5 minutes) flags a runaway writer before the disk is full, not after.
3. **Keep the VG headroom for real growth.** `vg_data` has 1.99 GB free. That's reserved for legitimate data, not for absorbing junk, which is why the fix was delete, not `lvextend`.

## 8. Reveal (after the root cause was written)

```text
$ sudo ak-chaos.sh reveal
fault: disk-full 2026-10-02 20:44:18
$ sudo ak-chaos.sh restore
restored: disk-full (marked done)
```

**The diagnosis matches the injected fault**: disk-full, catalog INC-002. The catalog's expected path (`df -h` → `du` → a hidden big file → remove) is the path that was followed. In addition, the file was proven safe to delete first (`lsof`, content, auditd), and the "grow the LV instead" option was considered and rejected with a reason.

**Telling INC-002 apart from INC-003** (same ticket text): here `df` and `du` **agreed**, so the space belonged to a visible file. If `du` had counted far less than `df` reported, the next step would have been `lsof +L1`, which finds a deleted file still held open by a process.

## 9. Timeline

| Time | Event |
|---|---|
| 20:44:18 | Fault injected (blind): `fallocate -l 4673M` → `/srv/app` 95% |
| ~20:45 | Round 1: `df` 95% / `du` 4.6G agree; `ls -la` finds hidden `.upload-tmp-3356.bin` (4.56 GiB, 20:44) |
| ~20:46 | Round 2: not open (`lsof`), all zeros, created by `fallocate` as root under akadmin (auditd); VG free only 1.99G → decision: delete |
| ~20:46 | Fix: `rm`; `df` back to 3%; healthcheck OK |
| ~20:47 | `verify.sh` 23/0/0; `reveal` = disk-full |

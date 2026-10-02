# INC-003: /srv/app at 94% but `du` finds nothing, a deleted file held open

| Field | Value |
|---|---|
| Node | web01 |
| Detected by | Zabbix filesystem alert (per ticket) |
| Severity | P2 degraded: /srv/app at 94%; nothing down yet |
| Date / time detected | 2026-10-02 22:11 IST (`ak-chaos.sh` injection at 22:11:02) |
| Time to resolve | about 5 min (fault 22:11:02 → unit stopped about 22:15, `df` 3%) |
| How blind | `ak-chaos.sh` random (the last fault in the pool, so partly known by elimination; the method was the point) |

## 1. Symptom

- **Reported / alert text:** "TICKET: Monitoring alert - filesystem /srv/app on web01 is almost full." The same text as INC-002.
- **Baseline just before:** `verify.sh` 23/0/0 at about 22:1x; `/srv/app` at 3% (130M).
- **What doesn't:** `/srv/app` at **94%** (4.7G of 5.0G, 323M free).
- **Scope:** `/srv/app` on web01.

## 2. Hypotheses

1. A large visible file, like INC-002: decided by whether `df` and `du` agree.
2. A deleted file still held open by a process: `du` can't see it, `df` still counts it.

## 3. Diagnosis: commands run

### 3.1 Round 1: `df` vs `du`, and deleted-but-open files

```text
$ df -h /srv/app
Filesystem                  Size  Used Avail Use% Mounted on
/dev/mapper/vg_data-lv_app  5.0G  4.7G  323M  94% /srv/app
======
$ sudo du -xh --max-depth=2 /srv/app | sort -h | tail -n 4
4.0K    /srv/app
4.0K    /srv/app/public
======
$ sudo lsof +L1 /srv/app
COMMAND    PID  USER   FD   TYPE DEVICE   SIZE/OFF NLINK NODE NAME
dbus-brok  863  dbus  mem    REG    0,1    2097152     0   84 /memfd:dbus-broker-log
dbus-brok  863  dbus  14u    REG    0,1    2097152     0   84 /memfd:dbus-broker-log (deleted)
nginx      975  root  mem    REG    0,1       4096     0  105 /dev/zero
nginx      976 nginx  mem    REG    0,1       4096     0  105 /dev/zero
python3   2393  root   3w    REG  253,2 4794089472     0  133 /srv/app/.logship.buf (deleted)
```

What it told me:
- **`df` (4.7G) and `du` (4.0K) disagree completely**, so the space is held by something that has no name in the directory tree. (In INC-002 they agreed, and the cause was a visible file.)
- `lsof +L1` lists open files with a link count below 1, i.e. **deleted but still open**. One of them is on `/srv/app` (device `253,2`): **`/srv/app/.logship.buf (deleted)`, 4,794,089,472 bytes, held by PID 2393 (`python3`, root) on fd 3, open for writing (`3w`)**.
- The other lines (dbus-broker's memfd, nginx's `/dev/zero` mappings) are on device `0,1`, not `/srv/app`. That's normal, and unrelated.
- A file's blocks are freed only when its **last** link *and* its **last** open descriptor are gone. Someone deleted the name, but PID 2393 still has the file open, so XFS can't free 4.5 GiB. There is nothing left to `rm`.

### 3.2 Round 2: what is PID 2393? (identify before you kill)

```text
$ systemctl status 2393 --no-pager | head -n 8
● ak-logship.service - AK log shipper
     Loaded: loaded (/run/systemd/transient/ak-logship.service; transient)
  Transient: yes
     Active: active (running) since Fri 2026-10-02 22:11:02 IST; 1min 55s ago
   Main PID: 2393 (python3)
      Tasks: 1 (limit: 9034)
     Memory: 1000.4M (peak: 1G)
======
$ sudo ls -l /proc/2393/fd/3
l-wx------. 1 root root 64 Oct  2 22:11 /proc/2393/fd/3 -> '/srv/app/.logship.buf (deleted)'
======
$ ps -o pid,user,lstart,cmd -p 2393
    PID USER                  STARTED CMD
   2393 root     Fri Oct  2 22:11:01 2026 /usr/bin/python3 -c  import os, time p = '/srv/app/.logship.buf' with open(p, 'wb') as f:     chunk = b'\0'
```

What it told me:
- The owner is **`ak-logship.service`, "AK log shipper"**, a **transient** unit (`/run/systemd/transient/`, `Transient: yes`). It was created ad hoc with `systemd-run` at 22:11:02, the ticket time. It has no unit file on disk and isn't part of the documented service set (nginx, ak-app, zabbix-agent2, …), so it's safe to stop.
- `/proc/2393/fd/3` shows the descriptor from the process's side: write-only (`l-wx`), pointing at the deleted buffer.
- The command line is an inline Python script that opens `/srv/app/.logship.buf`, writes zero chunks, then (per the reveal) unlinks it and sleeps forever, keeping the descriptor open.
- **Decision: stop the unit**, rather than truncating through `/proc/2393/fd/3`. The process is throwaway, so closing it is the clean fix. Truncating (`truncate -s 0 /proc/PID/fd/N`) is for processes you *can't* stop, like a production database with a runaway log.

## 4. Root cause

A transient service, `ak-logship.service` (PID 2393, python3, root), started at 22:11:02, wrote about 4.5 GiB to `/srv/app/.logship.buf`, **deleted the file and kept it open for writing**. With its last name gone, the file was invisible to `du` and `ls`. But XFS frees a file's blocks only when its last link **and** its last open descriptor are gone, so `df` still counted 4.7G used (94%). Removing anything couldn't help; only closing the descriptor could.

## 5. Fix

```bash
sudo systemctl stop ak-logship.service       # closes fd 3 -> the kernel frees the blocks at once
df -h /srv/app                               # back to 3%
```

**Deviation:** the first attempt ran `sudo systemctl stop UNIT` literally (`Failed to stop UNIT.service: Unit UNIT.service not loaded`). The instructions had used a placeholder instead of the real unit name from 3.2. The space was actually freed by `ak-chaos.sh restore`, which runs `systemctl stop ak-logship`, the same fix. Lesson for the runbook author: **give the exact command, not a placeholder**, when the value is already known.

## 6. Verification

```text
(first attempt, with the placeholder)
Failed to stop UNIT.service: Unit UNIT.service not loaded.
/dev/mapper/vg_data-lv_app  5.0G  4.7G  323M  94% /srv/app
1                                   <- logship still open
CRIT: disk /srv/app at 94%
======
fault: deleted-open-log 2026-10-02 22:11:02
restored: deleted-open-log (marked done)      <- systemctl stop ak-logship

(checked right after)
/dev/mapper/vg_data-lv_app  5.0G  130M  4.9G   3% /srv/app
ak-logship: inactive · PID 2393 gone
OK: web01 healthy   exit=0
```

- `/srv/app` back to the 3% baseline (130M), the moment the descriptor closed. Nothing had to be deleted.
- T15 healthcheck: `CRIT: disk /srv/app at 94%` before → `OK: web01 healthy` after.
- Regression (`verify.sh`): in the final check (Part F of E2).

## 7. Prevention

1. **Know the `df` ≠ `du` signal.** When `df` reports far more than `du` can find, run `lsof +L1 <mountpoint>` before anything else. It's the classic case where a log was "cleaned up" with `rm` while the daemon still writes to it.
2. **Rotate logs safely.** A daemon that keeps its log open needs `copytruncate`, or a reopen signal (`postrotate … kill -HUP`), in logrotate. Plain `rm` of an open log never frees space until restart.
3. **Transient units leave traces.** `systemctl list-units --all | grep transient`, or `ls /run/systemd/transient/`, shows ad-hoc `systemd-run` services. Unknown ones on a server deserve a question.
4. **Watch the rate.** The same rate-of-change trigger proposed in INC-002 (+20% within 5 minutes on `/srv/app`) fires for both disk faults, visible file or not.

## 8. Reveal

```text
$ sudo ak-chaos.sh reveal
fault: deleted-open-log 2026-10-02 22:11:02
$ sudo ak-chaos.sh restore
restored: deleted-open-log (marked done)
```

**The diagnosis matches the injected fault**: deleted-but-open file, catalog INC-003. The catalog's expected path (`df` vs `du` disagree → `lsof +L1` → PID → `systemctl status <PID>` → stop the unit) is exactly the path that was followed. This was the last of the six faults, so the type was partly known by elimination; the evidence chain was still built step by step.

## 9. Timeline

| Time | Event |
|---|---|
| 22:11:02 | Fault injected: transient `ak-logship.service` writes 4.5 GiB, unlinks, keeps fd 3 open |
| ~22:12 | Round 1: `df` 94% vs `du` 4.0K; `lsof +L1` → PID 2393, `.logship.buf (deleted)`, 4.79 GB |
| ~22:13 | Round 2: `systemctl status 2393` → transient `ak-logship.service`; decision: stop it |
| ~22:15 | `stop UNIT` (placeholder) fails; `restore` stops `ak-logship`; `df` 3%, healthcheck OK |

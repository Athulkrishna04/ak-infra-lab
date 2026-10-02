# INC-005: `/` returns 403, wrong SELinux label (`user_tmp_t`) on index.html

| Field | Value |
|---|---|
| Node | web01 |
| Detected by | user ticket (Zabbix view not recorded) |
| Severity | P1 for the static site: `/` returned 403 to every client; `/app/` unaffected |
| Date / time detected | 2026-10-02 22:04 IST (`ak-chaos.sh` injection at 22:04:09) |
| Time to resolve | about 4 min (fault 22:04:09 → `restorecon` at 22:07:51) |
| How blind | `ak-chaos.sh` random: the fault was unknown until `reveal`, after the root cause was written |

## 1. Symptom

- **Reported / alert text:** "TICKET: Users report that http://web01.lab.local/ is not working."
- **Note:** the third time this ticket text has appeared. INC-004 (nginx config) and INC-006 (firewall) are already done, so this is a different fault behind the same words.
- **Baseline:** `verify.sh` 23/0/0 at about 21:35; akdev re-test OK at about 22:03.

- **What works:** `/app/` = 200 from every vantage point; nginx and ak-app `active`.
- **What doesn't:** `/` = **403** from Windows, from mon01 (mgmt and public) and locally.
- **Scope:** the static site (`/srv/www`) on web01, for every client. Not network-related: the same code everywhere, including 127.0.0.1.

## 3. Diagnosis: commands run

### 3.1 Round 1: the matrix plus the nginx error log, labels and AVCs

```text
PS> curl.exe ... http://192.168.56.11/ http://192.168.56.11/app/
403 http://192.168.56.11/
200 http://192.168.56.11/app/

mon01$ for u in ...; do echo $u $(curl ... $u); done
http://192.168.56.11/ 403
http://192.168.56.11/app/ 200
http://10.0.10.6/ 403
http://10.0.10.6/app/ 200

web01$ sudo tail -n 4 /var/log/nginx/error.log
2026/10/02 22:05:14 [error] 976#976: *60 open() "/srv/www/index.html" failed (13: Permission denied), client: 10.0.10.5, server: web01.lab.local, request: "GET / HTTP/1.1", host: "10.0.10.6"
2026/10/02 22:05:25 [error] 976#976: *63 open() "/srv/www/index.html" failed (13: Permission denied), client: 127.0.0.1, ...
2026/10/02 22:05:31 [error] 976#976: *66 open() "/srv/www/index.html" failed (13: Permission denied), client: 192.168.56.10, ...
======
web01$ ls -lZ /srv/www
-rw-r--r--. 1 root root unconfined_u:object_r:user_tmp_t:s0 9 Oct  2 22:04 index.html
======
web01$ sudo ausearch -m AVC -ts recent -i | tail -n 4
type=PATH ... name=/srv/www/index.html inode=8398868 ... mode=file,644 ouid=root ogid=root ... obj=unconfined_u:object_r:user_tmp_t:s0
type=SYSCALL ... syscall=openat success=no exit=EACCES(Permission denied) ... comm=nginx exe=/usr/sbin/nginx subj=system_u:system_r:httpd_t:s0
type=AVC msg=audit(10/02/2026 22:05:31.040:402) : avc:  denied  { open } for  pid=976 comm=nginx path=/srv/www/index.html dev="dm-0" ino=8398868
    scontext=system_u:system_r:httpd_t:s0 tcontext=unconfined_u:object_r:user_tmp_t:s0 tclass=file permissive=0
```

What it told me:
- **403 everywhere, only on `/`** → nginx is up and reachable, and it refuses one resource. `/app/` is proxied to ak-app, so nginx never reads it from disk, and it still works.
- The error log names the exact file and errno 13, **Permission denied**.
- **The classic permissions are fine** (`-rw-r--r--`, readable by everyone), but the **SELinux type is `user_tmp_t`**. At the 21:42 kit run it was `httpd_sys_content_t`. The modification time, 22:04, is the moment of the ticket, and the size (9 bytes) is unchanged: same content, new inode, wrong label.
- The **AVC** proves it: `denied { open }` for `httpd_t` (nginx) on a `user_tmp_t` file, with `permissive=0` (enforcing). That's mandatory access control (MAC) overriding discretionary access control (DAC).

## 4. Root cause

`/srv/www/index.html` was replaced at 22:04 by a copy carrying the label **`user_tmp_t`**, the type of a file created in `/tmp`. A new file created in `/tmp` and **moved** into place with `mv` keeps its original label; `cp` (or creating the file in place) would have taken the directory's default, `httpd_sys_content_t`. The SELinux policy lets nginx (`httpd_t`) read web-content types but not users' temp files, so every request for `/` got **403** while `/app/` (proxied, never read from disk) kept working. `chmod` can't fix this, and `setenforce 0` would only hide it.

## 5. Fix

Ask the policy what the label *should* be, then restore it. **Don't** touch permissions, and **don't** `setenforce 0`:

```text
$ matchpathcon /srv/www/index.html
/srv/www/index.html     system_u:object_r:httpd_sys_content_t:s0
$ sudo restorecon -v /srv/www/index.html
Relabeled /srv/www/index.html from unconfined_u:object_r:user_tmp_t:s0 to unconfined_u:object_r:httpd_sys_content_t:s0
$ ls -Z /srv/www/index.html
unconfined_u:object_r:httpd_sys_content_t:s0 /srv/www/index.html
```

`restorecon` works here because `/srv/www` has a **persistent** file-context rule (`semanage fcontext`, from M2), so the policy knows the right type for this path. A `chcon` would also have fixed it, but only until the next relabel.

## 6. Verification

- Failing test re-run: local `/` → **200** right after `restorecon`.
- Regression smoke set (`bash tests/verify.sh`, about 22:1x): **23 PASS / 0 FAIL / 0 SKIP** (T04 SELinux Enforcing, T05 `/` and `/app/` = 200, T17 public side).
- From Windows, and the Zabbix view of the external check (`ext-http-mgmt` step `home` requires 200, so a 403 should fail it): not recorded.

### 6.1 Who? auditd `root_cmds`

```text
$ sudo ausearch -k root_cmds -ts today -i | grep -A8 srv/www/index.html | grep -e proctitle -e auid= | tail -n 4
type=PROCTITLE msg=audit(10/02/2026 22:07:51.892:490) : proctitle=restorecon -v /srv/www/index.html
type=SYSCALL ... auid=akadmin uid=root ... comm=restorecon exe=/usr/sbin/setfiles ... key=root_cmds
type=PROCTITLE msg=audit(10/02/2026 22:07:51.916:493) : proctitle=sudo ausearch -k root_cmds -ts today -i
type=SYSCALL ... auid=akadmin uid=akadmin ... comm=sudo exe=/usr/bin/sudo ... key=root_cmds
```

A dead end, as written: `tail -n 4` kept only the *latest* matches, which were the fix itself and the search command. The 22:04 `mv` that put the file in place was cut off. The right query is `head` instead of `tail`, or `-ts 22:04:00 -te 22:05:00`. Lesson: when hunting the cause, anchor the search on the **fault time**, not on "most recent".

## 7. Prevention

1. **Deploy web content with `cp` or `install`, never `mv` from `/tmp`.** A new file takes the label of the directory it's created in, while a moved file keeps its old label. Better still, publish through a deploy step that ends with `restorecon -Rv /srv/www`.
2. **Detect it early.** `restorecon -Rnv /srv/www` (dry-run) lists any file whose label differs from the policy, and prints nothing when all is well. It's cheap to run in `healthcheck.sh` or as a Zabbix item, alerting on non-empty output.
3. **The external check covers it.** `ext-http-mgmt` (INC-006 follow-up) requires `200` on `/`, so a 403 fails the step. That's monitoring by outcome, not by cause.
4. **Never "fix" SELinux with `setenforce 0`.** It would have hidden the symptom and removed the protection from the whole box. The AVC log plus `matchpathcon` give the precise fix in seconds.

## 8. Reveal (after the root cause was written)

```text
$ sudo ak-chaos.sh reveal
fault: selinux-context 2026-10-02 22:04:09
$ sudo ak-chaos.sh restore
restored: selinux-context (marked done)
```

**The diagnosis matches the injected fault**: wrong file context, catalog INC-005. The catalog's expected path (`ls -l` looks fine → `ls -Z` shows `user_tmp_t` → `ausearch` → `restorecon`) is the path that was followed. The nginx error log and the AVC were read in the same first round.

## 9. Timeline

| Time | Event |
|---|---|
| 22:04:09 | Fault injected (blind): index.html replaced through `mv` from `/tmp` |
| 22:05:14–22:05:31 | nginx `open() … (13: Permission denied)` for clients 10.0.10.5, 127.0.0.1, 192.168.56.10 |
| 22:05:31 | AVC `denied { open }` `httpd_t` → `user_tmp_t` |
| ~22:06 | Round 1 read: 403 only on `/`, DAC fine, label `user_tmp_t` → root cause |
| 22:07:51 | `restorecon -v` → `httpd_sys_content_t`; local `/` = 200; `reveal` = selinux-context |
| ~22:1x | `verify.sh` 23/0/0 |

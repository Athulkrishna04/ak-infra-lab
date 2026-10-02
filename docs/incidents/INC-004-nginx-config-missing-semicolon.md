# INC-004: website down, nginx won't start after a config edit (missing `;`)

| Field | Value |
|---|---|
| Node | web01 |
| Detected by | Zabbix trigger (20:31:36, 9 s after the fault), then user ticket |
| Severity | P1 service down: `/` and `/app/` unreachable for every client |
| Date / time detected | 2026-10-02 20:31 IST (`ak-chaos.sh` injection at 20:31:27) |
| Time to resolve | about 6 min to service restored (nginx `active` before the 20:38 `verify.sh`) |
| How blind | `ak-chaos.sh` random: the fault was unknown until `reveal`, after the root cause was written |

## 1. Symptom

*Written before touching the CLI.*

- **Reported / alert text:** "TICKET: Users report that http://web01.lab.local/ is not working."
- **Baseline just before:** `verify.sh` 23 PASS / 0 FAIL / 0 SKIP at about 20:30 (T05 `/` = 200, `/app/` = 200; T17 public side = 200).
- **What works:** SSH to web01; the backend `ak-app` is `active`.
- **What doesn't:** `/` and `/app/`: no HTTP answer at all (`000`) from Windows on the mgmt side.
- **Scope:** web01's nginx: the `nginx` unit is in state `failed`. Not a network-path problem: the service itself is down, so every client (mgmt, public, local) is affected.
- **Failing test(s):** T05 (`/` and `/app/` = 200), T17 (public side), T10 trigger "nginx is down on web01" expected.

## 2. Hypotheses (most likely first)

1.
2.
3.

## 3. Diagnosis: commands run

### 3.1 Triage round 1: where does it fail? (outside-in)

```text
PS> curl.exe -s -m 5 -o NUL -o NUL -w "%{http_code} %{url}\n" http://192.168.56.11/ http://192.168.56.11/app/
000 http://192.168.56.11/
000 http://192.168.56.11/app/

web01$ systemctl is-active nginx ak-app
failed
active
```

(The curl loops run through `ssh mon01 '…'` / `ssh web01 '…'` returned nothing usable: PowerShell 5.1 strips the inner double quotes when it hands the command to ssh, so `printf` got broken arguments. A dead end caused by the tooling, not by the system.)

What it told me: `000` means nothing answered on port 80, not an HTTP error. `nginx` is `failed` while `ak-app` is `active`. The fault is at the **service layer**: nginx won't run. The network path and the backend aren't the first suspects. Next: why did nginx stop, and why won't it start?

### 3.2 Triage round 2: why did nginx fail? (`systemctl status`, journal, `nginx -t`) on web01

```text
× nginx.service - The nginx HTTP and reverse proxy server
     Active: failed (Result: exit-code) since Fri 2026-10-02 20:31:27 IST; 5min ago
    Process: 1977 ExecStartPre=/usr/sbin/nginx -t (code=exited, status=1/FAILURE)
======
Oct 02 19:46:28 web01 nginx[965]: nginx: configuration file /etc/nginx/nginx.conf test is successful
Oct 02 20:31:27 web01 systemd[1]: Stopping nginx.service - The nginx HTTP and reverse proxy server...
Oct 02 20:31:27 web01 systemd[1]: nginx.service: Deactivated successfully.
Oct 02 20:31:27 web01 systemd[1]: Starting nginx.service - The nginx HTTP and reverse proxy server...
Oct 02 20:31:27 web01 nginx[1977]: nginx: [emerg] invalid number of arguments in "proxy_pass" directive in /etc/nginx/conf.d/app.conf:17
Oct 02 20:31:27 web01 nginx[1977]: nginx: configuration file /etc/nginx/nginx.conf test failed
Oct 02 20:31:27 web01 systemd[1]: nginx.service: Failed with result 'exit-code'.
======
$ sudo nginx -t
nginx: [emerg] invalid number of arguments in "proxy_pass" directive in /etc/nginx/conf.d/app.conf:17
nginx: configuration file /etc/nginx/nginx.conf test failed
```

What it told me: nginx didn't crash. It was **restarted** at 20:31:27 (a clean stop, then a start), and the start failed in `ExecStartPre`, the `nginx -t` config test that the unit runs before launching. The config had been valid at the 19:46 boot, so `/etc/nginx/conf.d/app.conf` changed between 19:46 and 20:31, and the restart loaded the broken version. The error points at the `proxy_pass` directive on line 17. Its timestamp shows it was last written at 20:31, while the repo copy (the source of truth) is from 12:08 and the same size.

### 3.3 Monitoring view (Zabbix *Monitoring → Problems*)

| Time | Severity | Problem |
|---|---|---|
| 20:31:36 | High | Health check CRIT on web01 |
| 20:31:38 | High | nginx is down on web01 |

Zabbix raised both 9–11 s after the fault, **before** the user ticket: monitoring worked as designed (T10 trigger). The same screen shows "System time is out of sync" on web01 from 20:15:48 to 20:23:24, which corroborates the clock finding in CHG-001/CHG-002.

### 3.4 Round 3: what changed? The live file vs the repo copy (source of truth) on web01

```text
$ sed -n 14,19p /etc/nginx/conf.d/app.conf
    location /app/ {
        proxy_pass http://127.0.0.1:8080/
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
======
$ diff ~/ak-infra-lab/configs/web01/nginx/conf.d/app.conf /etc/nginx/conf.d/app.conf
16c16
<         proxy_pass http://127.0.0.1:8080/;
---
>         proxy_pass http://127.0.0.1:8080/
```

What it told me: the only difference is the **`;` missing at the end of line 16**, yet nginx reported line 17. Without the terminator, the nginx parser keeps reading the directive until the next `;`, at the end of line 17. It therefore sees `proxy_pass http://127.0.0.1:8080/ proxy_set_header Host $host;` as one directive with four arguments, and `proxy_pass` takes exactly one. **A config error is often reported on the line after the real mistake.**

(A first attempt to find *who* changed the file through `ausearch -k root_cmds | grep -E "proctitle|auid"` was mangled by PowerShell's quote handling, the same tooling dead end as in 3.1.)

### 3.5 Who changed it? auditd `root_cmds` (E1) on web01

```text
$ sudo ausearch -k root_cmds -ts today -i -x sed | grep -e proctitle -e auid= | tail -n 4
type=PROCTITLE msg=audit(10/02/2026 20:31:27.036:642) : proctitle=sed -i s|proxy_pass http://127.0.0.1:8080/;|proxy_pass http://127.0.0.1:8080/ | /etc/nginx/conf.d/app.conf
type=SYSCALL msg=audit(10/02/2026 20:31:27.036:642) : arch=x86_64 syscall=execve success=yes exit=0 ... ppid=1958 pid=1969
    auid=akadmin uid=root ... tty=pts1 ses=17 comm=sed exe=/usr/bin/sed ... key=root_cmds
```

What it told me: the edit was a root `sed -i` that replaced `;` with a space on the `proxy_pass` line. It ran at **20:31:27.036**, the same second nginx was restarted, by login **`akadmin`** (session 17), through sudo. An earlier `sed` at 20:14:42 (`sed -n 1,30p`, read-only) belongs to CHG-001's `dnf history info last | sed`, which shows `root_cmds` catches everything, not just changes. Without the E1 audit rules, "who changed the config?" would have no answer here.

## 4. Root cause

`/etc/nginx/conf.d/app.conf` was edited at 20:31:27 (root `sed -i`, by login akadmin, per auditd) and the `;` terminating `proxy_pass` on line 16 was removed. nginx was then restarted. Its pre-start config test (`ExecStartPre=nginx -t`) rejected the whole configuration, and nginx stayed down. Because nginx validates *all* included files before it starts, one bad directive in the `/app/` block took the **entire** site down (`/` as well as `/app/`): nothing listened on port 80, hence `000` rather than an HTTP error.

## 5. Fix

Restore the file from the source of truth (the repo copy), validate, then start:

```bash
sudo install -m 0644 ~/ak-infra-lab/configs/web01/nginx/conf.d/app.conf /etc/nginx/conf.d/app.conf
ls -Z /etc/nginx/conf.d/app.conf      # system_u:object_r:httpd_config_t:s0  (correct label, no restorecon needed)
sudo nginx -t                         # syntax is ok / test is successful
sudo systemctl start nginx            # -> active
```

## 6. Verification

- Failing test re-run: `systemctl is-active nginx` → `active`; T05 `/` = 200, `/app/` = 200; T17 public side = 200.
- Regression smoke set (`bash tests/verify.sh`, about 20:38): **23 PASS / 0 FAIL / 0 SKIP**
- Zabbix problems "nginx is down on web01" and "Health check CRIT on web01": RESOLVED after the fix.

## 7. Prevention

1. **Reload, don't restart, after a config change, and test first.** `nginx -t && systemctl reload nginx`. On reload, the running master tests the new config and keeps serving with the old one if it's invalid. A **restart** stops the working server *before* finding out the new config is broken, and that turned a typo into an outage.
2. **Detect drift from the source of truth.** A Zabbix item `vfs.file.cksum[/etc/nginx/conf.d/app.conf]` with a "changed" trigger would flag any edit outside a change record. In E3, Ansible deploys this file from the repo and its handler runs `nginx -t` before a reload, so a broken file never replaces the running config.
3. auditd already records who ran what as root (`root_cmds`), so an unplanned edit can always be traced to a login.

## 8. Reveal (after the root cause was written)

```text
$ sudo ak-chaos.sh reveal
fault: nginx-config 2026-10-02 20:31:27
$ sudo ak-chaos.sh restore
restored: nginx-config (marked done)
$ systemctl is-active nginx
active
```

**The diagnosis matches the injected fault**: an nginx config error, catalog INC-004. The expected path in the catalog (`systemctl status` → `journalctl -u nginx` → `nginx -t` names the line) is the path that was followed. In addition, `diff` against the repo found the exact character, and auditd found who and when.

## 9. Timeline

| Time | Event |
|---|---|
| 20:31:27 | Fault injected (blind); the restart fails, nginx `failed` |
| 20:31:36 / 20:31:38 | Zabbix: "Health check CRIT on web01", "nginx is down on web01" (High) |
| ~20:33 | Triage round 1: `000` from Windows, nginx `failed`, ak-app `active` → service layer |
| ~20:36 | Round 2: `nginx -t`: `invalid number of arguments in "proxy_pass" … app.conf:17` |
| ~20:37 | Round 3: `diff` with the repo: missing `;` on line 16; fixed from the repo, `nginx -t` OK, nginx `active` |
| ~20:38 | `verify.sh` 23 PASS / 0 FAIL / 0 SKIP; Zabbix problems resolved |
| after | auditd: `sed -i` by `auid=akadmin` at 20:31:27.036; `ak-chaos.sh reveal` = nginx-config |

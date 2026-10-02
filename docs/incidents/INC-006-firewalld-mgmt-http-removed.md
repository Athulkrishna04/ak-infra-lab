# INC-006: site unreachable from the mgmt network, firewalld `mgmt` zone lost `http` (no alert)

| Field | Value |
|---|---|
| Node | web01 |
| Detected by | **user ticket only.** Zabbix raised nothing, because its nginx check runs on the box itself |
| Severity | P1 service down for every client in 192.168.56.0/24 (admins, mon01, Windows); public side unaffected |
| Date / time detected | 2026-10-02 20:50 IST (`ak-chaos.sh` injection at 20:50:05) |
| Time to resolve | about 5 min (fault 20:50:05 → fix and Windows `200` before the 20:55 `verify.sh`) |
| How blind | `ak-chaos.sh` random: the fault was unknown until `reveal`, after the root cause was written |

## 1. Symptom

*Written before touching the CLI.*

- **Reported / alert text:** "TICKET: Users report that http://web01.lab.local/ is not working."
- **Baseline just before:** `verify.sh` 23/0/0 at about 20:47 (T05 `/` = 200, `/app/` = 200; T17 public side = 200).
- **Note:** the same ticket text as INC-004 (nginx config, already done), so this is a different fault with the same symptom.
- **What works:** HTTP on the **public** side (10.0.10.6: `/` and `/app/` = 200); HTTP **locally** on web01 (200); nginx and ak-app `active`; **SSH** to web01 over the mgmt address 192.168.56.11.
- **What doesn't:** HTTP over the **mgmt** network (192.168.56.11) from Windows and from mon01: `000`, no HTTP answer.
- **Scope:** port 80 on web01's mgmt side only. That's every admin and internal client (all of them are in 192.168.56.0/24), but not the public side.
- **Failing test(s):** T05 (`/`, `/app/` via mgmt). T17 (public) still passes. **Zabbix raised nothing**: the "nginx is down" check (`net.tcp.service[http,,80]`) runs on web01 itself, so it never crosses the broken path.

## 2. Hypotheses (most likely first)

1. **Host firewall (firewalld) on web01 no longer allows http in the `mgmt` zone.** That explains everything: the mgmt source 192.168.56.0/24 is bound to `mgmt`, which normally allows ssh + http + 10050. SSH still works, http doesn't, and the public zone is unaffected.
2. nginx bound only to the 10.0.10.x address after a config change. Unlikely: `app.conf` is identical to the repo (checked at 20:51), and nginx answers on 127.0.0.1 too.
3. Something on the path (the host-only network / VirtualBox) blocking port 80 only. Unlikely: mon01 and Windows both fail the same way, and SSH over the same path works.

## 3. Diagnosis: commands run

### 3.1 Triage round 1: where does it fail? (outside-in)

```text
PS> curl.exe -s -m 5 -o NUL -o NUL -w "%{http_code} %{url}\n" http://192.168.56.11/ http://192.168.56.11/app/
000 http://192.168.56.11/
000 http://192.168.56.11/app/

mon01$ for u in http://192.168.56.11/ http://192.168.56.11/app/ http://10.0.10.6/ http://10.0.10.6/app/; do echo $u $(curl -s -o /dev/null -m 5 -w %{http_code} $u); done
http://192.168.56.11/ 000
http://192.168.56.11/app/ 000
http://10.0.10.6/ 200
http://10.0.10.6/app/ 200

web01$ systemctl is-active nginx ak-app; for u in http://127.0.0.1/ http://127.0.0.1/app/; do ...; done
active
active
http://127.0.0.1/ 200
http://127.0.0.1/app/ 200
```

Zabbix *Problems*: nothing new for web01 since INC-002 (last entry "Health check CRIT", 20:44:36–20:48:36, RESOLVED).

What it told me: **the service is fine and the network path is not, but only for port 80 on the mgmt side.** nginx answers locally and on the public address, so it is not the web server, the files or the backend. SSH over the same mgmt address works, so it is not the interface, routing or VirtualBox network. Only one thing treats "http from 192.168.56.0/24" differently from "http from 10.0.10.0/24" and "ssh from 192.168.56.0/24": the **firewalld zone** each source lands in. And the monitoring missed it entirely, because it checks from inside the box.

(Side check, read-only: `app.conf` on web01 is identical to the repo copy, so the INC-004 fix is intact. A `diff` in the terminal screenshot was scrollback from 20:37.)

### 3.2 Round 2: how does the connection fail, and what do the zones allow?

```text
mon01$ curl -sS -m 5 -o /dev/null http://192.168.56.11/; echo exit=$?
curl: (7) Failed to connect to 192.168.56.11 port 80 after 0 ms: Couldn't connect to server
exit=7

web01$ sudo firewall-cmd --get-active-zones
mgmt
  sources: 192.168.56.0/24
public (default)
  interfaces: enp0s3 enp0s8
======
web01$ sudo firewall-cmd --zone=mgmt --list-all
mgmt (active)
  target: default
  sources: 192.168.56.0/24
  services: ssh
  ports: 10050/tcp
  ...
======
permanent: ssh                    <- firewall-cmd --permanent --zone=mgmt --list-services
public: http                      <- firewall-cmd --zone=public --list-services
```

What it told me:
- **Rejected, not dropped.** curl failed after **0 ms** with exit 7, so the packets reached web01 and its firewall answered with a reject at once. A silent drop would have timed out after 5 s (exit 28), and a missing listener would say "Connection refused". nginx *is* listening, as the local and public 200s show.
- **`http` is missing from the `mgmt` zone**, which now has only `ssh` + `10050/tcp`. The design in [ip-plan.md](../ip-plan.md) says ssh + **http** + 10050/tcp.
- **It's in runtime and permanent**, so a `firewall-cmd --reload` or a reboot would *not* bring it back. The fix needs both.
- **Why `public` doesn't save it:** `enp0s8` (the host-only adapter) is in the `public` zone, which still allows http, yet mgmt clients are rejected. firewalld picks the zone by **source binding before interface**: a packet from 192.168.56.0/24 is handled entirely by `mgmt` and never falls through to `public`. Whatever `mgmt` doesn't allow is rejected by its default target.

## 4. Root cause

The `http` service was removed from web01's firewalld **`mgmt`** zone, in both the runtime and the permanent configuration. Every client in 192.168.56.0/24 (Windows, mon01, every admin) is bound to `mgmt` by source, so their port-80 connections were rejected instantly (`curl` exit 7 after 0 ms). Public-side clients (10.0.10.0/24, zone `public`, http allowed) and local requests were unaffected. nginx itself was healthy the whole time, so the on-box Zabbix check `net.tcp.service[http,,80]` stayed green: **a full outage for the users with zero alerts.**

## 5. Fix

```bash
sudo firewall-cmd --zone=mgmt --add-service=http              # runtime: takes effect now
sudo firewall-cmd --permanent --zone=mgmt --add-service=http  # permanent: survives reload/reboot
sudo firewall-cmd --zone=mgmt --list-services                 # -> http ssh
```

## 6. Verification

```text
web01$ sudo firewall-cmd --zone=mgmt --add-service=http && sudo firewall-cmd --permanent --zone=mgmt --add-service=http
success
success
runtime: http ssh permanent: http ssh

PS> curl.exe -s -m 5 -o NUL -o NUL -w "%{http_code} %{url}\n" http://192.168.56.11/ http://192.168.56.11/app/
200 http://192.168.56.11/
200 http://192.168.56.11/app/
```

- Failing test re-run: T05 from Windows and from mon01 → `200` / `200`; runtime **and** permanent both list `http ssh`.
- Regression smoke set (`bash tests/verify.sh`, about 20:55): **23 PASS / 0 FAIL / 0 SKIP** (T05, T06, T16, T17 all PASS: the zone split is intact).
- Zabbix: nothing to resolve. That's the problem; see Prevention.

### 6.1 Who changed it? auditd `root_cmds`

```text
$ sudo ausearch -k root_cmds -ts today -i | grep -A8 remove-service | grep -e proctitle -e auid=
type=PROCTITLE msg=audit(10/02/2026 20:50:05.040:1756) : proctitle=/usr/bin/python3 -sP /bin/firewall-cmd --quiet --zone=mgmt --remove-service=http
type=SYSCALL   msg=audit(10/02/2026 20:50:05.040:1756) : ... auid=akadmin uid=root ... ses=49 comm=firewall-cmd exe=/usr/bin/python3.12 ... key=root_cmds
type=PROCTITLE msg=audit(10/02/2026 20:50:05.206:1758) : proctitle=/usr/bin/python3 -sP /bin/firewall-cmd --quiet --permanent --zone=mgmt --remove-service=http
type=SYSCALL   msg=audit(10/02/2026 20:50:05.206:1758) : ... auid=akadmin uid=root ... ses=49 comm=firewall-cmd exe=/usr/bin/python3.12 ... key=root_cmds
```

Two commands, 166 ms apart, under login akadmin, session 49: first the runtime change, then the permanent one. That confirms the round-2 reading that the change was in both layers, so a `firewall-cmd --reload` or a reboot would **not** have fixed it. `firewall-cmd` is a Python program, which is why `exe=/usr/bin/python3.12` and `comm=firewall-cmd`: searching by executable name (`-x firewall-cmd`) would have missed it, and grepping the command line found it.

## 7. Prevention

The real lesson is that **a full outage for every admin produced zero alerts.** Zabbix's nginx check, `net.tcp.service[http,,80]`, is run *by the agent on web01*. It connects to web01 from web01, never crosses the firewall's mgmt zone, and stayed green throughout.

1. **Monitor from the user's side of the network.** Add a Zabbix **simple check** run by the server on mon01, `net.tcp.service[http,192.168.56.11,80]`, or better a **web scenario** that fetches `http://192.168.56.11/` and `/app/` and expects 200. Its trigger fires on exactly this failure (see the follow-up below). The on-box check stays too: the two together tell "nginx down" apart from "nginx up but unreachable".
2. **Firewall changes are changes.** They go through a change record. The intended zone contents are in [ip-plan.md](../ip-plan.md); in E3 Ansible enforces them (`ansible.posix.firewalld`, `permanent: true, immediate: true`), so drift is corrected on the next run and shows up as `changed`.
3. **Check both layers when you fix.** Runtime alone looks fixed until the next reload or reboot, and then the outage comes back. Fix and verify `--permanent` too, as done here.

## 8. Reveal (after the root cause was written)

```text
$ sudo ak-chaos.sh reveal
fault: firewall-http 2026-10-02 20:50:05
$ sudo ak-chaos.sh restore
restored: firewall-http (marked done)
```

**The diagnosis matches the injected fault**: firewalld drops http on the mgmt side, catalog INC-006. The catalog's expected path (`curl` local works, remote doesn't → `--get-active-zones` / `--zone=mgmt --list-all`) is the path that was followed. In addition, `curl`'s exit 7 after 0 ms told *reject* apart from *drop* before looking at the firewall, and runtime vs permanent was checked before fixing.

## 9. Timeline

| Time | Event |
|---|---|
| 20:50:05 | Fault injected (blind): `http` removed from `mgmt`, runtime then permanent |
| (none) | **No Zabbix alert** |
| ~20:51 | Round 1: mgmt `000` from Windows and mon01; public `200`; local `200`; nginx/ak-app `active` → path, mgmt side only |
| ~20:52 | Round 2: `curl` exit 7 after 0 ms (rejected); `mgmt` zone services = `ssh` only, runtime and permanent |
| ~20:54 | Fix: `--add-service=http` runtime + permanent; Windows `200` / `200` |
| ~20:55 | `verify.sh` 23/0/0; auditd: two `firewall-cmd` by akadmin; `reveal` = firewall-http |

## 10. Follow-up

- [x] **Done 2026-10-02.** Added the external check: the Zabbix web scenario `ext-http-mgmt` on host web01, run by the server on mon01 every 30 s against `http://192.168.56.11/` and `/app/`, with the trigger **"web01 website unreachable from mon01 (mgmt network)"** (High, `last(/web01/web.test.fail[ext-http-mgmt])<>0`). Re-injected `firewall-http` by name and held it for 2 minutes:

  | Time | Event |
  |---|---|
  | 21:20:57 | Fault re-injected (not blind) |
  | **21:21:01** | **New trigger raised, 4 s after the fault** |
  | 21:23:01 | RESOLVED after the restore (duration 2m) |
  | (none) | "nginx is down on web01" stayed quiet, as it should |

  The same failure that produced **zero alerts** at 20:50 is now caught within one check interval. Evidence: [scenario OK](../screenshots/INC-006-ext-check-ok.png), [problem fired and resolved](../screenshots/INC-006-ext-check-fired.png). Settings: [zabbix/README.md](../../zabbix/README.md#host-web01-external-http-check-inc-006-follow-up-2026-10-02).

  A first attempt at 21:17:40 was restored within seconds, before the 30 s scenario had sampled, and showed nothing. Same lesson as T10: hold a fault for at least two check intervals when testing an alert.

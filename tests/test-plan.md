# Test plan

Every requirement in [docs/requirements.md](../docs/requirements.md) maps to at least one test here. Most tests are automated in [`verify.sh`](verify.sh) (run on mon01 as akadmin), and T10 is manual.

**Negative tests pass when the action is refused.** These are T01, T02, T16 and T19.

Fill in **Result** and **Evidence** with what you actually observed. Evidence is either a file in `docs/screenshots/` or a short output excerpt pasted below the table.

| ID | Phase | Test | Command (run on) | Expected | Result | Evidence |
|---|---|---|---|---|---|---|
| T01 | M1 | Root SSH blocked *(neg)* | `ssh root@web01` (mon01 or Windows) | `Permission denied (publickey)` | | |
| T02 | M1 | Password auth off *(neg)* | `ssh -o PubkeyAuthentication=no akadmin@web01` | `Permission denied (publickey)` | | |
| T03 | M1 | Sudo scope for devs | `sudo -l -U akdev` (web01) | only `systemctl restart nginx` and the two `journalctl -u nginx … --no-pager` lines | | |
| T04 | M2 | SELinux enforcing | `getenforce` (web01) | `Enforcing` | | |
| T05 | M2 | Web + app up (mgmt side) | `curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: web01.lab.local' http://192.168.56.11/app/` (mon01) | `200` for `/` and `/app/` | | |
| T06 | M1 | Public zone scope | `sudo firewall-cmd --zone=public --list-services` (web01) | `http` only | | |
| T07 | M2 | LVM mount persistent | `findmnt /srv/app` after a reboot (web01) | `/dev/mapper/vg_data-lv_app`, `xfs` | | |
| T08 | M2 | cgroup limits applied | `systemctl show ak-app -p MemoryMax -p CPUQuotaPerSecUSec` (web01) | `MemoryMax=134217728`, `CPUQuotaPerSecUSec=250ms` | | |
| T09 | M3 | Agent reachable | `zabbix_get -s 192.168.56.11 -k agent.ping` (mon01) | `1` | | |
| T10 | M3 | **Alerting works (manual)** | `sudo systemctl stop nginx` (web01), watch *Monitoring → Problems*, then `start` | "nginx is down on web01" appears within ~2 min and resolves after start | | screenshot pair |
| T11 | M3 | Backup scheduled + ran | `systemctl list-timers ak-backup.timer`, `ls /var/lib/ak-backup/` (web01) | next run listed; `last_success` present | | |
| T12a | M3 | Backup integrity | `sha256sum -c <newest>.sha256` in `/srv/backups/web01` (mon01, sudo) | `…: OK` | | |
| T12b | M3 | Restore works | extract `etc/ssh/sshd_config` from the newest archive into a temp dir and `cmp` it with the live file; compare `stat -c %C` (web01) | identical content **and** SELinux label | | |
| T13 | E1 | Audit trail | `sudo useradd -M t13 && sudo userdel t13`, then `sudo ausearch -k identity -i -ts recent` (web01) | useradd/userdel events with `auid=akadmin` | | |
| T14 | E1 | Central logs | `logger -t t14 hello` (web01); `sudo grep hello /var/log/remote/web01/t14.log` (mon01) | line present | | |
| T15 | M3 | Health check | `/usr/local/bin/healthcheck.sh; echo $?` (both) | `OK: <host> healthy` and `0` | | |
| T16 | M1 | SSH via public zone refused *(neg)* | from mon01: connect to web01's **10.0.10.x** address on port 22 | connection refused / times out | | |
| T17 | M2 | HTTP via public zone | `curl -s -o /dev/null -w '%{http_code}' http://<web01 10.0.10.x>/` (mon01) | `200` | | |
| T18 | M1 | Time sync | `chronyc tracking` (both) | `Leap status : Normal` | | |
| T19 | M1 | Devs can't stop nginx *(neg)* | `sudo -l -U akdev /usr/bin/systemctl stop nginx; echo $?` (web01) | exit status `1` | | |
| T20 | E1 | Kernel hardening | `sysctl -n kernel.dmesg_restrict` (web01) | `1` | | |

`verify.sh` also prints **T09s** (the `zabbix-server` service is active on mon01).

## Which tests belong to which gate

| Gate | Tests that must pass |
|---|---|
| G1 (end of M1) | T01, T02, T03, T06, T16, T18, T19 |
| G2 (end of M2) | + T04, T05, T07, T08, T17 |
| G3 (end of M3) | + T09, T10, T11, T12a, T12b, T15 |
| G4 = v1.0 | `verify.sh` shows **0 FAIL**; the only SKIPs are T13, T14 and T20; T10 is recorded |
| E1 done | T13, T14 and T20 PASS; `verify.sh` shows 0 FAIL and 0 SKIP |

## Regression smoke set

Run the smoke set after every fix in E2 and after every patch run:

```bash
bash tests/verify.sh          # on mon01
```

Then do T10 by hand whenever the fix touched nginx, firewalld or Zabbix.

## Reboot test (end of M2 and after every patch run)

Reboot web01 (`sudo systemctl reboot`), wait about a minute, then run `verify.sh`. Nothing may need a manual step to come back: `/srv/app` mounts, ak-app and nginx start, and the backup timer is scheduled.

## Evidence

Paste trimmed real output here, one heading per test. Example:

### T08

```text
<paste output of: systemctl show ak-app -p MemoryMax -p CPUQuotaPerSecUSec>
```

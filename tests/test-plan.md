# Test plan

Every requirement in [docs/requirements.md](../docs/requirements.md) maps to at least one test here. Most tests are automated in [`verify.sh`](verify.sh) (run on mon01 as akadmin), and T10 is manual.

**Negative tests pass when the action is refused.** These are T01, T02, T16 and T19.

Fill in **Result** and **Evidence** with what you actually observed. Evidence is either a file in `docs/screenshots/` or a short output excerpt pasted below the table.

| ID | Phase | Test | Command (run on) | Expected | Result | Evidence |
|---|---|---|---|---|---|---|
| T01 | M1 | Root SSH blocked *(neg)* | `ssh root@web01` (mon01 or Windows) | `Permission denied (publickey)` | PASS | verify.sh 2026-10-02 |
| T02 | M1 | Password auth off *(neg)* | `ssh -o PubkeyAuthentication=no akadmin@web01` | `Permission denied (publickey)` | PASS | verify.sh 2026-10-02 |
| T03 | M1 | Sudo scope for devs | `sudo -l -U akdev` (web01) | only `systemctl restart nginx` and the two `journalctl -u nginx … --no-pager` lines | PASS | verify.sh 2026-10-02 |
| T04 | M2 | SELinux enforcing | `getenforce` (web01) | `Enforcing` | PASS | verify.sh 2026-10-02 |
| T05 | M2 | Web + app up (mgmt side) | `curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: web01.lab.local' http://192.168.56.11/app/` (mon01) | `200` for `/` and `/app/` | PASS | verify.sh 2026-10-02 |
| T06 | M1 | Public zone scope | `sudo firewall-cmd --zone=public --list-services` (web01) | `http` only | PASS | verify.sh 2026-10-02 |
| T07 | M2 | LVM mount persistent | `findmnt /srv/app` after a reboot (web01) | `/dev/mapper/vg_data-lv_app`, `xfs` | PASS | verify.sh 2026-10-02 |
| T08 | M2 | cgroup limits applied | `systemctl show ak-app -p MemoryMax -p CPUQuotaPerSecUSec` (web01) | `MemoryMax=134217728`, `CPUQuotaPerSecUSec=250ms` | PASS | verify.sh 2026-10-02 |
| T09 | M3 | Agent reachable | `zabbix_get -s 192.168.56.11 -k agent.ping` (mon01) | `1` | PASS | verify.sh 2026-10-02 |
| T10 | M3 | **Alerting works (manual)** | `sudo systemctl stop nginx` (web01), watch *Monitoring → Problems*, then `start` | "nginx is down on web01" appears within ~2 min and resolves after start | PASS (manual) | [problem](../docs/screenshots/T10-problem.png) / [resolved](../docs/screenshots/T10-resolved.png) |
| T11 | M3 | Backup scheduled + ran | `systemctl list-timers ak-backup.timer`, `ls /var/lib/ak-backup/` (web01) | next run listed; `last_success` present | PASS | verify.sh 2026-10-02 |
| T12a | M3 | Backup integrity | `sha256sum -c <newest>.sha256` in `/srv/backups/web01` (mon01, sudo) | `…: OK` | PASS | verify.sh 2026-10-02 |
| T12b | M3 | Restore works | extract `etc/ssh/sshd_config` from the newest archive into a temp dir and `cmp` it with the live file; compare `stat -c %C` (web01) | identical content **and** SELinux label | PASS | verify.sh 2026-10-02 |
| T13 | E1 | Audit trail | `sudo useradd -M t13 && sudo userdel t13`, then `sudo ausearch -k identity -i -ts recent` (web01) | useradd/userdel events with `auid=akadmin` | SKIP (E1) |  |
| T14 | E1 | Central logs | `logger -t t14 hello` (web01); `sudo grep hello /var/log/remote/web01/t14.log` (mon01) | line present | SKIP (E1) |  |
| T15 | M3 | Health check | `/usr/local/bin/healthcheck.sh; echo $?` (both) | `OK: <host> healthy` and `0` | PASS | verify.sh 2026-10-02 |
| T16 | M1 | SSH via public zone refused *(neg)* | from mon01: connect to web01's **10.0.10.x** address on port 22 | connection refused / times out | PASS | verify.sh 2026-10-02 |
| T17 | M2 | HTTP via public zone | `curl -s -o /dev/null -w '%{http_code}' http://<web01 10.0.10.x>/` (mon01) | `200` | PASS | verify.sh 2026-10-02 |
| T18 | M1 | Time sync | `chronyc tracking` (both) | `Leap status : Normal` | PASS | verify.sh 2026-10-02 |
| T19 | M1 | Devs can't stop nginx *(neg)* | `sudo -l -U akdev /usr/bin/systemctl stop nginx; echo $?` (web01) | exit status `1` | PASS | verify.sh 2026-10-02 |
| T20 | E1 | Kernel hardening | `sysctl -n kernel.dmesg_restrict` (web01) | `1` | SKIP (E1) |  |

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

### v1.0 run of `verify.sh` (2026-10-02, on mon01)

```text
== SUMMARY: 20 PASS, 0 FAIL, 3 SKIP ==
web01: PASS T03 T04 T06 T07 T08 T11 T12b T15 T18 T19 · SKIP T13 T20 (E1)
mon01: PASS T12a T09s T15 T18 · SKIP T14 (E1)
cross-node (from mon01): PASS T01 T02 T05 T09 T16 T17
T11 shows the nightly run worked unattended: last success 2026-10-02 01:34:35, archive web01_2026-10-02_0134.tar.gz (checksum OK on mon01)
```

The first v1.0 run reported 4 FAILs (T01, T02, T16, T17) with `Host key verification failed`. That was a test-script bug: `verify.sh` connected to web01 by IP, but mon01 had stored web01's host key under the name `web01`. Fixed by making `WEB=web01` the default.

Older per-test evidence follows, one heading per test.

### T08 (2026-10-01, web01)

```text
$ systemctl show ak-app -p MemoryMax -p CPUQuotaPerSecUSec -p TasksMax
CPUQuotaPerSecUSec=250ms
MemoryMax=134217728
TasksMax=50
$ cat /sys/fs/cgroup/system.slice/ak-app.service/{memory.max,cpu.max}
134217728
25000 100000
$ systemd-analyze security ak-app | tail -1
→ Overall exposure level for ak-app.service: 8.3 EXPOSED
```

### M2.8 online LVM extend (2026-10-01 18:27, web01)

A 60-second request loop from mon01 (`curl /app/` once per second) ran while the volume was grown. Result: **60 × `200`**, no failed request.

```text
Filesystem                  Size  Used Avail Use% Mounted on
/dev/mapper/vg_data-lv_app  3.0G   90M  2.9G   3% /srv/app        <- before
  Size of logical volume vg_data/lv_app changed from 3.00 GiB (768 extents) to 5.00 GiB (1280 extents).
  Extending file system xfs to 5.00 GiB (5368709120 bytes) on vg_data/lv_app...
data blocks changed from 786432 to 1310720
/dev/mapper/vg_data-lv_app  5.0G  130M  4.9G   3% /srv/app        <- after
  VG      #PV #LV #SN Attr   VSize  VFree
  vg_data   2   1   0 wz--n-  6.99g 1.99g
```

Side finding: after the 2 GB disk was attached, the kernel named it `sdb` and renamed the existing data disk `sdc`. `/srv/app` still mounted, because fstab references the filesystem by UUID.

### T05 / T17 (2026-10-01, from mon01)

```text
T05 mgmt   http://192.168.56.11/      -> 200
T05 mgmt   http://192.168.56.11/app/  -> 200
T17 public http://10.0.10.6/          -> 200
T17 public http://10.0.10.6/app/      -> 200
```

### T09 (2026-10-01, zabbix_get from mon01 → web01)

```text
agent.ping = 1
ak.health.status = 0
ak.mem.avail_pct = 73.3
ak.backup.age = 999999          (before the first backup)
net.tcp.service[http,,80] = 1
zabbix_agent2 runs as system_u:system_r:unconfined_service_t:s0 (no SELinux denials for UserParameters)
```

### T11 / T12a / T12b / T15 / T18 (2026-10-01 22:03–22:05)

First backup: `OK web01_2026-10-01_2203.tar.gz` (journal of ak-backup.service); the timer's next run is tonight at 01:30 (±10 min).

```text
web01  PASS T11  ak-backup.timer enabled/active, last success 2026-10-01 22:03:48
web01  PASS T12b restore of etc/ssh/sshd_config matches live file and label (web01_2026-10-01_2203.tar.gz)
web01  PASS T15  healthcheck: OK: web01 healthy
web01  PASS T18  chrony synchronised
mon01  PASS T12a web01_2026-10-01_2203.tar.gz: OK
mon01  PASS T09s zabbix-server active
mon01  PASS T15  healthcheck: OK: mon01 healthy
mon01  PASS T18  chrony synchronised
after the backup: ak.backup.age = 142 s
```

### T10

2026-10-02: `systemctl stop nginx` on web01, then `systemctl start nginx` about a minute later.

| Event | Time (IST) |
|---|---|
| Problem "nginx is down on web01" (High) raised | 02:02:38 |
| Recovered (status RESOLVED) | 02:03:38 |
| Duration | 1m |

The times are the VMs' clock, which was 9 h 15 min slow at that moment after the laptop slept with the VMs paused. The screenshots were taken at about 11:19 IST wall time. chrony was then set to `makestep 1 -1` and both clocks stepped back to the correct time at 11:29 IST.

Evidence: [T10-problem.png](../docs/screenshots/T10-problem.png), [T10-resolved.png](../docs/screenshots/T10-resolved.png).

An earlier attempt on 2026-10-01 left no problem event. nginx was most likely restarted before the 30-second item polled. Lesson: keep a service down for at least two check intervals when testing an alert.

### Reboot test after M2 (web01 booted 2026-10-01 18:19:59)

```text
T07 mount: /dev/mapper/vg_data-lv_app xfs
services: ak-app=active nginx=active failed-units=0
T04 SELinux: Enforcing   boolean: httpd_can_network_relay --> on
```

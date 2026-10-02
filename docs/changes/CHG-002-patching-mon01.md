# CHG-002: patching mon01 (apt)

| Field | Value |
|---|---|
| Node(s) | mon01 (Ubuntu 24.04.5 LTS) |
| Type | standard (monthly patching) |
| Window | 2026-10-02 20:15–21:00 IST, after CHG-001 is closed |
| Risk | **low**: only one package was pending at planning time. A refreshed list may add more, including Zabbix 7.0.x minor updates from the pinned 7.0 repo. mon01 is the monitoring server, so web01 is unmonitored while mon01 reboots (about 1 minute). |
| Snapshot taken | `baseline-E1` at 19:35 with the VM powered off; nothing has changed since except a boot. It serves as `pre-patch-latest` for this change. |

## 1. Reason

Planning check, 2026-10-02 19:45 (`apt list --upgradable`, lists from 2026-10-01):

| Package | From | To |
|---|---|---|
| `sosreport` | 4.10.2-0ubuntu0~24.04.1 | 4.11.2-0ubuntu0~24.04.1 |

**Finding:** `unattended-upgrades` is enabled (`APT::Periodic::Unattended-Upgrade "1"`), so Ubuntu already installs security updates daily by itself. That explains why so little was pending. The change refreshes the lists, applies whatever is pending (security and regular updates), records what unattended-upgrades did beforehand, and proves the Zabbix stack survives a reboot.

Zabbix stays on the 7.0 LTS branch (repo `zabbix/7.0/ubuntu`), installed version 7.0.31. A move to 8.0 is a separate change (E5).

## 2. Pre-checks

- [ ] `tests/verify.sh` green before starting: **not met.** It's the same 20:13 run as CHG-001 (`18 PASS, 5 FAIL`). On mon01: T15 `load1 9.48` + `chrony not synchronised`, and T18 `chrony not synchronised`. Same deviation as CHG-001: the change went ahead.
- [ ] Zabbix shows no open problems (not recorded)
- [x] Snapshot taken (`baseline-E1`, 19:35)
- [x] Rollback steps below have been read and are possible

## 3. Plan (exact commands)

```bash
# mon01 (second SSH session kept open)
sudo bash ~/ak-infra-lab/tools/patch-mon01.sh CHG-002
#   -> unattended-upgrades log, apt-get update, apt list --upgradable,
#      apt-get -y -o Dpkg::Options::=--force-confold upgrade (keeps our edited configs),
#      sshd -t, ssh/zabbix-server/agent2/mariadb/nginx/rsyslog active, :20514 listening,
#      Zabbix UI answers locally, reboot-required check,
#      then reboots ONLY if every post-check passed
# after ~1 min, on mon01: post-change verification
bash tests/verify.sh
```

Then log in to the Zabbix UI and check that the dashboard loads and no new problems are open.

## 4. Rollback plan

**Triggers:** a Zabbix component doesn't come back, the UI doesn't load, `verify.sh` shows a FAIL that isn't fixed within 15 min, or mon01 doesn't boot.

1. **First choice:** reinstall the previous version of the offending package (`apt-get install <pkg>=<old version>`, with the old version from `/var/log/apt/history.log`), then restart the service. apt has no transaction undo.
2. **Fallback:** power off and restore snapshot `baseline-E1`. Backups that web01 sent to mon01 after 19:35 would be lost with it, but web01 sends a new one every night.

## 5. Execution log (real output, trimmed)

From `/home/akadmin/CHG-002-mon01.log` (written by `tools/patch-mon01.sh`):

```text
== CHG-002 start on mon01.lab.local - before (20:15:35)
6.8.0-146-generic
zabbix-server-mysql 1:7.0.31-1+ubuntu24.04   mariadb-server 1:10.11.14-0ubuntu0.24.04.1   nginx 1.24.0-2ubuntu7.18

== what unattended-upgrades already did (last 10 lines)
2026-10-01 06:04:29 INFO Packages that will be upgraded: curl ... libexpat1 ... libssl3t64 libxml2 openssl
                         perl ... polkitd ... python3.12 ... rsyslog sudo
2026-10-01 06:04:43 INFO All upgrades installed
2026-10-02 11:25:43 INFO Allowed origins are: o=Ubuntu,a=noble, o=Ubuntu,a=noble-security, ...
2026-10-02 11:25:45 INFO No packages found that can be upgraded unattended and no pending auto-removals

== apt-get update + pending (20:15:35)
Fetched 8,856 kB in 35s (257 kB/s)
libxpm4/noble-updates,noble-security 1:3.5.17-1ubuntu0.24.04.2 amd64 [upgradable from: 1:3.5.17-1ubuntu0.24.04.1]
sosreport/noble-updates 4.11.2-0ubuntu0~24.04.1 amd64 [upgradable from: 4.10.2-0ubuntu0~24.04.1]

== apply: apt-get upgrade (keep local config files) (20:23:28)   <- clock stepped +431.8 s at 20:23:24 by chrony
The following upgrades have been deferred due to phasing:
  sosreport
The following packages will be upgraded:
  libxpm4
1 upgraded, 0 newly installed, 0 to remove and 1 not upgraded.
Restarting services...
 systemctl restart php8.3-fpm.service
2026-10-02 20:23:30 upgrade libxpm4:amd64 1:3.5.17-1ubuntu0.24.04.1 1:3.5.17-1ubuntu0.24.04.2

== post-checks before reboot (20:23:32)
sshd -t: config OK
ssh active · zabbix-server active · zabbix-agent2 active · mariadb active · nginx active · rsyslog active
rsyslog listening on 20514
Zabbix UI / -> 200

== reboot needed? (20:23:32)
no reboot-required flag (rebooting anyway, as planned, to prove the boot)
== all post-checks OK - rebooting in 10 s (planned in CHG-002)
The system will reboot now!   (20:23:42)
```

Notes:
- **`sosreport` was held back by Ubuntu's phased updates.** Ubuntu releases some updates to a growing share of machines over several days, and this one hasn't reached mon01's share yet. That's expected behaviour, not an error. It will arrive in a later run.
- **`libxpm4` (noble-security)** only appeared after `apt-get update`. The planning check had used day-old lists, which is why it showed only sosreport.
- **The timestamps jump by 8 minutes** between `apt-get update` and `apply`. That isn't time spent: chrony stepped the clock by 431.8 s at 20:23:24, the moment it first reached an NTP server since the 19:36 boot.

## 6. Post-checks

- [x] `/var/run/reboot-required`: not set. We rebooted anyway, as planned. After the boot chrony found a source within 6 s and corrected a 12.0 s RTC offset at 20:24:02.
- [x] `tests/verify.sh` summary (about 20:25): **`22 PASS, 1 FAIL, 0 SKIP`**. All mon01 checks PASS: T12a, T14 (fresh token from web01 arrived), T09s, T15 `OK: mon01 healthy`, T18. The one FAIL is web01's T13 test-script bug (see CHG-001).
- [ ] Zabbix: UI loads, no new problems after 10 min (not recorded)
- [x] Versions after the change: kernel `6.8.0-146-generic` (unchanged), `zabbix-server-mysql 1:7.0.31`, `mariadb-server 1:10.11.14`, `nginx 1.24.0-2ubuntu7.18`, `libxpm4 1:3.5.17-1ubuntu0.24.04.2`

## 7. Result

**Successful.** One security update was applied, one update was deferred by phasing, and the Zabbix stack and log receiver survived the upgrade and a reboot. The change took 8 min of wall time, most of it `apt-get update` (35 s of fetching) plus the clock step; no rollback needed.

Follow-up: unattended-upgrades already patches mon01 daily from `noble-security`. Monthly changes like this one catch the non-security updates and prove the reboot, and they're the place to review what unattended-upgrades did.

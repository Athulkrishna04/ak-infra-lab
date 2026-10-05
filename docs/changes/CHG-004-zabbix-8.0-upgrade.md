# CHG-004: Zabbix 7.0 LTS → 8.0 upgrade on mon01 (E5): **DEFERRED, no-go**

| Field | Value |
|---|---|
| Node(s) | mon01 (Zabbix server 7.0.31 + frontend + MariaDB 10.11), web01 (agent2 7.0.31) |
| Type | normal (major version upgrade, database schema migration) |
| Status | **No-go (2026-10-05).** 8.0 is not generally available; re-assess when the `release` channel carries 8.0 packages |
| Risk | **high**: a one-way database schema upgrade of the monitoring server; rollback is restore-only |

## 1. Go/no-go check (2026-10-05, read directly from repo.zabbix.com)

| Channel | Ubuntu 24.04 (noble) content |
|---|---|
| `zabbix/8.0/release/` | only `zabbix-release` (repo definition package, versions `8.0-0.1` … `8.0-0.4`); `dists/noble/main` has **`binary-all` only, no server/frontend/agent builds** |
| `zabbix/8.0/unstable/` | `zabbix-server-mysql` **`8.0.0~beta1`, `8.0.0~beta2`, `8.0.0~rc1`** |
| `zabbix/7.0/` (current) | `zabbix-server-mysql 7.0.31` (LTS, supported) |

**Decision: no-go.** The newest 8.0 build is a release candidate in the `unstable` channel. Upgrading a working monitoring server to it would mean:
- running a pre-release whose database schema may still change before 8.0.0;
- no supported upgrade path from an RC to the final release;
- trading an LTS with fixes for a build without them.

The lab's monitoring has no requirement that 7.0 LTS doesn't meet. The build guide's own precondition for E5 is "once 8.0 is GA".

## 2. Criteria to re-open the change

- [ ] `zabbix/8.0/release/ubuntu/dists/noble/main/binary-amd64` contains `zabbix-server-mysql 8.0.x` (not `~rc` / `~beta`), and the same for Rocky 10 (`zabbix-agent2`)
- [ ] The 8.0 upgrade notes have been read for: the minimum MariaDB and PHP versions (mon01 has MariaDB 10.11.14, PHP 8.3), removed or renamed items/macros used by the AK template, and the supported agent versions
- [ ] Ideally 8.0.1 or later (let early fixes land first)

## 3. Plan (for when the criteria are met)

```bash
# 0) Pre-checks: verify.sh 24/0/0, no open Zabbix problems, chrony synced on both nodes
# 1) Rollback points
mon01$ sudo systemctl stop zabbix-server
mon01$ sudo mysqldump --single-transaction --routines zabbix | gzip > /srv/backups/zabbix-7.0.31-$(date +%F).sql.gz
mon01$ sudo tar czf /srv/backups/zabbix-conf-7.0.31.tgz /etc/zabbix   # includes nginx.conf, php-fpm.conf, web/zabbix.conf.php, server + agent configs
#    copy both files OFF mon01 (rehearsal finding 5), e.g. scp to Windows, then power off mon01 and take an offline VirtualBox snapshot pre-zabbix8
# 2) Switch the repo and upgrade (packages from the 8.0 release channel only)
mon01$ wget https://repo.zabbix.com/zabbix/8.0/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_8.0+ubuntu24.04_all.deb
mon01$ sudo dpkg -i zabbix-release_latest_8.0+ubuntu24.04_all.deb && sudo apt-get update
mon01$ sudo apt-get install --only-upgrade zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2 zabbix-get
# 2b) Frontend moved to /usr/share/zabbix/ui (rehearsal finding 1): adopt the new nginx.conf
mon01$ sudo bash ~/ak-infra-lab/tools/zbx8-nginx-merge.sh      # merges .dpkg-dist + our listen/server_name, nginx -t, reload
# 3) The server upgrades the DB schema on first start: watch it finish
mon01$ sudo systemctl start zabbix-server
mon01$ sudo tail -f /var/log/zabbix/zabbix_server.log      # "database upgrade fully completed"
# 4) Verify: UI loads, web01 + Zabbix server hosts green, AK Linux Lab items have fresh data,
#    ext-http-mgmt web scenario OK, T10 by hand, verify.sh 24/0/0
# 5) web01's agent: stays 7.0 if 8.0's compatibility notes allow it; otherwise switch the
#    zabbix_agent role's repo URL to 8.0, run ansible/run.sh site.yml, and expect changed>0 once, then 0
```

## 4. Rollback plan

**Triggers:** the schema upgrade fails or doesn't complete, the UI doesn't load, or items stop collecting and that isn't fixed within 30 min.

1. Stop zabbix-server, reinstall the 7.0 repo package and the `7.0.31` packages, restore the `mysqldump` into an emptied `zabbix` database, restore `/etc/zabbix`, and start. **A downgrade without the dump is impossible**, because the 8.0 schema change is one-way.
2. Fallback: power off and restore the snapshot `pre-zabbix8`.

## 5. Result

**Deferred** on 2026-10-05: no-go, because the precondition (8.0 GA) isn't met. Monitoring stays on 7.0.31 LTS. Re-check the `release` channel monthly as part of the regular patching change.

## 6. Dress rehearsal (2026-10-05, 8.0.0rc1, rolled back)

The plan above was rehearsed end-to-end against the pre-release, **behind an offline snapshot** (`pre-zabbix8`), using `tools/zbx8-rehearsal.sh` and `tools/zbx8-nginx-merge.sh`. The log was copied off mon01 before the rollback. This was a rehearsal, not a production change: mon01 was rolled back afterwards.

### What happened

| Time | Step | Evidence |
|---|---|---|
| 20:55:57 | Before | `zabbix_server 7.0.31`, `dbversion 7000000 / 7000030`, latest web01 value 20:55:54 |
| 20:55:57 | Backup | `mysqldump` **5.9 MB, 203 tables**; `/etc/zabbix` 17 KB |
| 20:55:59 | Repo | `zabbix-release 1:8.0-0.4` installed; apt reads `zabbix/8.0/unstable/ubuntu noble` (the official 8.0 package enables that channel) |
| 20:56:07 | Upgrade | `zabbix-server-mysql`, `-frontend-php`, `-nginx-conf`, `-sql-scripts`, `-agent2`, `-get` → **`2:8.0.0~rc1-1`** |
| 20:56:40 | Schema migration | `current database version 07000000/07000030` → `starting automatic database upgrade` → **`database upgrade fully completed` at 20:56:49 (9 s)**; `dbversion 7050195` |
| 20:56:51 | Server and agents | `zabbix_server 8.0.0rc1`; web01's **7.0.31 agent works with the 8.0 server** (`agent.ping = 1`); fresh web01 data at 20:58:51 (same second as the check) |
| 20:56:51 | **Frontend: HTTP 404** | finding 1 below |
| 21:13 | Merged nginx config | `nginx -t` OK; then `/` = **200** (`<title>ak-infra-lab: Zabbix</title>`), API `apiinfo.version` = **`8.0.0`**, reachable from the mgmt network; [8.0 login page](../screenshots/CHG-004-rehearsal-zabbix8-login.png) |
| 21:28:25 → 21:28:39 | **Rollback** (power off, restore `pre-zabbix8`, start) | 14 s; afterwards `zabbix_server 7.0.31`, all packages `7.0.31`, `zabbix-release 7.0-5`, original `nginx.conf`, API `7.0.31`, UI 200 |

### Findings (to fold into the real change)

1. **The 8.0 frontend moved to `/usr/share/zabbix/ui/`.** Because the upgrade keeps edited config files (`--force-confold`), our M3-edited `/etc/zabbix/nginx.conf` still pointed at `/usr/share/zabbix`, so the UI returned **404**. dpkg saved the new file as `nginx.conf.dpkg-dist`. Zabbix even left a hint page behind (`zabbix-update-msg-nginx.php`). **Plan step added:** merge `nginx.conf.dpkg-dist` (new paths in `root` and the three `fastcgi_param` lines, plus `client_max_body_size 5m`) and re-apply our two edits (`listen 80`, `server_name`). Exactly 2 lines differ after the merge.
2. **Test after a graceful reload with a short delay.** Straight after `systemctl reload nginx`, the old workers still served the old config (404); seconds later it was 200. Verification steps now wait or retry.
3. **`zabbix_server.conf.dpkg-dist`**: the only non-comment difference from ours is `DBPassword` (masked). No new mandatory server settings to merge.
4. **The 7.0 agent on web01 keeps working** with the 8.0 server, so the agent upgrade can be a separate, later step.
5. **Keep the DB dump off the box.** The rehearsal's `mysqldump` lived on mon01 and disappeared with the snapshot rollback. **Plan step added:** copy the dump to Windows or web01 *before* the upgrade, so rollback path 1 still exists if the snapshot can't be used.
6. **The web login failed** ("incorrect user name or password or account is temporarily blocked") after several attempts. Not investigated, because the rehearsal was rolled back. In the real change, test the login **once** right after the upgrade; if it fails, check the 8.0 release notes on authentication and the `users` table's `attempt_failed` / `attempt_clock` (a blocked account), before trying more passwords.
7. **The rollback by snapshot is fast and exact** (14 s, everything back to 7.0.31). That's what makes a one-way schema upgrade acceptable in this lab.

**After the rollback** (spot checks, ~21:35): mon01 `7.0.31`, healthcheck OK, UI 200, web01 `agent.ping = 1`, web01 `/` and `/app/` 200, NFS share readable, 0 failed units on web01, chrony `Normal`. The temporary snapshot `pre-zabbix8` was then deleted with mon01 powered off, leaving mon01's usual three (`clean-install`, `baseline-M3`, `baseline-E1`).

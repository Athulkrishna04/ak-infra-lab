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
#    then power off mon01 and take an offline VirtualBox snapshot pre-zabbix8
# 2) Switch the repo and upgrade (packages from the 8.0 release channel only)
mon01$ wget https://repo.zabbix.com/zabbix/8.0/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_8.0+ubuntu24.04_all.deb
mon01$ sudo dpkg -i zabbix-release_latest_8.0+ubuntu24.04_all.deb && sudo apt-get update
mon01$ sudo apt-get install --only-upgrade zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent2 zabbix-get
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

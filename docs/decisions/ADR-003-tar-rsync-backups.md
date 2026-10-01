# ADR-003: Nightly tar archive pushed with rsync over SSH, run by a systemd timer

**Status:** accepted · **Date:** 2026-09-29

## Context

web01's `/etc`, `/srv/www` and `/srv/app` must be recoverable (RPO ≤ 25 h). The receiver on mon01 must not run as root. On RHEL a restored file is only correct if its owner, mode, ACLs and **SELinux label** come back too.

## Decision

- **Format:** `tar --acls --xattrs --selinux -czpf` plus a `.sha256` file. A plain rsync mirror to a non-root receiver would lose ownership and SELinux labels, while the archive keeps them.
- **Transport:** `rsync -a` over SSH with a dedicated key (`/root/.ssh/backup_ed25519`) to the user **`akbackup`** on mon01. Ubuntu already has a `backup` system account with a nologin shell, so that name can't be used. In E1 the key is locked to `rrsync -wo` (write-only, one directory).
- **Schedule:** `ak-backup.timer`, `OnCalendar=01:30`, `RandomizedDelaySec=10m`, `Persistent=true`. The timer (instead of cron) runs a missed backup at the next boot, which matters for a laptop lab, and every run is logged in the journal.
- **Safety:** the archive holds `/etc/shadow`, so it's created under `umask 077`. The `last_success` timestamp stays 0644 so the Zabbix agent can read it.
- **Retention:** 3 days locally on web01 and 14 days on mon01.
- **Proof:** a backup only counts once a restore has been tested (T12b), and a stale backup raises a Zabbix alert.

## Consequences

- There's no dedup or encryption at rest; restic or borg would be the upgrade path.
- A restore is manual and follows [runbooks/restore-from-backup.md](../runbooks/restore-from-backup.md).

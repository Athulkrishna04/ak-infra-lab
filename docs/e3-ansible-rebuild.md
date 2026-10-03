# E3: Ansible rebuild (evidence)

**Result (2026-10-03):** web01 was restored to its M0 `clean-install` snapshot (fresh Rocky 10.2, two **new empty** data disks) and rebuilt by `ansible-playbook site.yml` from mon01. On the rebuilt node `tests/verify.sh` shows **23 PASS, 0 FAIL, 0 SKIP**, and a second run reports **`changed=0`** on both hosts.

## What the playbook manages

| Role | Hosts | From the build | Highlights |
|---|---|---|---|
| `common` | both | M0–M3 | time zone, base packages incl. SELinux Python libs, chrony `makestep 1 -1`, ops/devs groups, public SSH keys from `configs/keys/`, `/etc/hosts`, sudoers (`visudo -cf` before install), healthcheck units, kdump off + its failed state cleared |
| `hardening` | both | M1, E1 | sshd drop-ins (`sshd -t` before **reload**), banner, `login.defs` aging, sysctl, audit rules (`augenrules`, never restart auditd), firewalld mgmt/public in the safe order (web01), ufw (mon01) |
| `logging` | both | E1.3 | SELinux port label, forwarder (web01), receiver + logrotate (mon01) |
| `web` | web01 | M2 | `vg_data` on both data disks, `lv_app` 5 GiB XFS mounted **by UUID**, akapp + cgroup unit, ACLs, `sefcontext` + `restorecon`, `httpd_can_network_relay`, nginx (`nginx -t` before reload) |
| `zabbix_agent` | web01 | M3 | 7.0 repo (installed only if missing), agent2, `Server`/`Hostname`, AK UserParameters |
| `backup` | web01 (+ mon01 via `delegate_to`) | M3, E1.6 | script + timer, key **generated on web01, never in the repo** (`creates:`), mon01 host key in root's known_hosts, akbackup + `authorized_key` locked to `rrsync -wo`, crontab compared before install, first backup if none |

Passwords: akadmin's sudo password differs per VM, so `host_vars/<host>.yml` point into an **ansible-vault file outside the repo** (`~/.ak-become.vault.yml` on mon01). `run.sh` loads it; `make-vault.sh` builds it from passwords that `sudo -v` actually accepts on each host. Nothing secret is committed (`*.vault.yml` is gitignored).

## Gates

| Step | mon01 | web01 |
|---|---|---|
| E3.2 first `--check --diff` on the live v1.1 fleet | changed=4 | changed=1 |
| E3.2 apply #1 (after fixing the roles) | changed=1 (ufw rules rewritten into the module's form) | changed=0 |
| E3.2 apply #2 | **changed=0** | **changed=0** |
| E3.4 rebuild from `clean-install`, attempt 1 | changed=0 | changed=26, **failed=1** (role bug 3 below) |
| E3.4 rebuild, attempt 2 (after the fix) | changed=0 | ok=72, changed=1, failed=0 |
| `reload-services.yml` (one-time recovery, bug 4) | – | changed=3 |
| **`verify.sh` on the rebuilt web01** | **23 PASS / 0 FAIL / 0 SKIP** | |
| **Second run on the rebuilt node** | **changed=0** | **changed=0** |

## Role bugs the gate found (all fixed in the roles, never by hand on the VM)

1. **Duplicate `/etc/hosts` entries:** `lineinfile` with a plain `line:` would have added a second entry per host, because the hand-written lines used different spacing. Fixed: match by IP with `regexp`. Found by the first `--check --diff`.
2. **Tasks for things a node doesn't use:** `acl` on mon01, and mon01's own key in its own `authorized_keys`. Scoped to web nodes. Found by the first `--check --diff`.
3. **Package order:** `logging`'s `seport` ran before `web` installed the SELinux Python bindings (`ModuleNotFoundError: No module named 'seobject'`). Invisible on the old web01, where the package already existed. Fixed: install them in `common`.
4. **Dropped handlers:** attempt 1 changed the sshd, audit and rsyslog files, then failed. Ansible drops pending handlers on failure, and the next runs saw the files already in place, so nothing re-notified them. The configs were on disk but never loaded: `verify.sh` failed T02 (password auth still offered), skipped T13 (no audit rules loaded) and failed T14 (no forwarding). Fixed: `force_handlers = True` in `ansible.cfg`; `reload-services.yml` ran the dropped handlers once.
5. **Not idempotent until a reboot:** the crashkernel task tested `/proc/cmdline`, which only changes at the next boot, so it re-ran `grubby` on every run. Fixed: check `grubby --info=ALL` instead.
6. **Kdump's failed state:** on a fresh install kdump has already failed at boot. Disabling it doesn't clear the state, so the health check would report it. Fixed: `systemctl reset-failed` after disabling.

## Operational lessons

- **A base image is only useful if its credentials are known.** The `clean-install` snapshot predates every password change, and akadmin's M0 password wasn't recorded, so it had to be reset from the console (`init=/bin/bash`, as in [INC-009](incidents/INC-009-root-password-reset.md)). The vault now holds the working passwords.
- **Editing the vault by hand failed three times** (placeholder text, missing space after `web01:`, a value that wasn't the real password). A diagnostic that tested the value with plain `sudo -S` said *rejected* for both hosts, and was wrongly dismissed at first, because mon01 seemed to work. In fact mon01's Ansible runs locally on the admin's terminal, and Ubuntu's sudo caches credentials per terminal for 15 minutes. `make-vault.sh` now only accepts what sudo accepts.
- **Ansible ignores `ansible.cfg` in a world-writable directory.** The repo copy on mon01 had `o+w` bits from the Windows copy; fixed with `chmod -R go-w`.

## Known gaps (not automated)

- **mon01's Zabbix server, frontend and MariaDB** (installed with `tools/zabbix-db-setup.sh` in M3), the Zabbix host/template/web-scenario configuration, and mon01's netplan are not in Ansible. The E3 gate covers rebuilding **web01**.
- **Patching is not part of the playbook**, by design: mixing "apply updates" into a converge would break `changed=0`. The rebuilt web01 came up with the `clean-install` package versions (49 security notices pending, 2 Critical) and was patched in [CHG-003](changes/CHG-003-patch-rebuilt-web01.md): 0 advisories left, `verify.sh` 23/0/0, and the playbook still `changed=0` afterwards.
- **The previous web01's backup key** is still authorized on mon01, next to the new one (the role adds keys, it doesn't remove old ones). It's locked to `rrsync -wo /srv/backups/web01` either way; remove the stale line by hand or with `exclusive: true` once only Ansible manages that file.
- **Users' passwords** aren't managed. The vault holds them only for `become`.

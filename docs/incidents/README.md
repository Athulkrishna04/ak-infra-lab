# Incident catalog

INC-001 isn't injected. It happens on its own during M2, when nginx first proxies to ak-app under SELinux. Write it up from the real output as it happens.

INC-002 to INC-009 are injected in E2, one at a time, each followed by a full write-up ([template](TEMPLATE.md)). Six of them can be injected **blind** with [`tools/ak-chaos.sh`](../../tools/ak-chaos.sh). It shows you only the ticket text, so you diagnose from the symptom instead of from memory. The two boot-level faults are injected by hand.

**Protocol for every fault:**
1. Take a snapshot `pre-patch-latest`, or revert to it for a clean start.
2. Inject exactly one fault.
3. Write **Symptom** first.
4. Diagnose, fix and verify: `verify.sh` must pass and T10 must be done if nginx was involved.
5. Only then run `ak-chaos.sh reveal` and compare it with your root cause.
6. Commit the write-up.

Don't read the "Expected path" column before you've done the fault. It's here so the catalog stays complete and reproducible.

| ID | Layer | Fault | Inject | Ticket / symptom | Restore | Expected diagnostic path | Runbook |
|---|---|---|---|---|---|---|---|
| INC-001 | MAC (SELinux) | nginx can't connect to ak-app | *natural, M2* | `/app/` returns **502**; `/` works | the boolean suggested by `audit2why` | nginx error log "Permission denied while connecting to upstream" → `ausearch -m AVC \| audit2why` → boolean | [selinux-denial](../runbooks/selinux-denial.md) |
| INC-002 | Storage | Filesystem full | `ak-chaos.sh inject disk-full` | Zabbix "Space is low" on /srv/app; healthcheck CRIT | `ak-chaos.sh restore` | `df -h` → `du -xh --max-depth=1` → a hidden big file → remove, or `lvextend -r` | [disk-full](../runbooks/disk-full.md) |
| INC-003 | Storage / process | Deleted-but-open file | `ak-chaos.sh inject deleted-open-log` | Same ticket as INC-002, but `du` doesn't find the space | `ak-chaos.sh restore` | `df` vs `du` disagree → `lsof +L1` → PID → `systemctl status <PID>` → stop the unit | [disk-full](../runbooks/disk-full.md) |
| INC-004 | Service | nginx config error | `ak-chaos.sh inject nginx-config` | Site down; Zabbix "nginx is down" | `ak-chaos.sh restore` | `systemctl status nginx` → `journalctl -u nginx` → `nginx -t` names the line | [service-down](../runbooks/service-down.md) |
| INC-005 | MAC (SELinux) | Wrong file context | `ak-chaos.sh inject selinux-context` | `/` returns **403**; `/app/` works | `ak-chaos.sh restore` | `ls -l` looks fine → `ls -Z` shows `user_tmp_t` → `ausearch` → `restorecon` | [selinux-denial](../runbooks/selinux-denial.md) |
| INC-006 | Network | firewalld drops http on the mgmt side | `ak-chaos.sh inject firewall-http` | Site times out from Windows and mon01; **Zabbix nginx check stays green** (it runs locally) | `ak-chaos.sh restore` | `curl` local works, remote doesn't → `firewall-cmd --get-active-zones` / `--zone=mgmt --list-all` | [service-down](../runbooks/service-down.md) |
| INC-007 | Identity | Account expired | `ak-chaos.sh inject account-expired` | akdev can't log in (key auth fails) | `ak-chaos.sh restore` | `journalctl -u sshd` / `/var/log/secure` "account has expired" → `chage -l akdev` | [ssh-lockout](../runbooks/ssh-lockout.md) |
| INC-008 | Boot | fstab typo → emergency mode | By hand: snapshot, then change one character of the `/srv/app` UUID in `/etc/fstab`, **don't** run `mount -a`, then `sudo systemctl reboot` | Host down in Zabbix; the console shows emergency mode | Fix fstab from the emergency shell | root password → `systemctl --failed` → `journalctl -xb` → `blkid` vs fstab | [emergency-mode-fstab](../runbooks/emergency-mode-fstab.md) |
| INC-009 | Boot / auth | Forgotten root password | By hand: set root's password to a random string you don't keep (`openssl rand -base64 12 \| sudo passwd --stdin root`) | You can't answer the emergency-mode prompt | Reset via `rd.break` | GRUB `e` → `rd.break` → `chroot /sysroot` → `passwd` → `/.autorelabel` | [root-password-reset](../runbooks/root-password-reset.md) |

**Why INC-006 matters:** it shows that monitoring from inside the box isn't the user's view. The fix and its prevention could be an external check from mon01, a Zabbix `net.tcp.service` *simple check* run by the server itself. That makes a good E2 follow-up.

## Index (fill in as you write them)

| ID | Title | Date | Time to resolve | Blind? |
|---|---|---|---|---|
| [INC-001](INC-001-nginx-502-selinux.md) | nginx returns 502 for /app/ under SELinux | 2026-10-01 | ~10 min | natural |
| [INC-002](INC-002-disk-full-hidden-tempfile.md) | /srv/app at 95%: hidden 4.6 GB temp file (`fallocate`) | 2026-10-02 | ~3 min | yes (ak-chaos random) |
| [INC-004](INC-004-nginx-config-missing-semicolon.md) | Website down: nginx won't start after a config edit (missing `;`) | 2026-10-02 | ~6 min | yes (ak-chaos random) |

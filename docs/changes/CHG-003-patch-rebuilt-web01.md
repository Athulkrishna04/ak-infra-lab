# CHG-003: security patching of the Ansible-rebuilt web01

| Field | Value |
|---|---|
| Node(s) | web01 (Rocky Linux 10.2, rebuilt from the M0 `clean-install` image in E3.4) |
| Type | normal (catch-up after a rebuild; far larger than a monthly run) |
| Window | 2026-10-03, about 13:00–13:30 IST |
| Risk | **medium**: 183 package updates including kernel, glibc, systemd, sudo and openssh; a reboot is certain (new kernel) |
| Snapshot taken | no new snapshot. Rollback is the **rebuild itself**: restore `clean-install` and run `ansible-playbook site.yml` (proven in E3.4), or `dnf history undo` |

## 1. Reason

The rebuild restored web01 from the M0 image, so it runs the package versions of the original install (openssh `9.9p1-23`, kernel `6.12.0-211.16.1`). Pending at planning time (`dnf updateinfo summary`, 2026-10-03 ~12:58):

| Severity | Security notices |
|---|---|
| Critical | 2 (e.g. RLSA-2026:22963, RLSA-2026:25191) |
| Important | 33 |
| Moderate | 13 |
| Low | 1 |
| **Total** | **49** (183 package updates), plus 1 bugfix notice |

Key packages: `kernel` → 6.12.0-211.61.1.el10_2, `glibc` → 2.39-128.el10_2, `openssh` → 9.9p1-28.el10_2.rocky.0.1, `sudo` → 1.9.17-10.p2.el10_2.6, `systemd` → 257-23.el10_2.2.rocky.0.1.

This also explains why "apply updates" isn't a task in the Ansible roles: a converge must report `changed=0` on a second run, and patching is a change with its own record and window.

## 2. Pre-checks

- [x] `tests/verify.sh` green: 23 PASS / 0 FAIL / 0 SKIP on the rebuilt node (E3.4, ~12:55); second playbook run `changed=0`
- [x] chrony synchronised (T18 PASS)
- [x] Rollback possible: the rebuild path is proven; old package versions remain in baseos for `dnf history undo`

## 3. Plan (exact commands)

```bash
# web01 (tools/patch-web01.sh copied to web01 first: the rebuilt node has no repo copy)
sudo bash ~/ak-infra-lab/tools/patch-web01.sh CHG-003
#   -> dnf upgrade --security -y, dnf history info last, sshd -t, services + local /app/,
#      needs-restarting, then reboots ONLY if every post-check passed
# after ~2 min, on mon01:
bash tests/verify.sh
cd ansible && ./run.sh site.yml          # the playbook must still report changed=0 after patching
```

## 4. Rollback plan

**Triggers:** web01 doesn't boot, a service doesn't come back, or `verify.sh` / the playbook shows a regression not fixed within 15 min.

1. Boot the previous kernel from the GRUB menu if only the new kernel misbehaves.
2. `sudo dnf history undo <ID>` (ID from the log).
3. Rebuild: restore `clean-install`, run `site.yml` (E3.4), then patch again in smaller steps.

## 5. Execution log (from `/home/akadmin/CHG-003-web01.log`, trimmed)

```text
== transaction record (dnf history info last)
Transaction ID : 8
Begin time     : Sat 03 Oct 2026 01:12:16 PM IST
End time       : Sat 03 Oct 2026 01:15:21 PM IST (185 seconds)
Return-Code    : Success

== post-checks before reboot (13:15:22)
sshd -t: config OK
sshd active · nginx active · ak-app active · zabbix-agent2 active · rsyslog active · auditd active
local /app/ -> 200
kernel-core-6.12.0-211.16.1.el10_2.0.1.x86_64
kernel-core-6.12.0-211.61.1.el10_2.x86_64
openssh-server-9.9p1-28.el10_2.rocky.0.1.x86_64

== reboot needed? (13:15:22)
Core libraries or services have been updated since boot-up:
  * dbus-broker  * kernel  * kernel-core  * microcode_ctl
Reboot is required to fully utilize these updates.
needs-restarting -r exit=1 (1 = reboot required)
services using old libraries: NetworkManager ak-app chronyd dbus-broker firewalld systemd-udevd user@1000

== all post-checks OK - rebooting in 10 s (planned in CHG-003) (13:15:24)
```

(Transaction ID 8 again, as in CHG-001: it's a new rpmdb on the rebuilt VM, so the counter restarted.)

## 6. Post-checks

- [x] Reboot required (new kernel, `needs-restarting -r` exit 1): handled by the planned reboot. Running kernel afterwards **`6.12.0-211.61.1.el10_2`**; `systemctl is-system-running` → `running`.
- [x] **0 security advisories pending** (`dnf updateinfo list --security` → 0 lines, down from 49).
- [x] Versions: `openssh-server-9.9p1-28.el10_2.rocky.0.1`, `sudo-1.9.17-10.p2.el10_2.6`. `glibc` (2.39-121) and `systemd` (257-23 …2.1) are at their latest **security** level; newer bugfix builds stay for a regular `dnf upgrade` change.
- [x] `tests/verify.sh` (~13:22): **23 PASS / 0 FAIL / 0 SKIP**.
- [x] `ansible/run.sh site.yml` after patching: **mon01 changed=0, web01 changed=0**. The configuration survived 183 package updates and a kernel change.

## 7. Result

**Successful.** 49 security notices (2 Critical, 33 Important) applied in 185 s, plus one planned reboot onto the new kernel. Tests green, configuration unchanged. No rollback needed. This closes the "rebuilt node is unpatched" gap from [E3](../e3-ansible-rebuild.md).

Lesson: a rebuild from an old base image re-opens every vulnerability fixed since that image was made. Rebuild, then patch, then verify, every time; or refresh the base image periodically.

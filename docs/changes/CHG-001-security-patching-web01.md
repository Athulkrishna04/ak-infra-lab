# CHG-001: security patching on web01

| Field | Value |
|---|---|
| Node(s) | web01 (Rocky Linux 10.2) |
| Type | standard (monthly security patching, security advisories only) |
| Window | 2026-10-02 20:00–20:45 IST |
| Risk | **medium**: one of the packages is `openssh-server`, the service every admin session depends on. Existing sessions survive an sshd restart, and the hardening drop-ins in `sshd_config.d/` are not package-owned, so they're kept. |
| Snapshot taken | `baseline-E1` at 19:35 with the VM powered off; nothing has changed since except a boot. It serves as `pre-patch-latest` for this change. |

## 1. Reason

2 security advisories are pending (checked 2026-10-02 19:45 with `dnf updateinfo list --security`):

| Advisory | Severity | Packages |
|---|---|---|
| RLSA-2026:74001 | Important | `expat` → 2.7.3-1.el10_2.5 (from 2.7.3-1.el10_2.3) |
| RLSA-2026:73954 | Moderate | `openssh`, `openssh-clients`, `openssh-server` → 9.9p1-28.el10_2.rocky.0.1 (from 9.9p1-27) |

These 4 packages are also the only updates of any kind pending (`dnf check-update`), so a security-only run brings web01 fully up to date. No kernel update is pending.

## 2. Pre-checks

- [ ] `tests/verify.sh` green before starting: **not met.** The run at about 20:13 showed `18 PASS, 5 FAIL`:
  - T15 and T18 on **both** nodes: `chrony not synchronised` (plus `load1 9.48` on mon01). The clocks had lost NTP sync after the 19:36 boot. mon01's clock was **431.8 s** off and was stepped by chrony at 20:23:24, once it could reach a server again (chrony journal).
  - T13: a test-script bug (`useradd -K CREATE_MAIL_SPOOL=no` isn't valid on Rocky 10), not a system fault.
  - **Deviation:** the change went ahead anyway. None of these failures involve the packages being changed, and the planned reboot was expected to clear the clock state, which it did. The strict rule is still "red pre-check = don't start", and it should have been followed: fix chrony first, re-run, then patch.
- [ ] Zabbix shows no open problems for web01 (not recorded)
- [x] Snapshot taken (`baseline-E1`, 19:35)
- [x] Rollback steps below have been read and are possible: `dnf history undo` needs the old packages, and `dnf list --showduplicates` shows baseos still carries them (openssh-server 9.9p1-23/-25/-27, expat el10_2.1/.3); the snapshot covers everything else

## 3. Plan (exact commands)

```bash
# on mon01: baseline green before the change
bash tests/verify.sh
# web01 (second SSH session kept open the whole time in case sshd breaks)
sudo bash ~/ak-infra-lab/tools/patch-web01.sh CHG-001
#   -> dnf upgrade --security -y, dnf history info last, sshd -t,
#      services + local /app/ check, needs-restarting -r/-s,
#      then reboots ONLY if every post-check passed
# after ~1 min, on mon01: post-change verification
bash tests/verify.sh
```

The reboot is planned even if `needs-restarting -r` doesn't require one. It loads the new libraries into every process, and it proves the box still boots unattended after the change.

## 4. Rollback plan

**Triggers:** `sshd -t` fails, a service doesn't come back, `verify.sh` shows a FAIL that isn't fixed within 15 min, or web01 doesn't boot.

1. **First choice:** `sudo dnf history undo <ID>`, with the transaction ID from `dnf history info last` in the log, then `sudo systemctl restart sshd` and run `verify.sh` again.
2. **SSH broken but the box is up:** use the second session that was kept open (or the VirtualBox console) to run step 1.
3. **Fallback:** power off and restore snapshot `baseline-E1`, then re-run `verify.sh`.

## 5. Execution log (real output, trimmed)

From `/home/akadmin/CHG-001-web01.log` (written by `tools/patch-web01.sh`):

```text
== CHG-001 start on web01.lab.local - before (20:14:35)
6.12.0-211.61.1.el10_2.x86_64
expat-2.7.3-1.el10_2.3.x86_64
openssh-server-9.9p1-27.el10_2.rocky.0.1.x86_64

== apply: dnf upgrade --security (20:14:36)
Upgrading:
 expat               x86_64     2.7.3-1.el10_2.5               baseos     121 k
 openssh             x86_64     9.9p1-28.el10_2.rocky.0.1      baseos     350 k
 openssh-clients     x86_64     9.9p1-28.el10_2.rocky.0.1      baseos     762 k
 openssh-server      x86_64     9.9p1-28.el10_2.rocky.0.1      baseos     541 k
Upgrade  4 Packages            Total download size: 1.7 M
Complete!

== transaction record (dnf history info last) (20:14:42)
Transaction ID : 8
Begin time     : Fri 02 Oct 2026 08:14:39 PM IST
End time       : Fri 02 Oct 2026 08:14:41 PM IST (2 seconds)
User           : akadmin <akadmin>
Return-Code    : Success
Command Line   : -y upgrade --security

== post-checks before reboot (20:14:42)
sshd -t: config OK
sshd active · nginx active · ak-app active · zabbix-agent2 active · rsyslog active · auditd active
local /app/ -> 200

== reboot needed? (20:14:42)
No core libraries or services have been updated since boot-up.
Reboot should not be necessary.
needs-restarting -r exit=0 (1 = reboot required)
services using old libraries:  dbus-broker.service  firewalld.service  polkit.service

== all post-checks OK - rebooting in 10 s (planned in CHG-001) (20:14:43)
The system will reboot now!   (20:14:53)
```

The sshd restart by the package scriptlet didn't drop the session running the change, and the drop-ins in `sshd_config.d/` (hardening, banner) survived: `sshd -t` passed and the banner still showed afterwards.

## 6. Post-checks

- [x] `dnf needs-restarting -r`: no reboot required. 3 services held old libraries (dbus-broker, firewalld, polkit, from the expat update), and the planned reboot loaded the new ones.
- [x] `tests/verify.sh` summary after both changes (about 20:25): **`22 PASS, 1 FAIL, 0 SKIP`**. The only FAIL is T13, the test-script bug above. T15/T18 are green again on both nodes. web01 was back up 3 minutes after the reboot with chrony `Leap status: Normal`, offset 1.7 ms.
- [ ] Zabbix: no new problems after 10 min (not recorded)
- [x] Versions after the change: kernel `6.12.0-211.61.1.el10_2` (unchanged), `openssh-server-9.9p1-28.el10_2.rocky.0.1`, `expat-2.7.3-1.el10_2.5`

## 7. Result

**Successful.** Both advisories are applied and web01 has no pending updates. The change took 18 s plus the reboot, with no rollback needed.

Follow-ups:
- Fix T13 in `tests/checks-web01.sh` (done: plain `useradd` + mail-spool cleanup) and confirm 23/0/0 on the next run.
- Process lesson: a red pre-check stops the change, even when the failures look unrelated.
- The VMs lose NTP sync after the host sleeps or loses network. Watch for it before every change (`chronyc tracking` must show `Leap status : Normal`).

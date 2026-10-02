# INC-007: developer akdev can't log in, account expired (`chage -E 0`)

| Field | Value |
|---|---|
| Node | web01 |
| Detected by | user ticket |
| Severity | P3: one user can't log in; no service impact |
| Date / time detected | 2026-10-02 21:36 IST (`ak-chaos.sh` injection at 21:36:32) |
| Time to resolve | about 6 min (fault 21:36:32 → restored about 21:42) |
| How blind | `ak-chaos.sh` random: the fault was unknown until `reveal` |

## 1. Symptom

- **Reported / alert text:** "TICKET: Developer akdev can't log in to web01 since this morning."
- **Baseline just before:** `verify.sh` 23/0/0 at about 21:35.
- **Note:** "since this morning" is the user's account; the fault was injected at 21:36:32. Tickets are often vague, or wrong, about when a problem started, so trust the logs.
- **What works:** akadmin's SSH and sudo; all services.
- **What doesn't:** key login as akdev, from Windows with akdev's own key.
- **Scope:** one account on web01.
- **Failing test(s):** none in `verify.sh` (it doesn't log in as akdev); a gap, see Prevention.

## 2. Hypotheses (most likely first)

1. The account is expired or locked (`chage` / `passwd -S`): a policy change, not a key problem.
2. akdev is no longer in `devs`, which `AllowGroups ops devs akbackup` requires.
3. Wrong ownership/mode/label on `~akdev/.ssh`: sshd ignores the key.

## 3. Diagnosis: commands run

### 3.1 Reproduce as the user (Windows)

```text
PS> ssh -i ~/.ssh/akdev_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes akdev@192.168.56.11 id
Authorized use only. Activity on this system is logged and audited.
akdev@192.168.56.11: Permission denied (publickey).
```

What it told me, read at the time: *publickey*, a key problem? **Corrected afterwards: this test proved nothing.** akdev's private key is passphrase-protected, and `-o BatchMode=yes` forbids ssh to ask for the passphrase. `ssh -v` (after the fix, 21:4x) shows the sequence:

```text
debug1: Offering public key: …/akdev_ed25519 ED25519 SHA256:H9fkJlq7…/OI explicit
debug1: Server accepts key: …/akdev_ed25519 ED25519 SHA256:H9fkJlq7…/OI explicit
debug1: no identity pubkey loaded from …/akdev_ed25519        <- can't decrypt the private key without the passphrase
akdev@192.168.56.11: Permission denied (publickey).
```

The server *accepts* the key, but ssh can't sign with it, so it gives up. That fails the same way **with or without the fault**. A reproduction is only evidence if it would succeed on a healthy system, so check that first. Correct test: without `BatchMode`, typing akdev's passphrase (section 6).

### 3.2 Server side: what sshd logged, and the account's state (web01)

```text
$ sudo journalctl -u sshd --since -10min --no-pager | grep -i akdev | tail -n 6
Oct 02 21:41:37 web01.lab.local sshd-session[6346]: Connection reset by authenticating user akdev 192.168.56.1 port 61172 [preauth]
======
$ id akdev
uid=1001(akdev) gid=1003(akdev) groups=1003(akdev),1002(devs)
======
$ sudo chage -l akdev
Last password change                                    : Oct 01, 2026
Password expires                                        : Dec 30, 2026
Password inactive                                       : never
Account expires                                         : Jan 01, 1970
Minimum number of days between password change          : 0
Maximum number of days between password change          : 90
Number of days of warning before password expires       : 7
======
$ sudo passwd -S akdev
akdev P 2026-10-01 0 90 7 -1
```

What it told me:
- **`Account expires: Jan 01, 1970`** is the root cause. That's day 0 of the Unix epoch: someone ran `chage -E 0`, which expires the account immediately. sshd refuses an expired account whatever the credentials: it checks the shadow expiry itself, and PAM's *account* stage checks it again. A correct key doesn't help.
- Ruled out **hypothesis 2**: akdev is still in `devs`.
- Ruled out a **locked password**: `passwd -S` shows `P` (usable password), not `LK`. Expiry and locking are different controls. Expiry (`chage -E`) blocks every login method, keys included. Locking (`usermod -L` / `passwd -l`) only disables the password.
- Note the **password** policy: max 90 days, warning 7. Those come from the E1 `login.defs` change (`PASS_MAX_DAYS 90`), so the password expires Dec 30, 2026. That's working as intended, and it's a different thing from the **account** expiry.
- The only sshd line, `Connection reset by authenticating user akdev … [preauth]`, comes from the flawed test in 3.1 (the client gave up before signing), so it says nothing about expiry. **`chage -l` was the deciding evidence**, not the log, and not the client error.

## 4. Root cause

akdev's account expiry date was set to day 0 (`chage -E 0 akdev`, shown as `Account expires: Jan 01, 1970`). sshd (its own shadow-expiry check, plus PAM's account stage) refuses an expired account for every login method, so akdev couldn't log in with any method. (The `Permission denied (publickey)` seen in 3.1 was a test artifact, see the correction there. The root cause rests on `chage -l` and is confirmed by the reveal.)

## 5. Fix

```bash
sudo chage -E -1 akdev        # -1 = the account never expires
sudo chage -l akdev | grep 'Account expires'   # -> never
```

**Deviation:** the fix wasn't run by hand. `ak-chaos.sh restore` (below) applied exactly this command (`chage -E -1 akdev`). The re-test of 3.1 after the fix wasn't recorded: next time, re-run the user's own command and see it succeed before closing.

## 6. Verification

- Account restored by `ak-chaos.sh restore` (`chage -E -1 akdev`); `chage -l akdev` → `Account expires : never`.
- **Valid re-test as the user** (with akdev's passphrase, through `ssh -J mon01`, because the direct path was temporarily blocked, see [INC-010](INC-010-sshd-persourcepenalties-admin-lockout.md)):
  ```text
  PS> ssh -J mon01 -i ~/.ssh/akdev_ed25519 -o IdentitiesOnly=yes akdev@192.168.56.11 id
  Enter passphrase for key 'C:\Users\ATHUL KRISHNA/.ssh/akdev_ed25519':
  uid=1001(akdev) gid=1003(akdev) groups=1003(akdev),1002(devs) context=unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023
  ```
- Regression: the next `verify.sh` (Part F) covers T03/T19, akdev's sudo rights. Login as akdev is not covered by `verify.sh` (see Prevention).

## 7. Prevention

1. **Treat expiry dates as changes.** An account expiry is a legitimate control (contractors, leavers), so it belongs in a change record or a ticket. Then "akdev can't log in" has a documented answer.
2. **Know the warning signs:** `chage -l` for the account, and `lastlog -u akdev` for the last successful login. A daily report of accounts expiring within 7 days (`chage -l` for every human user) gives a heads-up before the ticket arrives.
3. **Test the user's path.** Add a `verify.sh` check that logs in **as akdev** with akdev's key (from Windows, or with a test key on mon01). That would have caught this outright, the same lesson as INC-006: check what the user does.

## 8. Reveal

```text
$ sudo ak-chaos.sh reveal
fault: account-expired 2026-10-02 21:36:32
$ sudo ak-chaos.sh restore
restored: account-expired (marked done)
```

**The diagnosis matches the injected fault**: account expired, catalog INC-007. The catalog's expected path (sshd log / "account has expired" → `chage -l akdev`) was followed, except that this sshd build didn't print "expired" in the journal, so `chage -l` did the work.

## 9. Timeline

| Time | Event |
|---|---|
| 21:36:32 | Fault injected (blind): `chage -E 0 akdev` |
| ~21:41 | Reproduced from Windows: `Permission denied (publickey)` |
| 21:41:37 | sshd: `Connection reset by authenticating user akdev … [preauth]` |
| ~21:41 | `chage -l`: `Account expires: Jan 01, 1970` → root cause |
| ~21:42 | `reveal` = account-expired; `restore` ran `chage -E -1 akdev` |

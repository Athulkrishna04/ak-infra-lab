# INC-010: admin workstation locked out of web01 by sshd `PerSourcePenalties`

| Field | Value |
|---|---|
| Node | web01 (OpenSSH_9.9p1, Rocky 10.2) |
| Detected by | during work: every SSH from Windows refused, including akadmin |
| Severity | P2: no SSH from the admin workstation; services unaffected, out-of-band paths worked |
| Date / time detected | 2026-10-02 ~21:59 IST |
| Time to resolve | about 10 min (the penalty expired on its own; worked around through mon01 meanwhile) |
| How blind | **happened naturally** while re-testing INC-007, not injected |

## 1. Symptom

- From Windows (192.168.56.1), **every** SSH to web01 failed immediately, for akadmin as well as akdev:
  ```text
  PS> ssh -t web01 'sudo /usr/local/sbin/ak-chaos.sh inject'
  Connection closed by 192.168.56.11 port 22
  PS> ssh -o BatchMode=yes web01 uptime -p
  kex_exchange_identification: read: Software caused connection abort
  banner exchange: Connection to 192.168.56.11 port 22: Software caused connection abort
  ```
- **What works:** SSH to web01 **from mon01** (`up 4 minutes`, `OpenSSH_9.9p1`), and the website.
- **Scope:** one source address (the admin workstation) → one target (web01's sshd).

## 2. Hypotheses

1. sshd is refusing this *source address* (rate limiting / penalties), because mon01 gets in and Windows doesn't. **← it**
2. sshd down or misconfigured: ruled out, since mon01 connects fine.
3. The firewall: ruled out. The `mgmt` zone covers both sources, and the failure is at the SSH banner exchange, not a TCP timeout.

## 3. Diagnosis

### 3.1 Same target, two sources

```text
Windows (192.168.56.1) -> web01: banner exchange: ... Software caused connection abort
mon01 (192.168.56.10)  -> web01: up 4 minutes / OpenSSH_9.9p1
```

TCP connects, then sshd closes before the SSH banner, and only for one source. OpenSSH **9.8+** has `PerSourcePenalties`, **on by default**: addresses that cause failed or abandoned logins are temporarily refused, for up to 10 minutes by default.

### 3.2 sshd's own log (read through mon01: `ssh -t -J mon01 web01 'sudo journalctl -u sshd …'`)

```text
Oct 02 21:59:05 web01.lab.local sshd[913]: drop connection #0 from [192.168.56.1]:55509 on [192.168.56.11]:22 penalty: exceeded LoginGraceTime
Oct 02 21:59:21 web01.lab.local sshd[913]: drop connection #0 from [192.168.56.1]:55510 on [192.168.56.11]:22 penalty: exceeded LoginGraceTime
Oct 02 21:59:54 web01.lab.local sshd[913]: drop connection #0 from [192.168.56.1]:60635 on [192.168.56.11]:22 penalty: exceeded LoginGraceTime
```

The penalty reason is **`exceeded LoginGraceTime`**. Our M1 hardening sets `LoginGraceTime 30` in `configs/common/sshd_config.d/10-hardening.conf`.

## 4. Root cause

Two hardening controls interacted. akdev's key is passphrase-protected, and ssh asks for the passphrase **on the client** while the server's login timer runs. Whenever typing the passphrase took longer than our **`LoginGraceTime 30`**, sshd dropped the half-finished login and recorded a *grace-exceeded* penalty against 192.168.56.1. Earlier failed attempts added to it: the INC-007 test with `BatchMode=yes`, which offers the key and then can't sign, and the retries. Together these pushed the address over the `PerSourcePenalties` threshold, so sshd then refused **every** connection from it, akadmin's included, until the penalty expired. That's a brute-force defence working as designed, against its own admin.

## 5. Fix / workaround

- **Immediate:** use a path from another source address. `ssh -J mon01 web01 …` (ProxyJump) connects to web01 from 192.168.56.10, which isn't penalised. The penalty then expires on its own (max 600 s by default) *if* no further failing attempts are made.
- Verified at about 22:05: `ssh -o BatchMode=yes web01 uptime -p` → `up 6 minutes` from Windows directly.
- **No config change was made.** Keeping the protection is the right default.

## 6. Verification

- Direct SSH from Windows works again (`up 6 minutes`).
- INC-007's re-test passed through the jump host: `uid=1001(akdev) gid=1003(akdev) groups=1003(akdev),1002(devs)`.

## 7. Prevention

1. **Know the feature and the escape hatch.** OpenSSH 9.8+ penalises misbehaving sources. Symptom: `Connection closed` or `banner exchange … abort` from one machine only. Check: `journalctl -u sshd | grep penalty`. Escape hatch: a second source (`ssh -J mon01`) or the console. That's another reason to keep an out-of-band path (M1 runbook: [ssh-lockout](../runbooks/ssh-lockout.md)).
2. **Don't type passphrases against a 30 s timer.** Load keys into **ssh-agent** once (`Start-Service ssh-agent` (admin) then `ssh-add ~/.ssh/akdev_ed25519`), so the login itself takes milliseconds.
3. **Never test logins in `BatchMode` with a passphrase-protected key.** It fails every time and feeds the penalty counter (see INC-007 §3.1).
4. Optional, as a deliberate change: `PerSourcePenaltyExemptList 192.168.56.1` would exempt the admin workstation. That's a trade-off, because the most trusted source loses brute-force protection. Not done here.

## 8. Timeline

| Time | Event |
|---|---|
| ~21:41–21:58 | Failed akdev login attempts from Windows (BatchMode tests; slow passphrase entry) |
| 21:59:05–21:59:54 | sshd: `drop connection … from [192.168.56.1] … penalty: exceeded LoginGraceTime` |
| ~22:00 | Every SSH from Windows refused; mon01 → web01 works → per-source block suspected |
| ~22:03 | Log read through `ssh -J mon01`: cause confirmed |
| ~22:05 | Penalty expired; direct SSH from Windows works |

# Requirements

There's no real client, so this is a role-play: a written brief, stakeholders who get interviewed, and every answer turned into a requirement that a test can prove. **Rewrite it in your own words** before you commit it. This draft is only a starting point.

## 1. Brief

*AK Web Services* is a five-person company that runs one internal web application for its customers. Right now it sits on a single hand-built server that nobody fully understands. There's no monitoring, backups are "someone copies a folder sometimes", and every admin logs in as root with a shared password.

The owner wants a small, documented platform:
- one application server
- one operations server for monitoring, logs and backups
- a first-line (L1) on-call person who can see problems, follow a runbook and escalate
- a clear record of every change and every incident

## 2. Stakeholders

| Stakeholder | Cares about | Questions to ask (answer them in character) |
|---|---|---|
| Owner (sponsor) | Uptime, cost, risk | How long can the app be down? How much data can we afford to lose (RPO)? How fast must we be back (RTO)? |
| Developer (`akdev`) | Deploying content, reading logs | What do you need to do on the server, and what do you never need to do? |
| L1 on-call / NOC | Seeing problems early, knowing what to do | Which failures must page someone? What does "healthy" look like? Where are the runbooks? |
| Security / auditor | Who did what, least privilege | Who can become root? How do we know who changed users or sudo rules? Are logs kept off the box? |
| **Reviewer / hiring manager** (the real audience) | Evidence of skill | Can I follow the build? Is the output real? Can the candidate explain every line? |

## 3. Functional requirements

| ID | Requirement | Test(s) |
|---|---|---|
| FR-01 | Admins log in with personal SSH keys only; root and password logins are refused. | T01, T02 |
| FR-02 | Developers can restart nginx and read its journal, and do nothing else as root. | T03, T19 |
| FR-03 | The website and the app are served through nginx with SELinux enforcing. | T04, T05 |
| FR-04 | SSH is reachable only from the management network; the "public" side serves http only. | T06, T16, T17 |
| FR-05 | Application data lives on its own LVM volume that can grow without downtime. | T07 (+ the M2 extend evidence) |
| FR-06 | The application runs as an unprivileged user with memory, CPU and task limits. | T08 |
| FR-07 | Monitoring shows host health and raises a problem when nginx stops. | T09, T10 |
| FR-08 | Config and content are backed up nightly off the server, and a restore is proven. | T11, T12a, T12b |
| FR-09 | A health check summarises disk, load, memory, failed units, SELinux and time sync in one exit code. | T15 |
| FR-10 | Both servers keep accurate time. | T18 |
| FR-11 *(E1)* | Changes to users, sudo rules and the SSH config are audited. | T13 |
| FR-12 *(E1)* | Logs are copied off web01 to mon01 in near real time. | T14 |
| FR-13 *(E1)* | The kernel is hardened with sysctl defaults. | T20 |
| FR-14 *(E2)* | Every patch run follows a change record with a snapshot and a rollback plan. | `docs/changes/CHG-*` |
| FR-15 *(E2)* | Every incident gets a written report: symptom, diagnosis, root cause, fix, prevention. | `docs/incidents/INC-*` |

## 4. Non-functional requirements

| ID | Requirement | How it's checked |
|---|---|---|
| NFR-01 | The whole lab runs on an 8 GB Windows laptop alongside the OS. | mon01 2 GB + web01 1.5 GB; preflight.ps1 |
| NFR-02 | Every service comes back after a reboot with no manual step. | Reboot test in the test plan |
| NFR-03 | Backup RPO ≤ 25 h; an older backup raises an alert. | Zabbix trigger `ak.backup.age > 90000` |
| NFR-04 | No secrets in Git (keys, DB passwords). | `.gitignore`, `git grep -i password` before every push |
| NFR-05 | A reviewer can rebuild the lab from the README and the build guide. | Rebuild from the `clean-install` snapshot |
| NFR-06 | Only free software and free licences. | Tool list in the build guide |

## 5. Constraints, assumptions and out of scope

- **Constraints:** 7.7 GB RAM and a 2-core CPU; VirtualBox only; C: nearly full, so everything lives on D:.
- **Assumptions:** the lab is single-site, and names resolve through `/etc/hosts` (no DNS server).
- **Out of scope:** HA/clustering, TLS certificates for the web app, email or SMS alert delivery (Zabbix *Problems* is the alert surface; a Telegram media type is optional), Kubernetes, cloud, and the AD/ServiceNow lab (a separate project).

## 6. Success criteria

| ID | Criterion |
|---|---|
| SC1 | `tests/verify.sh` shows **0 FAIL** at v1.0 (only T13, T14 and T20 SKIP), and T10 is recorded with screenshots. |
| SC2 | web01 survives a reboot with every test still passing. |
| SC3 | INC-001 (the SELinux 502) is written up from real output. |
| SC4 | A restore from backup is proven (T12b) and documented in the restore runbook. |
| SC5 | The README, IP plan and build guide let someone else rebuild the lab. |
| SC6 | *(v1.1)* 8 injected incidents are written up, with at least 6 of them diagnosed blind using `ak-chaos.sh`. |

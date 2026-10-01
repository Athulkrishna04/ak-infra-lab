# CHG-0NN: <title>

Copy to `docs/changes/CHG-0NN-<slug>.md` and fill in sections 1–4 **before** the change starts.

| Field | Value |
|---|---|
| Node(s) | |
| Type | standard (pre-approved, e.g. monthly security patching) · normal · emergency |
| Window | YYYY-MM-DD HH:MM–HH:MM IST |
| Risk | low / medium / high, with one sentence on why |
| Snapshot taken | `pre-patch-latest` at HH:MM (yes/no) |

## 1. Reason

What is changing and why (e.g. "5 security advisories pending, 1 Important").

## 2. Pre-checks

- [ ] `tests/verify.sh` green before starting (paste the summary line)
- [ ] Zabbix shows no open problems for the node
- [ ] Snapshot taken
- [ ] Rollback steps below have been read and are possible

## 3. Plan (exact commands)

```bash
```

## 4. Rollback plan

Say what triggers a rollback, for example "verify.sh FAIL not fixed within 15 min" or "the node doesn't boot". Then give the steps:
1. First choice (e.g. `dnf history undo <id>`)
2. Fallback (revert snapshot `pre-patch-latest`)

## 5. Execution log (real output, trimmed)

```text
```

## 6. Post-checks

- [ ] `dnf needs-restarting -r` / `/var/run/reboot-required` handled
- [ ] `tests/verify.sh` summary:
- [ ] Zabbix: no new problems after 10 min
- [ ] Kernel / package versions after the change:

## 7. Result

Successful / rolled back / partially done. Include the duration and any follow-up.

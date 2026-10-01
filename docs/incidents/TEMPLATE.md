# INC-0NN: <title>

| Field | Value |
|---|---|
| Node | |
| Detected by | Zabbix trigger · healthcheck · user ticket · during build |
| Severity | P1 service down · P2 degraded · P3 no user impact |
| Date / time detected | |
| Time to resolve | |
| How blind | `ak-chaos.sh` random · injected by hand (not blind) · happened naturally |

## 1. Symptom

*Write this before touching the CLI, from the user's or the monitoring's point of view.*

- **Reported / alert text:**
- **What works:**
- **What doesn't:**
- **Scope:** which node, which service, which clients (mgmt side vs public side vs local)
- **Failing test(s):**

## 2. Hypotheses (most likely first)

1.
2.
3.

## 3. Diagnosis: commands run

*In order, with trimmed **real** output. Include the dead ends.*

### 3.1 `<command>` on `<node>`

```text
<paste output>
```

What it told me:

### 3.2 `<command>` on `<node>`

```text
<paste output>
```

What it told me:

## 4. Root cause

*One sentence, plus why it produces exactly this symptom.*

## 5. Fix

```bash
<exact commands>
```

## 6. Verification

- Failing test re-run:
- Regression smoke set (`bash tests/verify.sh`): N PASS / 0 FAIL
- Zabbix problem resolved at:
- Evidence: `docs/screenshots/INC-0NN-...png`

## 7. Prevention

*One control that would have prevented this, or caught it sooner.*

## 8. Timeline (optional, for P1)

| Time | Event |
|---|---|
| | Alert fired |
| | Diagnosis started |
| | Root cause found |
| | Fixed and verified |

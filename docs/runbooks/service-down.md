# Runbook: a service is down (nginx / ak-app)

**Triggered by:** the Zabbix problem "nginx is down on web01", a healthcheck `CRIT: failed units: …`, or a user reporting that the site doesn't load.
**Who:** L1 can run steps 1–4. If the cause isn't clear after 15 minutes, escalate.

## 1. Confirm and scope

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.56.11/        # from mon01: 000 = no answer, 502 = nginx up but backend not, 403 = permission/label
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.56.11/app/
```

| Result | Points to |
|---|---|
| `000` / timeout from mon01, but `curl http://127.0.0.1/` on web01 works | firewall (the `mgmt` zone lost http). Zabbix still looks happy because its check runs locally |
| `000` everywhere | nginx not running |
| `502` on `/app/` only | ak-app down, or SELinux blocking the proxy ([selinux-denial](selinux-denial.md)) |
| `403` | file permissions or SELinux label ([selinux-denial](selinux-denial.md)) |

## 2. Look at the unit

```bash
systemctl status nginx ak-app --no-pager
journalctl -u nginx -b --no-pager -n 50
journalctl -p err -b --no-pager -n 30
```

## 3. Common causes and fixes

| Cause | Check | Fix |
|---|---|---|
| Config syntax error | `sudo nginx -t` | Fix the file it names, run `nginx -t` again, then `systemctl restart nginx` |
| Port already in use | `sudo ss -tlpn 'sport = :80'` | Stop the other process |
| Firewall | `sudo firewall-cmd --zone=mgmt --list-services` | `firewall-cmd --zone=mgmt --add-service=http` (plus `--permanent`) |
| ak-app killed by its memory limit | `journalctl -u ak-app -b`, `journalctl -k \| grep -i oom` | Find out why it used >128M before you raise `MemoryMax` |
| `/srv/app` not mounted | `findmnt /srv/app` | [emergency-mode-fstab](emergency-mode-fstab.md) |

## 4. Verify

```bash
systemctl is-active nginx ak-app
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.56.11/app/     # 200 from mon01
```

The Zabbix problem must resolve by itself within about a minute. Then run the regression smoke set: `bash tests/verify.sh`.

## 5. Record

Open `docs/incidents/INC-0NN-<slug>.md` from the [template](../incidents/TEMPLATE.md).

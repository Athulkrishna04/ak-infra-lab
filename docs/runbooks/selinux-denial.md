# Runbook: SELinux denial

**Symptoms:** permission errors (a 403, a 502 from a proxy, "permission denied" in a service log) even though ordinary Unix permissions look correct.

**Rule: never "fix" it with `setenforce 0`.** At most, use `setenforce 0` for one minute to *confirm* SELinux is the cause, then switch it straight back to 1.

## 1. Confirm it is SELinux

```bash
getenforce                                          # Enforcing
sudo ausearch -m AVC,USER_AVC -ts recent            # raw denials from the last 10 minutes
sudo ausearch -m AVC -ts recent | audit2why         # plain-English reason + suggested fix
sudo journalctl -t setroubleshoot --since -10min    # if setroubleshoot-server is installed
```

Read the denial like this: **source context** (`scontext`, e.g. `httpd_t`) wanted **permission** (e.g. `name_connect`, `read`) on **target** (`tcontext`, e.g. `http_cache_port_t`, `user_tmp_t`).

## 2. Pick the right tool

| audit2why says | Meaning | Fix |
|---|---|---|
| Missing type enforcement, with a **boolean** suggested | The policy already allows it behind a switch | `sudo setsebool -P <boolean> on`. Prefer the narrowest boolean offered (for example `httpd_can_network_relay` over `httpd_can_network_connect`) |
| A file has the **wrong type** (e.g. `user_tmp_t`, `admin_home_t` under /srv/www) | It was moved with `mv`, or created somewhere else | `sudo restorecon -Rv <path>`. If the directory is custom, define it once: `sudo semanage fcontext -a -t httpd_sys_content_t "/srv/www(/.*)?"` then `restorecon` |
| A service must use a **non-standard port** | The port isn't labeled for that service | `sudo semanage port -a -t <type> -p tcp <port>` (e.g. `syslogd_port_t 20514`) |
| None of the above | The policy genuinely lacks a rule | Last resort: `sudo ausearch -m AVC -ts recent \| audit2allow -M ak-local` and review `ak-local.te` **before** `semodule -i ak-local.pp`. Document why |

## 3. Verify

```bash
ls -Z <path>                          # expected type now
getsebool -a | grep <boolean>
sudo ausearch -m AVC -ts recent       # "<no matches>" after you retry the action
getenforce                            # still Enforcing
```

## Useful references

- `semanage fcontext -l | grep /srv` lists the custom file-context rules you've added.
- `sesearch -A -s httpd_t -t http_cache_port_t -c tcp_socket` shows what the policy allows (from the `setools-console` package).

# INC-001: nginx returns 502 for /app/ under SELinux

| Field | Value |
|---|---|
| Node | web01 (Rocky Linux 10.2, SELinux enforcing) |
| Detected by | During the build (M2.6): the first request through the new reverse proxy |
| Severity | P2: the static site at `/` worked, the application at `/app/` was down |
| Date / time detected | 2026-10-01 18:14:52 IST (first denied connect in the nginx error log) |
| Time to resolve | ~10 minutes |
| How blind | Happened naturally. Nothing was injected; this is the default policy meeting a new proxy config |

## 1. Symptom

- **Reported:** `/app/` returned **HTTP 502 Bad Gateway** right after nginx was set up as a reverse proxy to ak-app.
- **What works:** `http://web01/` returns 200 (static page from `/srv/www`). ak-app itself answers on `127.0.0.1:8080` (`ak-app OK`).
- **What doesn't:** `http://web01/app/`, the nginx → ak-app hop.
- **Scope:** web01 only, the `/app/` location only, from every client (local, mgmt and public side). So the fault sits between nginx and the backend, not in the network.
- **Failing test(s):** T05 (`/app/` must return 200).

## 2. Hypotheses (most likely first)

1. ak-app is not running or not listening on 8080. *Ruled out: a direct `curl http://127.0.0.1:8080/` returned `ak-app OK`.*
2. Typo in `proxy_pass` (wrong port or path). *Ruled out: `nginx -t` passed and the config matches the repo file.*
3. Something is **blocking nginx itself** from opening the connection. On RHEL, with SELinux enforcing, that is the prime suspect.

## 3. Diagnosis: commands run

### 3.1 Status code and backend check on web01

Status codes taken locally on web01 right after nginx was enabled (`curl -w %{http_code}` for `/` and `/app/`, then `getenforce`):

```text
root=200
app=502
Enforcing
```

The backend, tested directly, bypassing nginx:

```text
$ curl -s http://127.0.0.1:8080/
ak-app OK
```

### 3.2 nginx error log

```text
$ sudo grep -m3 8080 /var/log/nginx/error.log
2026/10/01 18:14:52 [crit] 1808#1808: *3 connect() to 127.0.0.1:8080 failed (13: Permission denied) while connecting
  to upstream, client: 127.0.0.1, server: web01.lab.local, request: "GET /app/ HTTP/1.1", upstream: "http://127.0.0.1:8080/", host: "127.0.0.1"
2026/10/01 18:17:01 [crit] 1808#1808: *6 connect() to 127.0.0.1:8080 failed (13: Permission denied) while connecting
  to upstream, client: 127.0.0.1, server: web01.lab.local, request: "GET /app/ HTTP/1.1", upstream: "http://127.0.0.1:8080/", host: "127.0.0.1"
```

What it told me: error 13 is a *permission* failure on the connect() call, not "connection refused". The backend was listening, and nginx was not allowed to reach it.

### 3.3 `ausearch -m AVC -ts recent | audit2why` on web01

```text
type=AVC msg=audit(1790858692.937:684): avc:  denied  { name_connect } for  pid=1808 comm="nginx" dest=8080
  scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:http_cache_port_t:s0 tclass=tcp_socket permissive=0

        Was caused by:
        One of the following booleans was set incorrectly.
        Description:
        Allow httpd to can network connect

        Allow access by executing:
        # setsebool -P httpd_can_network_connect 1
        Description:
        Allow httpd to can network relay

        Allow access by executing:
        # setsebool -P httpd_can_network_relay 1
type=AVC msg=audit(1790858821.733:722): avc:  denied  { name_connect } for  pid=1808 comm="nginx" dest=8080
  scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:http_cache_port_t:s0 tclass=tcp_socket permissive=0
  (same explanation repeated)
```

What it told me: the process `nginx` runs in the SELinux domain **`httpd_t`**. It was denied **`name_connect`** (opening an outgoing TCP connection) to port **8080**, which the policy labels **`http_cache_port_t`**. `permissive=0` means the denial was enforced, not just logged. audit2why named two booleans that would allow it.

### 3.4 Port label and current booleans

```text
$ semanage port -l | grep -w 8080
http_cache_port_t              tcp      8080, 8118, 8123, 10001-10010

$ getsebool -a | grep httpd_can_network
httpd_can_network_connect --> off
httpd_can_network_connect_cobbler --> off
httpd_can_network_connect_db --> off
httpd_can_network_memcache --> off
httpd_can_network_redis --> off
httpd_can_network_relay --> off
```

What it told me: both candidate booleans were off, which matches the denial.

## 4. Root cause

The SELinux policy confines nginx (`httpd_t`) and, by default, forbids it to open outbound connections to `http_cache_port_t` ports such as 8080. The new `proxy_pass http://127.0.0.1:8080/` therefore had its `connect()` denied with EACCES. nginx turned that into **502 Bad Gateway** for `/app/` only, while static files under `/` (correctly labelled `httpd_sys_content_t`) kept working.

## 5. Fix

audit2why offered two booleans. I chose the **narrower** one:

- `httpd_can_network_relay` lets httpd connect to web, proxy and cache ports, which is exactly what a reverse proxy needs.
- `httpd_can_network_connect` would let httpd connect to *any* TCP port.

```text
$ sudo setsebool -P httpd_can_network_relay on      # -P = persistent across reboots
$ getsebool httpd_can_network_relay
httpd_can_network_relay --> on
$ curl -s http://127.0.0.1/app/
ak-app OK
$ getenforce
Enforcing
```

SELinux was **not** disabled or switched to permissive at any point.

## 6. Verification

- Failing test re-run: T05 `/` = 200, `/app/` = 200 from mon01 (mgmt side). T17 `/` and `/app/` = 200 via web01's labnet IP 10.0.10.6 (public side). `/app/` = 200 from Windows.
- Survives reboot: after `systemctl reboot` (booted 18:19:59), `getsebool` still shows `httpd_can_network_relay --> on`, `getenforce` = Enforcing, and `/app/` = 200.
- A 60-second request loop from mon01 returned only `200`.
- Evidence: this report. Optionally add `docs/screenshots/INC-001-audit2why.png`.

## 7. Prevention

- Treat SELinux as part of every reverse-proxy change: after editing `proxy_pass`, run `ausearch -m AVC -ts recent` before calling the change done.
- Automate it: `tests/verify.sh` (T05) fails if `/app/` isn't 200, and the Ansible `web` role (E3) sets this boolean with `ansible.posix.seboolean` so a rebuild can't reintroduce the fault.
- Rule of thumb, and the interview answer: **fix SELinux with the narrowest tool** (a boolean, `semanage fcontext` + `restorecon`, or `semanage port`), **never with `setenforce 0`**.

# Zabbix: template "AK Linux Lab"

Zabbix 7.0 LTS. The server, frontend and database run on mon01, and agent 2 runs on web01. Agent 2 on mon01 also monitors the server itself.

Build the template **by hand in the web UI** (build guide M3.6), then export it into [`templates/`](templates/). The YAML committed here must be the real export from your Zabbix, not something typed up to look like one.

## Hosts

| Host | Interface | Templates |
|---|---|---|
| Zabbix server (mon01, pre-created) | Agent 127.0.0.1:10050 | Linux by Zabbix agent, Zabbix server health |
| web01 | Agent 192.168.56.11:10050 | Linux by Zabbix agent, **AK Linux Lab** |

The disk-space triggers (80% warning / 90% high) already come from "Linux by Zabbix agent". Don't duplicate them.

## Template "AK Linux Lab": items

*Data collection → Templates → Create template*, name `AK Linux Lab`, group `Templates/AK`. Then *Items → Create item*:

| Name | Key | Type | Type of information | Interval | Units |
|---|---|---|---|---|---|
| AK nginx port 80 | `net.tcp.service[http,,80]` | Zabbix agent | Numeric (unsigned) | 30s | |
| AK health status | `ak.health.status` | Zabbix agent | Numeric (unsigned) | 1m | |
| AK backup age | `ak.backup.age` | Zabbix agent | Numeric (unsigned) | 5m | s |
| AK memory available | `ak.mem.avail_pct` | Zabbix agent | Numeric (float) | 1m | % |

The last three come from the UserParameters in [`zabbix_agent2.d/ak.conf`](zabbix_agent2.d/ak.conf).

## Template "AK Linux Lab": triggers

| Name | Severity | Expression |
|---|---|---|
| nginx is down on {HOST.NAME} | High | `last(/AK Linux Lab/net.tcp.service[http,,80])=0` |
| Health check CRIT on {HOST.NAME} | High | `last(/AK Linux Lab/ak.health.status)=2` |
| Health check WARN on {HOST.NAME} | Warning | `last(/AK Linux Lab/ak.health.status)=1` |
| Backup older than 25 h on {HOST.NAME} | High | `last(/AK Linux Lab/ak.backup.age)>90000` |
| Memory pressure on {HOST.NAME} | Warning | `max(/AK Linux Lab/ak.mem.avail_pct,5m)<10` |

Optional: make the WARN trigger depend on the CRIT trigger (the trigger's *Dependencies* tab), so a CRIT doesn't also raise a WARN.

## Host web01: external HTTP check (INC-006 follow-up, 2026-10-02)

Everything above runs **on the box**. `net.tcp.service[http,,80]` is asked of web01's agent, which connects to web01 from web01. In [INC-006](../docs/incidents/INC-006-firewalld-mgmt-http-removed.md), the firewalld `mgmt` zone lost `http`: every admin lost the site while that check stayed green. The fix is a check that takes **the user's path**, run by the Zabbix **server** on mon01 across the mgmt network:

| Object | Setting |
|---|---|
| Web scenario (on host web01) | `ext-http-mgmt`, interval 30s, attempts 1, agent Zabbix |
| Step 1 `home` | `http://192.168.56.11/`, timeout 5s, required status 200 |
| Step 2 `app` | `http://192.168.56.11/app/`, timeout 5s, required status 200 |
| Trigger | **web01 website unreachable from mon01 (mgmt network)**, High: `last(/web01/web.test.fail[ext-http-mgmt])<>0` |

`web.test.fail` is 0 when every step passes, otherwise the number of the failing step. It lives on the host, not in the template: the URLs are web01's, and mon01 doesn't serve `/app/`.

**Proven** by re-injecting the INC-006 fault by name (`ak-chaos.sh inject firewall-http`, held for 2 minutes):

| Time | Event |
|---|---|
| 21:20:57 | `http` removed from the `mgmt` zone |
| **21:21:01** | **"web01 website unreachable from mon01 (mgmt network)" (High) raised, 4 s later** |
| ~21:22:57 | Restored (`mgmt services: http ssh`) |
| 21:23:01 | RESOLVED, duration 2m |
| (none) | "nginx is down on web01" did **not** fire: nginx was up the whole time |

Screenshots: [scenario OK before](../docs/screenshots/INC-006-ext-check-ok.png) · [problem fired and resolved](../docs/screenshots/INC-006-ext-check-fired.png).

Together the two checks tell failures apart: **both red** = nginx is down; **only the external one red** = nginx is up but unreachable (firewall, network path).

## Passive vs active checks (interview point)

- **Passive** (item type "Zabbix agent"): the server connects to the agent on **10050/tcp** and asks for one value. That's why web01's firewalld `mgmt` zone opens 10050.
- **Active** (item type "Zabbix agent (active)"): the agent fetches its item list from the server and pushes values to **10051/tcp**. That's why mon01's ufw opens 10051 and the agent config sets `ServerActive`.
- Everything in this template is passive. The "Linux by Zabbix agent" template is passive too; "Linux by Zabbix agent active" is its active twin.

## Export

*Data collection → Templates* → tick `AK Linux Lab` → *Export* → YAML → save as `zabbix/templates/ak-linux-lab.yaml`.

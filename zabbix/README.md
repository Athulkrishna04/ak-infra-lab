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

## Passive vs active checks (interview point)

- **Passive** (item type "Zabbix agent"): the server connects to the agent on **10050/tcp** and asks for one value. That's why web01's firewalld `mgmt` zone opens 10050.
- **Active** (item type "Zabbix agent (active)"): the agent fetches its item list from the server and pushes values to **10051/tcp**. That's why mon01's ufw opens 10051 and the agent config sets `ServerActive`.
- Everything in this template is passive. The "Linux by Zabbix agent" template is passive too; "Linux by Zabbix agent active" is its active twin.

## Export

*Data collection → Templates* → tick `AK Linux Lab` → *Export* → YAML → save as `zabbix/templates/ak-linux-lab.yaml`.

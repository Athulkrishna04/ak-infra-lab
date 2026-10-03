# IP, user and port plan (source of truth)

This file is the source of truth. If a config file disagrees with it, the config is the one that's wrong.

## Networks

| Network | VirtualBox type | Subnet | DHCP | Purpose |
|---|---|---|---|---|
| `labnet` | NAT Network (adapter 1 on every VM) | 10.0.10.0/24 | on (VirtualBox) | Outbound internet for dnf/apt; VMs can also reach each other here. It's the "public" side for firewalld tests T16/T17. |
| host-only | Host-only adapter (adapter 2 on every VM) | 192.168.56.0/24 | **off** | Management plane: SSH, Zabbix, logs, backups, web UI from Windows. |

The Windows host is **192.168.56.1** on the host-only network. The default route on each VM goes out adapter 1 (labnet). Adapter 2 has **no gateway**.

## Nodes (8 GB layout)

| Node | OS | vCPU | RAM | Disks | Adapter 1 (enp0s3) | Adapter 2 (enp0s8) |
|---|---|---|---|---|---|---|
| mon01 | Ubuntu Server 24.04 LTS | 2 | 2 GB | 25 GB | DHCP 10.0.10.x | **192.168.56.10/24** |
| web01 | Rocky Linux 10 (Minimal) | 1 | 2 GB during install → 1.5 GB | 20 GB (OS) + 5 GB (`sdb`, M2) + 2 GB (`sdc`, M2 extend) | DHCP 10.0.10.x | **192.168.56.11/24** |
| nfs01 | Rocky Linux 10 | 1 | 1.5 GB | 20 + 5 GB | DHCP | 192.168.56.12/24 (16 GB laptops only, E4) |

Check the interface names with `ip -br link` after the install. VirtualBox normally gives `enp0s3` and `enp0s8`.

## Names

`/etc/hosts` on both VMs ([configs/common/hosts.lab](../configs/common/hosts.lab)):

```
192.168.56.10   mon01.lab.local   mon01
192.168.56.11   web01.lab.local   web01
```

## Users and groups

| Account | Node(s) | Groups | Login | Purpose |
|---|---|---|---|---|
| `akadmin` | both | `ops` (+ `wheel`/`sudo` until M1 proves `ops` works) | SSH key | Administrator: full sudo with a password |
| `akdev` | web01 | `devs` | SSH key (its own) | Developer: may restart nginx and read its journal, nothing else |
| `akapp` | web01 | `akapp` (system) | none (`/sbin/nologin`) | Runs `ak-app.service` |
| `akbackup` | mon01 | `akbackup` | SSH key from web01's root, locked to rrsync in E1 | Receives backup archives in `/srv/backups/<host>/` |
| `root` | both | | console only; password set (needed for emergency mode) | Never over SSH |
| `zabbix` | both | | none | Created by the Zabbix packages |

## Storage (web01)

| Device | PV | VG | LV | FS | Mount | Notes |
|---|---|---|---|---|---|---|
| 5 GB disk (`web01-data1.vdi`) | yes | `vg_data` | `lv_app` 3 GB | XFS | `/srv/app` (fstab by UUID) | M2 |
| 2 GB disk (`web01-data2.vdi`) | yes | `vg_data` | `lv_app` +2 GB → **5 GB** | | | M2 online extend with `lvextend -r` |

Kernel names: after the 2 GB disk was attached, the kernel called it **`sdb`** and renamed the 5 GB disk **`sdc`**. Never refer to these disks by `sdX`; fstab uses the filesystem UUID. `vg_data` is 6.99 GB with 1.99 GB free.

mon01 was installed **without LVM**: one ext4 root partition (`sda2`, 25 GB). `/srv/backups` is a plain directory on it.

## Ports and flows

| From | To | Port | Purpose | Allowed by |
|---|---|---|---|---|
| Windows 192.168.56.1 | web01, mon01 | 22/tcp | SSH administration | web01 firewalld `mgmt` · mon01 ufw |
| Windows | mon01 | 80/tcp | Zabbix web UI | mon01 ufw |
| Windows, mon01 | web01 | 80/tcp | Website `/` and `/app/` | web01 `mgmt` |
| (any on labnet) | web01 10.0.10.x | 80/tcp only | "Public" side, T17 | web01 `public` |
| (any on labnet) | web01 10.0.10.x | 22/tcp **blocked** | T16 | web01 `public` (no ssh) |
| mon01 | web01 | 10050/tcp | Zabbix passive checks | web01 `mgmt` |
| web01 | mon01 | 10051/tcp | Zabbix active checks | mon01 ufw |
| web01 | mon01 | 20514/tcp | rsyslog forwarding (E1) | mon01 ufw; web01 SELinux `syslogd_port_t` |
| web01 (root) | mon01 (akbackup) | 22/tcp | rsync over SSH backups | mon01 ufw + `AllowGroups` |
| web01 nginx | web01 127.0.0.1 | 8080/tcp | Reverse proxy to ak-app | SELinux boolean (INC-001) |

## Listening ports (E1.5 review, 2026-10-02, `ss -tuln`)

Every listening socket must be explained. Anything that isn't gets disabled.

| Node | Proto / address | Service | Why it's there | Reachable from |
|---|---|---|---|---|
| web01 | tcp 0.0.0.0:22, [::]:22 | sshd | Administration | mgmt zone only (192.168.56.0/24) |
| web01 | tcp 0.0.0.0:80, [::]:80 | nginx | Website + `/app/` proxy | mgmt and public zones |
| web01 | tcp 127.0.0.1:8080 | ak-app (python http.server) | Backend behind nginx | localhost only |
| web01 | tcp *:10050 | zabbix-agent2 | Passive checks from mon01 | mgmt zone only |
| web01 | udp 127.0.0.1:323, [::1]:323 | chronyd | `chronyc` control socket | localhost only |
| mon01 | tcp 0.0.0.0:22, [::]:22 | sshd | Administration, backups (akbackup) | ufw: 192.168.56.0/24 |
| mon01 | tcp 0.0.0.0:80 | nginx | Zabbix web UI | ufw: 192.168.56.0/24 |
| mon01 | tcp 0.0.0.0:10051, [::]:10051 | zabbix-server | Active agent checks | ufw: 192.168.56.0/24 |
| mon01 | tcp 0.0.0.0:20514, [::]:20514 | rsyslogd (imtcp) | Central log receiver (E1) | ufw: 192.168.56.0/24 |
| mon01 | tcp *:10050 | zabbix-agent2 | Server monitors itself | blocked by ufw (no rule); used via localhost |
| mon01 | tcp 127.0.0.1:3306 | mariadb | Zabbix database | localhost only |
| mon01 | tcp/udp 127.0.0.53:53, 127.0.0.54:53 | systemd-resolved | Local DNS stub | localhost only |
| mon01 | udp 10.0.10.5:68 | systemd-networkd | DHCP client on labnet | n/a (client) |
| mon01 | udp 127.0.0.1:323, [::1]:323 | chrony | `chronyc` control socket | localhost only |
| mon01 | udp 127.0.0.1:161, [::1]:161 | ~~snmpd~~ | **Not needed.** Pulled in as a "recommended" package with Zabbix, with no access config | **Disabled** 2026-10-02 (`systemctl disable --now snmpd`); 0 sockets on :161 afterwards |

## Snapshots (at most 3 per VM, always taken with the VM powered off)

| VM | Name | Taken | Purpose |
|---|---|---|---|
| both | `clean-install` | end of M0 | Fresh OS, static IPs, Windows key; the base image the E3 rebuild starts from |
| both | `baseline-E1` | 2026-10-02 19:35 | Hardened + central logging, `verify.sh` 23/0/0 (v1.1 code base before E2) |
| mon01 | `baseline-M3` | end of M3 | Monitoring + backups working (v1.0 state) |
| web01 | `baseline-E3` | 2026-10-03 | Rebuilt by Ansible from `clean-install`, patched in CHG-003, `verify.sh` 23/0/0, playbook `changed=0` |

Rotated out along the way: `baseline-M1`, `baseline-M2`, `pre-boot-drills` (E2 drills), `pre-ansible` (the v1.1 web01 before the E3 rebuild).
web01's original data disks (`web01-data1.vdi`, `web01-data2.vdi`) live on only in `baseline-E1`; the rebuilt web01 uses `web01-data1-e3.vdi` / `web01-data2-e3.vdi`.

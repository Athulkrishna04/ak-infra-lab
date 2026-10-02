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

## Snapshots (at most 3 per VM)

| Name | Taken | Purpose |
|---|---|---|
| `clean-install` | end of M0 | Fresh OS, static IPs, nothing else |
| `baseline-M1` | end of M1 | Users, keys, SSH/firewall hardening |
| `pre-patch-latest` | before every patch run or risky change (replace the old one) | Rollback point |

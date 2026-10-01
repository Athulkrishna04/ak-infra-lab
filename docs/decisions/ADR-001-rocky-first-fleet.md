# ADR-001: Rocky Linux 10 for the app server, Ubuntu 24.04 for the ops server

**Status:** accepted · **Date:** 2026-09-29

## Context

Every Linux job description that named a distro in the research sample included a RHEL-family one. RHCSA (EX200) is now based on RHEL 10. At the same time, junior admins are expected to work on Ubuntu as well: apt, AppArmor, ufw and netplan. The laptop has 7.7 GB RAM, so there's room for only two VMs.

## Decision

- **web01 = Rocky Linux 10 Minimal.** It's RHEL 10-compatible and free, and it gives SELinux, firewalld, dnf and NetworkManager/`nmcli`. That's where the RHCSA-relevant work happens.
- **mon01 = Ubuntu Server 24.04 LTS.** It's the Zabbix host, with packages for 7.0 LTS, and it provides the apt/ufw/netplan contrast.
- **Fallback:** if the v3 check in M0.7 fails (the CPU or hypervisor exposes only x86-64-v2), use the AlmaLinux 10 x86-64-v2 image or Rocky 9.x, and record it here.

## Evidence (M0.7, 2026-10-01)

Run inside mon01 (Ubuntu 24.04.5, kernel 6.8.0-146), with VirtualBox 7.2.20 on VT-x after the Windows hypervisor was turned off ([ADR-004](ADR-004-host-hypervisor-off.md)):

```text
akadmin@mon01:~$ /lib64/ld-linux-x86-64.so.2 --help | grep x86-64-v
  x86-64-v4
  x86-64-v3 (supported, searched)
  x86-64-v2 (supported, searched)
```

v3 is supported, so Rocky Linux 10 is used for web01, and the AlmaLinux fallback isn't needed.

## Consequences

- The project shows both families, and every "Rocky vs Ubuntu" interview question has a concrete answer from the lab.
- Rocky 10 needs an x86-64-v3 CPU, which is why the host hypervisor question matters ([ADR-004](ADR-004-host-hypervisor-off.md)).
- A literal "RHEL" node is optional later, through the free Red Hat Developer Subscription.

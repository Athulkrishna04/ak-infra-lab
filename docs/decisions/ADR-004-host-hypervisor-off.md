# ADR-004: Switch the Windows hypervisor off on lab days

**Status:** accepted (review after the first M0 attempt) · **Date:** 2026-09-29

## Context

On this laptop (Windows 11 Home, i3-1115G4, 7.7 GB) the Windows hypervisor is running for two reasons: **WSL2** (Ubuntu, kali-linux) and **Memory Integrity** (HVCI, part of Core isolation). When the hypervisor is on, VirtualBox has to run on top of it through the Hyper-V API ("NEM", shown as a green turtle). That mode is slower and may not pass AVX2 through to guests, and Rocky Linux 10 needs x86-64-v3 (AVX2).

## Decision

On lab days:
1. Run `wsl --shutdown`.
2. Turn **Memory integrity off** in *Windows Security → Device security → Core isolation details*.
3. From an elevated prompt, run `bcdedit /set hypervisorlaunchtype off` and reboot.

Afterwards, `tools/preflight.ps1` must report "Windows hypervisor is off".

To go back (WSL2 or Docker days): run `bcdedit /set hypervisorlaunchtype auto`, turn Memory integrity back on, and reboot.

**Fallback if you'd rather keep Memory integrity on:** leave the hypervisor running and accept NEM mode. Run the v3 check in M0.7, and if Rocky 10 won't boot, use AlmaLinux 10 x86-64-v2 ([ADR-001](ADR-001-rocky-first-fleet.md)).

## Consequences

- **Security trade-off:** while the hypervisor is off, Memory Integrity isn't protecting Windows. This is a personal laptop, the trade-off is time-boxed to lab sessions, and the restore steps are written down.
- WSL2 and the lab can't run at the same time. Plan WSL and Docker work for other days.
- Every switch needs a reboot.

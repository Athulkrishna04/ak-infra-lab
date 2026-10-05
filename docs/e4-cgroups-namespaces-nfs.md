# E4: cgroups, namespaces, performance baseline, NFS + autofs (evidence)

All on the 2-node lab (web01 = 1 vCPU / 1.5 GB). Parts A–C come from `tools/e4-demos.sh` (log `/home/akadmin/E4-demos.log` on web01); part D is Ansible-managed and covered by test **T21**.

## A1. A CPU cap really holds (cgroup v2 `cpu.max`)

`sha256sum /dev/zero` as a transient unit, CPU share measured from the cgroup's own accounting (`CPUUsageNSec` delta over 10 s):

| Run | CPU share of the one vCPU |
|---|---|
| no limit | **98%** |
| `systemd-run -p CPUQuota=20%` | **19%** |

```text
cgroup cpu.stat:  nr_throttled 111   throttled_usec 8753121
```

The kernel throttled the process 111 times, for 8.75 s in total, to hold it at 20 ms per 100 ms period. That's the same mechanism as `ak-app.service`'s `CPUQuota=25%` (T08).

## A2. A memory limit really kills (cgroup OOM)

Python asks for 200 MiB inside `MemoryMax=64M` with `MemorySwapMax=0`:

```text
Finished with result: oom-kill
kernel: python3 invoked oom-killer: gfp_mask=0xcc0(GFP_KERNEL), order=0, oom_score_adj=0
kernel: oom-kill:constraint=CONSTRAINT_MEMCG,nodemask=(null),cpuset=/,mems_allowed=0,oom_memcg=/system.slice
kernel: Memory cgroup out of memory: Killed process 1434 (python3) total-vm:441616kB, anon-rss:65236kB, ...
e4-hog.service: Failed with result 'oom-kill'.
```

`constraint=CONSTRAINT_MEMCG` shows the kill came from the **cgroup limit**, not from the host running out of memory. `anon-rss` was 65,236 kB, right at 64 MiB. Only that unit died; the rest of web01 was untouched.

**Side effect, found by the test suite:** the deliberately killed unit stayed `failed`, and the next `verify.sh` failed T15 (`CRIT: failed units: … e4-hog.service`). The health check did its job. The demo now runs `systemctl reset-failed` after the kill. (`dnf-makecache.service` had also failed on its own while the laptop's network was down; reset and re-run: `makecache-OK`.)

## B1. A PID namespace without any container tool

```text
$ unshare --pid --fork --mount-proc /bin/sh -c 'echo "inside: my PID is $$"; ps -o pid,user,comm'
inside: my PID is 1
    PID USER     COMMAND
      1 root     ps
outside, the host has 133 processes
```

## B2. A rootless container is user + 6 other namespaces (podman 5.8.2, run as akdev)

```text
podman top e4demo user huser pid hpid comm
USER        HUSER       PID         HPID        COMMAND
root        1001        1           2792        sleep

lsns -p 2792
        NS TYPE     PID USER  COMMAND
4026532243 user    2755 akdev └─catatonit -P
4026532245 net     2792 akdev sleep 300
4026532304 mnt     2792 akdev sleep 300
4026532305 uts     2792 akdev sleep 300
4026532306 ipc     2792 akdev sleep 300
4026532307 pid     2792 akdev sleep 300
4026532308 cgroup  2792 akdev sleep 300
subordinate id range used for the mapping: akdev:589824:65536
```

**"root" inside the container is UID 1001 (akdev) on the host**, so a breakout gives an unprivileged user, not root. The process is PID 1 inside and 2792 outside, and every namespace is owned by akdev. The container was removed afterwards, and linger was disabled again.

## C. Performance baseline (web01, 1 vCPU)

| State | vmstat `r` | us / sy / id (vmstat) | sar average |
|---|---|---|---|
| idle | 0 | 0–1 / 1–5 / 94–99 | 1.02% user, 2.24% system, **96.75% idle** |
| CPU load (one uncapped `sha256sum`) | 1 | 90–95 / 5–10 / **0** | **92.65% user**, 7.35% system, 0% idle |

Free memory stayed at ~810 MB in both states. `si`/`so` were 0, so there's no swapping.

**Disk (C3): inconclusive.** Two attempts each wrote 400–800 MiB with `dd oflag=direct` to `/srv/app` while `iostat -dxy` sampled. The write finished before or between samples, so `dm-2` (lv_app) shows ~0 `wkB/s`. The likely cause is VirtualBox's host-side cache absorbing writes to the VDI. A meaningful disk baseline in this lab needs `fio` with a time-based job (`--time_based --runtime=30`) rather than a fixed-size `dd`. Recorded as a gap, not as a number.

## D. NFS + autofs (Ansible roles `nfs_server`, `nfs_client`)

| Piece | Where | What |
|---|---|---|
| Export | mon01 `/etc/exports.d/ak.exports` | `/srv/share 192.168.56.11(rw,sync,root_squash,no_subtree_check)`: web01 only; root on web01 becomes nobody |
| Firewall | mon01 ufw | `2049/tcp` from **192.168.56.11 only** (comment "NFSv4 from web01 (E4)") |
| Automount | web01 `/etc/auto.master.d/ak.autofs` + `/etc/auto.ak` | `/nfs/share` → `192.168.56.10:/srv/share`, NFSv4.2, mounted on first access, unmounted after 60 s idle |

Design choice: the guide said `/net/share`, but Rocky's `/etc/auto.master` already maps **`/net` to the built-in `-hosts` map**. A second map on `/net` would conflict, so the share lives under `/nfs`.

| Run | mon01 | web01 |
|---|---|---|
| apply #1 (adds NFS) | changed=7 | changed=5 |
| **apply #2** | **changed=0** | **changed=0** |
| **`verify.sh`** | **24 PASS, 0 FAIL, 0 SKIP**, with the new test | |

```text
PASS T21 web01 /nfs/share automounted from mon01 (192.168.56.10:/srv/share nfs4)
```

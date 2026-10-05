#!/usr/bin/env bash
# e4-demos.sh - E4 A-C on web01: cgroup CPU cap + OOM kill, namespaces, performance baseline.
#   sudo bash ~/ak-infra-lab/tools/e4-demos.sh
# Everything is transient (systemd-run units, a throwaway container) and cleaned up at the end.
# Output goes to the screen and to /home/akadmin/E4-demos.log (readable by akadmin).
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
LOG=/home/akadmin/E4-demos.log
: > "$LOG"; chmod 644 "$LOG"
exec > >(tee "$LOG") 2>&1
step(){ echo; echo "== $* ($(date +%T))"; }

# CPU share of a transient unit over N seconds, from its cgroup's CPU accounting.
cpu_pct(){ # unit seconds
  local u=$1 s=$2 a b
  a=$(systemctl show "$u" -p CPUUsageNSec --value); sleep "$s"
  b=$(systemctl show "$u" -p CPUUsageNSec --value)
  echo $(( (b - a) / (s * 10000000) ))
}

step "host"; uname -r; nproc; free -m | sed -n 2p

# ---------------- A1: CPU cap ----------------------------------------------------------------
step "A1 CPU: sha256sum /dev/zero WITHOUT a limit, 10 s"
systemd-run --quiet --unit=e4-burn-free /usr/bin/sha256sum /dev/zero
sleep 1; free_pct=$(cpu_pct e4-burn-free 10)
echo "uncapped: ${free_pct}% of one CPU"
systemctl stop e4-burn-free

step "A1 CPU: the same with CPUQuota=20%, 10 s"
systemd-run --quiet --unit=e4-burn-cap -p CPUQuota=20% /usr/bin/sha256sum /dev/zero
sleep 1; cap_pct=$(cpu_pct e4-burn-cap 10)
echo "capped:   ${cap_pct}% of one CPU"
echo "cgroup: $(cat /sys/fs/cgroup/system.slice/e4-burn-cap.service/cpu.max)   (quota period, in us)"
grep -E 'nr_throttled|throttled_usec' /sys/fs/cgroup/system.slice/e4-burn-cap.service/cpu.stat
systemctl stop e4-burn-cap
echo "RESULT A1: uncapped ${free_pct}% -> CPUQuota=20% ${cap_pct}%"

# ---------------- A2: memory limit -> OOM kill ----------------------------------------------
step "A2 memory: python asks for 200 MiB inside MemoryMax=64M (no swap allowed)"
systemd-run --wait --unit=e4-hog -p MemoryMax=64M -p MemorySwapMax=0 \
  /usr/bin/python3 -c 'b = bytearray(200*1024*1024); print("allocated - limit did NOT work")'
echo "kernel log:"
journalctl -k --since "-2min" --no-pager -o short-iso | grep -iE 'memory cgroup out of memory|oom-kill|Killed process' | tail -n 3
journalctl -u e4-hog --since "-2min" --no-pager -o cat | grep -iE 'oom|result' | tail -n 3
systemctl reset-failed e4-hog.service 2>/dev/null   # the deliberate OOM leaves a failed unit; healthcheck (T15) would report it

# ---------------- B: namespaces -------------------------------------------------------------
step "B1 unshare: a new PID + mount namespace; the shell inside is PID 1"
unshare --pid --fork --mount-proc /bin/sh -c 'echo "inside: my PID is $$"; ps -o pid,user,comm'
echo "outside, the host has $(ps -e --no-headers | wc -l) processes"

step "B2 rootless podman as akdev (user namespace: root in the container = akdev outside)"
dnf -q -y install podman >/dev/null && rpm -q podman
loginctl enable-linger akdev                       # gives akdev /run/user/<uid> for rootless podman
U=$(id -u akdev)
AK(){ sudo -iu akdev env XDG_RUNTIME_DIR=/run/user/$U "$@"; }
AK podman run -d --name e4demo docker.io/library/alpine:3 sleep 300 >/dev/null \
  && { echo "container started:"; AK podman ps --format '{{.Names}} {{.Image}} {{.Status}}'
       echo "podman top (user = inside, huser = on the host):"; AK podman top e4demo user huser pid hpid comm
       echo "namespaces of the container's process, seen from the host:"
       lsns -p "$(AK podman inspect -f '{{.State.Pid}}' e4demo)" -o NS,TYPE,PID,USER,COMMAND
       echo "subordinate id range used for the mapping: $(grep '^akdev:' /etc/subuid)"
       AK podman rm -f e4demo >/dev/null; }
loginctl disable-linger akdev

# ---------------- C: performance baseline ---------------------------------------------------
step "C1 idle: vmstat 1 5"
vmstat 1 5
step "C1 idle: sar -u 1 5 (average line)"
sar -u 1 5 | tail -n 1

step "C2 CPU load (uncapped sha256sum): vmstat 1 5"
systemd-run --quiet --unit=e4-load /usr/bin/sha256sum /dev/zero
sleep 1; vmstat 1 5
sar -u 1 5 | tail -n 1
systemctl stop e4-load

step "C3 disk load: 800 MiB direct write to /srv/app, one 3 s iostat sample DURING the write"
( dd if=/dev/zero of=/srv/app/.e4-io-test bs=1M count=800 oflag=direct status=none ) &
sleep 1; iostat -dxy 3 1 | grep -E 'Device|sd[a-c]|dm-'      # -y: skip the since-boot report
wait; rm -f /srv/app/.e4-io-test

step "E4 demos done"

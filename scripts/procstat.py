#!/usr/bin/env python3
"""procstat.py - system stats read straight from /proc (standard library only).

Install: /usr/local/bin/procstat.py (0755)
Usage:   procstat.py                 -> JSON report
         procstat.py mem_avail_pct   -> one value (Zabbix item ak.mem.avail_pct)
"""
import json
import os
import sys


def meminfo():
    out = {}
    with open("/proc/meminfo") as f:
        for line in f:
            key, val = line.split(":", 1)
            out[key] = int(val.split()[0])          # values are in kB
    return out


def loadavg():
    with open("/proc/loadavg") as f:
        l1, l5, l15, runnable, _last_pid = f.read().split()
    return {"1m": float(l1), "5m": float(l5), "15m": float(l15), "runnable/total": runnable}


def uptime_hours():
    with open("/proc/uptime") as f:
        return round(float(f.read().split()[0]) / 3600, 1)


def top_rss(n=5):
    procs = []
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            with open(f"/proc/{pid}/status") as f:
                fields = dict(line.split(":", 1) for line in f if ":" in line)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue                                  # process exited or is restricted
        rss_kb = int(fields.get("VmRSS", "0 kB").split()[0])   # kernel threads have no VmRSS
        procs.append((rss_kb, int(pid), fields["Name"].strip()))
    return [{"pid": p, "name": name, "rss_kb": r} for r, p, name in sorted(procs, reverse=True)[:n]]


if __name__ == "__main__":
    m = meminfo()
    report = {
        "mem_avail_pct": round(100 * m["MemAvailable"] / m["MemTotal"], 1),
        "swap_used_kb": m["SwapTotal"] - m["SwapFree"],
        "uptime_h": uptime_hours(),
        "load": loadavg(),
        "top_rss": top_rss(),
    }
    if len(sys.argv) > 1:
        key = sys.argv[1]
        if key not in report:
            sys.exit(f"unknown key {key!r}; choose from: {', '.join(report)}")
        print(report[key])
    else:
        print(json.dumps(report, indent=2))

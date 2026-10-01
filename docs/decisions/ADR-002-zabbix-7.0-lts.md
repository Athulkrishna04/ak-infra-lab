# ADR-002: Zabbix 7.0 LTS, not 8.0

**Status:** accepted · **Date:** 2026-09-29

## Context

Zabbix 8.0 LTS was targeted for Q3 2026, but when the research was done its latest published build was a beta and its docs were marked "development version". Several Indian L1 JDs in the sample named Zabbix or Nagios.

## Decision

Use **Zabbix 7.0 LTS** (server, frontend, agent 2) with MariaDB and nginx on mon01, installed with the exact commands zabbix.com/download shows for *7.0 LTS → Ubuntu 24.04 → Server, Frontend, Agent 2 → MySQL → Nginx*. Agent 2 on web01 comes from the Zabbix repo for Rocky Linux 10. If EPEL is ever enabled, set `excludepkgs=zabbix*` in its repo file.

## Consequences

- The platform is stable, well documented and supported. Tutorials match what's on screen.
- Moving to 8.0 once it's GA and a few minor releases in is enhancement **E5**. It gets its own change record with a snapshot, a DB backup and a rollback step, which is a realistic upgrade story to tell in an interview.

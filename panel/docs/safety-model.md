# Safety Model

Leikwan Panel `2.1.0` keeps the stable Plan safety model and adds a very small readonly task channel.

## Command Classification

```text
readonly
manual
blocked
```

- `readonly`: known safe inspection commands such as `lq status`.
- `manual`: comments and TODO steps that require an operator.
- `blocked`: command text that matches a forbidden pattern and must not be generated.

## Safety Level

```text
safe
caution
dangerous
```

- `safe`: read-only commands and passing preflight.
- `caution`: manual steps, warnings, unknown or offline nodes.
- `dangerous`: blocked command text was detected and removed.

## Readonly Tasks

2.1.0 only allows these task actions:

```text
probe_core_version
run_status
run_status_json
run_doctor
run_doctor_json
list_forwards
ddns_overview
```

Controller queues action names only. Agent maps each action to a fixed argv array and never executes `shell -c`, `bash -c`, `eval`, or a command string from Controller.

`enable_tasks` defaults to `false`, so a node must opt in before polling tasks.

In `2.1.0`, task approval is audit-only. `approve` and `reject` update Controller metadata and timeline; they do not enable write operations.

## Readonly Plan Dry-run

Plan dry-run creates only readonly allowlisted tasks and aggregates their redacted results back into the Plan. It does not execute generated command text.

Dry-run can report `passed`, `warning`, or `failed`, but those states are advisory. They never grant write permission.

## Blocked Patterns

The blocked list includes:

```text
rm
systemctl restart
systemctl stop
nft
iptables
ip route
curl | bash
bash -c
eval
write into /etc
```

If a blocked pattern appears in payload-derived Plan text, the plan becomes `dangerous` and the blocked line is removed from generated commands.

## Why 2.1.0 Still Does Not Write

Readonly tasks are a narrow observability bridge. Future write automation would still need:

- explicit write allowlist
- dry-run
- snapshot confirmation
- rollback path
- audit logs
- operator approval
- scoped permissions

Until those exist, Panel does not modify Leikwan Core, nftables, systemd, EasyTier, DDNS, entries, forwards or PBR.

## 2.1.0 Snapshot / Rollback Safety Framework

Leikwan Panel 2.1.0 adds Plan fields for manual snapshot and rollback metadata plus Safety Gate and verification APIs. The Controller only records operator-provided references and notes. It does not create snapshots, roll back nodes, restart services, or modify Core configuration.

New Plan APIs:

```text
POST /api/v1/plans/:id/snapshot
POST /api/v1/plans/:id/rollback-info
GET  /api/v1/plans/:id/safety-gate
POST /api/v1/plans/:id/verify
```

See `snapshot-rollback-beta.md` and `safety-gate.md`.

## 2.1.0 Write Action Review

Leikwan Panel 2.1.0 adds an Action Catalog and Plan Action Review. This is still non-executing.

Action categories:

```text
readonly
future_write_low
future_write_guarded
future_write_dangerous
blocked
```

Risk levels:

```text
low
medium
high
critical
```

Future write actions such as `create_entry`, `create_forward`, `switch_entry`, `update_ddns_config`, `rollback_config`, and `restart_relay` are visible for review with `enabled=false`.

Blocked actions such as arbitrary commands, `shell -c`, `bash -c`, `eval`, raw `nft`, raw `iptables`, raw `ip route`, `rm`, direct `/etc` writes, and `curl | bash` remain permanently blocked.

`ready_for_future_execution` is always `false` in 2.1.0 because write execution is disabled.

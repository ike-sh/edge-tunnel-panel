# Safety Model

Leikwan Panel `2.1.0-alpha.1` keeps the beta Plan safety model and adds a very small readonly task channel.

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

2.1-alpha.1 only allows these task actions:

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

## Why 2.1-alpha.1 Still Does Not Write

Readonly tasks are a narrow observability bridge. Future write automation would still need:

- explicit write allowlist
- dry-run
- snapshot confirmation
- rollback path
- audit logs
- operator approval
- scoped permissions

Until those exist, Panel does not modify Leikwan Core, nftables, systemd, EasyTier, DDNS, entries, forwards or PBR.

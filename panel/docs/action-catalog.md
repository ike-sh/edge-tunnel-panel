# Action Catalog

Leikwan Panel `2.1.0` exposes a read-only action catalog.

## API

```text
GET /api/v1/action-catalog
GET /api/v1/action-catalog/:action
```

The catalog is metadata only. It never queues tasks and never modifies nodes.

## Readonly Actions

Readonly actions are the only actions Agents can execute when `enable_tasks=true`:

```text
probe_core_version
run_status
run_status_json
run_doctor
run_doctor_json
list_forwards
ddns_overview
```

Each maps to a fixed argv array. The Controller does not send command strings.

## Future Write Actions

Future write actions remain disabled in 2.1.0:

```text
create_entry
create_forward
switch_entry
update_ddns_config
rollback_config
restart_relay
```

Every future write action has:

- `enabled=false`
- `risk_level`
- `required_gates`
- `required_capabilities`
- `snapshot_required`
- `rollback_required`
- `approval_required`

These are design review fields, not execution permission.

## Blocked Actions

Blocked actions are permanently unsafe for Panel execution:

```text
arbitrary_command
shell_c
bash_c
eval
raw_nft
raw_iptables
raw_ip_route
rm
write_etc
curl_pipe_bash
```

Blocked actions are always `enabled=false`.

## Why Command Strings Are Not Accepted

Arbitrary command strings would bypass the safety model, redaction checks, dry-run semantics, rollback design, and the Agent allowlist. Panel APIs therefore accept action names only, and the Agent maps only known readonly action names to fixed argv.

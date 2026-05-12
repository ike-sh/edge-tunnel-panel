# Capabilities

Leikwan Panel `2.1.0` exposes read-only capability metadata for planning and readonly tasks.

## Controller Capabilities

`GET /api/v1/capabilities` returns known command classes:

```text
lq --version                  readonly
lq status                     readonly
lq status --json              readonly
lq doctor                     readonly
lq doctor --json              readonly
lq forward list               readonly
lq ddns overview              readonly
manual TODO steps             manual
readonly allowlisted tasks    readonly
manual snapshot record        manual
manual rollback record        manual
future write tasks            future
```

It also returns:

- `allowed_task_actions`: the 2.1.0 readonly task action list.
- `task_support`: a note that Agents default `enable_tasks=false` and approval is audit-only.
- blocked patterns such as `rm`, `systemctl restart`, `nft`, `iptables`, `ip route`, `curl | bash`, `bash -c`, `eval` and shell writes into `/etc`.
- Action Catalog metadata is exposed separately at `GET /api/v1/action-catalog`.

## Agent-reported Capabilities

Agent reports only locally observed read-only capabilities:

```json
{
  "lq_available": true,
  "core_version": "1.4.0 LTS",
  "supports_status_json": true,
  "supports_doctor_json": true,
  "supports_forward_list": true,
  "supports_ddns_overview": true,
  "enable_tasks": false,
  "supports_snapshot_manual_record": true,
  "supports_rollback_manual_record": true,
  "write_actions_supported": false,
  "supported_write_actions": [],
  "allowed_task_actions": [
    "probe_core_version",
    "run_status",
    "run_status_json",
    "run_doctor",
    "run_doctor_json",
    "list_forwards",
    "ddns_overview"
  ]
}
```

If probing fails, the Agent reports `false` or `missing` and continues.

## Safety Boundary

Capabilities do not grant permission to write. In 2.1.0 they only describe:

- what readonly Core checks are known.
- whether a node has opted into readonly task polling.
- which fixed action names the Agent can map to fixed argv.
- that snapshot and rollback metadata can be recorded manually in the Panel.

They do not enable arbitrary shell commands or configuration changes.

## Readonly Task Lifecycle

Capabilities describe what is safe to request. They do not approve or execute writes. Task cancel, retry, approval, rejection, expiry, and timeline are Controller-side audit lifecycle features for readonly tasks.

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

## 2.1.0 Action Catalog

The Controller publishes Action Catalog metadata:

```text
GET /api/v1/action-catalog
GET /api/v1/action-catalog/:action
```

Readonly actions can be queued as tasks. Future write actions and blocked actions are present for review only and have `enabled=false`.
## Stable Capability Boundary

2.1.0 is the stable Panel release. Capabilities are descriptive only; they do not grant write permission.

# Capabilities

Leikwan Panel `2.1.0-alpha.1` exposes read-only capability metadata for planning and readonly tasks.

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
future write tasks            future
```

It also returns:

- `allowed_task_actions`: the 2.1-alpha.1 readonly task action list.
- `task_support`: a note that Agents default `enable_tasks=false`.
- blocked patterns such as `rm`, `systemctl restart`, `nft`, `iptables`, `ip route`, `curl | bash`, `bash -c`, `eval` and shell writes into `/etc`.

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

Capabilities do not grant permission to write. In 2.1-alpha.1 they only describe:

- what readonly Core checks are known.
- whether a node has opted into readonly task polling.
- which fixed action names the Agent can map to fixed argv.

They do not enable arbitrary shell commands or configuration changes.

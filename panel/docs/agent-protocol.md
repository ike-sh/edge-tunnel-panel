# Leikwan Agent Protocol

Current protocol version: `2.1.0-alpha.1`.

Agent reports local read-only state to Controller. In `2.1.0-alpha.1`, Agent can optionally pull built-in readonly tasks, but it still cannot receive arbitrary command strings and cannot perform writes.

## Authorization

Agent APIs require:

```text
Authorization: Bearer <token>
```

Tokens must never appear in logs, events, raw JSON, frontend pages, task results or Plan output.

## Role Enum

```text
entry
relay
backend
mixed
unknown
```

## Status Enum

```text
online
offline
degraded
```

Use `degraded` when collection partially fails but the Agent can still report.

## Register

```http
POST /api/v1/agent/register
Authorization: Bearer <token>
Content-Type: application/json
```

```json
{
  "node_id": "relay-1",
  "node_name": "relay-1",
  "role": "relay",
  "hostname": "relay-1"
}
```

## Report

```http
POST /api/v1/agent/report
Authorization: Bearer <token>
Content-Type: application/json
```

```json
{
  "node_id": "relay-1",
  "node_name": "relay-1",
  "role": "relay",
  "hostname": "relay-1",
  "public_ip": "203.0.113.10",
  "primary_lan_ip": "10.0.0.10",
  "easytier_ip": "10.198.1.1",
  "agent_version": "2.1.0-alpha.1",
  "core_version": "1.4.0 LTS",
  "status": "online",
  "health_score": 96,
  "interval_seconds": 30,
  "services": {
    "nftables": "active",
    "easytier": "active",
    "leikwan-agent": "active",
    "ddns_timer": "active"
  },
  "capabilities": {
    "lq_available": true,
    "core_version": "1.4.0 LTS",
    "supports_status_json": true,
    "supports_doctor_json": true,
    "supports_forward_list": true,
    "supports_ddns_overview": true,
    "enable_tasks": false,
    "allowed_task_actions": [
      "ddns_overview",
      "list_forwards",
      "probe_core_version",
      "run_doctor",
      "run_doctor_json",
      "run_status",
      "run_status_json"
    ]
  },
  "entries": [],
  "forwards": [],
  "recent_errors": [],
  "errors": []
}
```

## Readonly Task Poll

`enable_tasks` defaults to `false`. When explicitly enabled, Agent polls:

```http
GET /api/v1/agent/tasks?node_id=relay-1
Authorization: Bearer <token>
```

Controller returns only queued tasks for that exact `node_id`.

```json
[
  {
    "id": 1,
    "node_id": "relay-1",
    "action": "run_status_json",
    "status": "picked"
  }
]
```

## Readonly Task Result

```http
POST /api/v1/agent/tasks/1/result
Authorization: Bearer <token>
Content-Type: application/json
```

```json
{
  "status": "succeeded",
  "result_stdout": "{...redacted...}",
  "result_stderr": "",
  "exit_code": 0,
  "error": ""
}
```

Controller redacts and truncates stdout/stderr to 64KB before storing.

## Allowed Task Actions

Actions are names, not commands:

```text
probe_core_version -> lq --version
run_status         -> lq status
run_status_json    -> lq status --json
run_doctor         -> lq doctor
run_doctor_json    -> lq doctor --json
list_forwards      -> lq forward list
ddns_overview      -> lq ddns overview
```

Agent maps action to fixed argv locally. Controller never sends command text.

## Capabilities

Capabilities are discovered only through read-only checks:

- `lq --version`
- `lq status --json`
- `lq doctor --json`
- `lq forward list`
- `lq ddns overview`

Probe failures are reported as `false` or `missing`; they do not crash the Agent.

## Redaction

Controller and Agent redact:

```text
token
secret
password
private_key
privateKey
network_secret
custom_url
custom_cmd
Authorization
```

URL query fields such as `token=`, `key=`, `password=` and `secret=` are also redacted. Bearer tokens become `Bearer REDACTED`.

## Forbidden

The protocol does not include:

- arbitrary command execution
- shell command strings
- configuration writes
- service restarts
- nftables changes
- EasyTier network modification
- DDNS configuration updates
- entries / forwards / PBR modification

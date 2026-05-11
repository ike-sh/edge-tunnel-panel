# Readonly Tasks Alpha

Leikwan Panel `2.1.0-alpha.1` introduces a minimal Agent task system for readonly diagnostics.

## Scope

This release only supports readonly allowlisted tasks. It does not support configuration changes, service restarts, nftables edits, EasyTier changes, DDNS edits, entries/forwards/PBR changes, or arbitrary remote commands.

## Defaults

Agent tasks are disabled by default:

```yaml
enable_tasks: false
task_interval_seconds: 10
task_timeout_seconds: 20
```

Enable tasks only on nodes where you want the Controller to request readonly diagnostics:

```yaml
enable_tasks: true
```

## Supported Actions

Controller accepts only these action names:

```text
probe_core_version
run_status
run_status_json
run_doctor
run_doctor_json
list_forwards
ddns_overview
```

Agent maps them locally to fixed argv:

```text
probe_core_version -> lq --version
run_status         -> lq status
run_status_json    -> lq status --json
run_doctor         -> lq doctor
run_doctor_json    -> lq doctor --json
list_forwards      -> lq forward list
ddns_overview      -> lq ddns overview
```

## No Command Strings

The task API does not accept `command`. Controller sends only an `action`, and Agent rejects any action outside the local allowlist.

Agent does not use `shell -c`, `bash -c`, `eval`, or string concatenation. Each action becomes a fixed executable plus fixed argv.

## Timeout, Redaction and Result Limit

- Each task has a timeout, default 20 seconds.
- stdout, stderr and errors are redacted before upload.
- Controller redacts again before database storage.
- stdout/stderr are limited to the first 64KB.
- Task failure does not stop the Agent's normal status reports.

## API

```http
POST /api/v1/tasks
GET  /api/v1/tasks
GET  /api/v1/tasks/:id
GET  /api/v1/agent/tasks?node_id=...
POST /api/v1/agent/tasks/:id/result
```

Agent endpoints require `Authorization: Bearer <token>`.

## Future Write Automation

Future write operations would require dry-run, snapshot, rollback, approval, strict write allowlists and audit trails. They are not part of 2.1-alpha.1.

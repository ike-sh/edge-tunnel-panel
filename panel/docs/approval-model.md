# Approval Model

Leikwan Panel `2.1.0` adds approval fields for audit only.

## Approval Status

```text
not_required
pending
approved
rejected
```

Readonly tasks default to `not_required`.

## Approval Boundary

Approving a task does not enable write operations. Rejecting a task only records audit state and prevents normal pickup when the task is still queued.

Controller still does not send command strings. Agent still maps action names to fixed readonly argv and never runs `shell -c`, `bash -c`, or `eval`.

Plan dry-run also remains readonly: it queues only allowlisted diagnostic tasks and records a redacted `dry_run_report`.

## Future Writes

Future write automation would need all of these before it can be considered:

- explicit operator approval
- dry-run output
- automatic snapshot
- rollback path
- strict write allowlist
- bounded timeout
- full audit timeline

None of those write paths are active in `2.1.0`.

## Why Command Strings Are Rejected

Free-form command strings are impossible to audit safely in this model. They could hide shell expansion, pipes, redirection, or destructive commands. The task API therefore accepts only action names from the readonly allowlist.

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

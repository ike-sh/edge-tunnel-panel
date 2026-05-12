# Write Action Review

Leikwan Panel `2.1.0` adds a write action review framework. It does not execute write actions.

## What It Does

Action Review maps a Plan type to a future write action and reports:

- matched action
- risk level
- required gates
- missing gates
- required capabilities
- whether the action is enabled
- why future execution is not available

`ready_for_future_execution` is always `false` in `2.1.0`.

```text
write execution is disabled in 2.1.0
```

## APIs

```text
GET  /api/v1/plans/:id/action-review
POST /api/v1/plans/:id/action-review
```

Both forms only return the review result. They do not:

- create Agent tasks
- modify nodes
- generate command strings
- change Plan execution state
- write nftables, systemd, EasyTier, DDNS, entries, forwards or PBR

## Categories

```text
readonly
future_write_low
future_write_guarded
future_write_dangerous
blocked
```

Future write actions are cataloged for design review only and have `enabled=false`.

## Risk Levels

```text
low
medium
high
critical
```

`switch_entry`, `rollback_config`, and raw command-like actions are high or critical risk.

## Required Gates

Future write actions can require:

- dry-run
- approval
- snapshot
- rollback
- verification
- maintenance-window

These gates are visible for review, but passing them does not enable write execution in 2.1.0.

## Safety Boundary

Before any future write support exists, it must still satisfy dry-run, approval, snapshot, rollback, verification, redaction, audit timeline, and a strict allowlist. The Controller still does not send arbitrary commands and the Agent still does not execute writes.

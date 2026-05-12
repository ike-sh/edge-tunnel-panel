# Leikwan Panel 2.1.0 Stable

Leikwan Panel 2.1.0 is the stable safety-control release for the Panel line. Leikwan Toolkit 1.4.x remains the Shell Core / LTS path for real forwarding behavior. The Panel observes, audits and prepares manual plans; it does not modify node configuration.

## Scope

2.1.0 includes:

- Controller / Agent architecture
- Node heartbeat and status reporting
- Readonly node inventory, entries and forwards views
- Readonly allowlisted tasks
- Task lifecycle with cancel, retry, TTL, timeline and result limits
- Manual Plan execution guides
- Plan dry-run using readonly tasks
- Manual snapshot / rollback metadata
- Safety Gate
- Action Catalog
- Write Action Review
- Operator Auth and strict-auth mode

## Safety Boundary

2.1.0 does not:

- execute write operations
- create write tasks
- accept arbitrary command strings
- send commands from Controller to Agent
- add, delete or modify forwards
- switch public entries
- restart relay
- create snapshots
- run rollback
- modify nftables, systemd, EasyTier, DDNS, entries, forwards or PBR
- modify `leikwan-toolkit.sh` or Shell Core behavior

Future write actions remain visible only as disabled catalog entries with `enabled=false`.

## Controller Deployment

The Controller can run on a dedicated management host:

```bash
export LEIKWAN_CONTROLLER_TOKEN='agent-token'
export LEIKWAN_OPERATOR_TOKEN='operator-token'
leikwan-controller --listen 0.0.0.0:18080 --db ./data/controller.db
```

Use `--strict-auth` when every Web API except `/api/v1/health` should require the Operator token.

## Agent Deployment

Agents run on A public entry nodes, B relay nodes and optional C backend nodes. Agents connect outward to the Controller and report local read-only state.

```bash
leikwan-agent --config /etc/leikwan-agent/config.yml
```

`enable_tasks` defaults to `false`. If enabled, the Agent only executes built-in readonly task actions mapped to fixed argv arrays.

## Operator Auth

- `LEIKWAN_CONTROLLER_TOKEN`: Agent register/report/tasks/result token.
- `LEIKWAN_OPERATOR_TOKEN`: Web and operator API token.

The tokens are not interchangeable. Events and timelines store only operator fingerprints, not full tokens.

## Known Limits

2.1.0 is intentionally conservative. It provides manual plans, dry-run reports and audit metadata, but it does not apply changes. Operators must still SSH to the target node and use Leikwan Core manually for any real configuration change.

## Path to 2.2.0

2.2.0 may explore a very small set of whitelist write operations, but only after dry-run, snapshot, rollback, approval, verification and audit requirements are satisfied. Arbitrary command strings and raw shell execution remain out of scope.

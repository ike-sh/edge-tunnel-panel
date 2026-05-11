# Plans Beta

Leikwan Panel `2.0.0-beta.2` is the manual execution guide stage.

Plans are still safe by design:

- Controller stores drafts and generates text only.
- Agent does not pull tasks.
- Agent does not execute commands.
- No node system is modified by the Panel.
- Leikwan Core files, nftables, systemd, EasyTier, DDNS, entries, forwards and PBR remain untouched.

## Plan Types

```text
create_entry
create_forward
switch_entry
ddns_check
```

- `create_entry`: draft manual steps for adding an A public entry.
- `create_forward`: draft manual steps for adding a forward target.
- `switch_entry`: conservative inspection guide for a possible entry switch.
- `ddns_check`: read-only DDNS inspection guide.

## Plan Status

```text
draft
generated
copied
archived
```

## Manual Execution Status

```text
not_run
running_manually
succeeded
failed
rolled_back
```

These fields are audit notes only. Marking a plan as `succeeded`, `failed` or `rolled_back` never changes a node.

## Generated Artifacts

When a plan is generated, Controller stores:

- `generated_commands`: backward-compatible flat command list.
- `command_groups`: commands grouped by node.
- `checklist`: manual verification checklist.
- `markdown`: a redacted execution guide.
- `warnings`: risk notes.

The Markdown guide always states:

```text
This plan is manual-only. The agent will not execute it.
```

## Allowed Commands

Generated command text may include read-only checks:

```bash
lq --version
lq status
lq status --json
lq doctor
lq doctor --json
lq forward list
lq ddns overview
```

If Leikwan Core does not expose a stable non-interactive CLI for an operation, Panel writes a `# TODO` manual step instead of inventing a command.

## Forbidden Commands

Plans must not generate:

```text
rm
systemctl restart
nft
iptables
curl | bash
eval
bash -c
direct writes into /etc
```

## Redaction

Plan payload, generated commands, Markdown, events and raw JSON are redacted for:

```text
token
secret
password
privateKey
network_secret
custom_url
custom_cmd
Authorization
```

## Why Not Automatic Execution Yet

Automatic execution needs a permission model, allowlisted tasks, review, audit logs, rollback handling and explicit operator approval. These are out of scope before 2.1.


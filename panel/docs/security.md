# Security

## Tokens

- `EDGE_OPERATOR_TOKEN` is used by Web and operator APIs.
- `EDGE_CONTROLLER_TOKEN` is used by Agents.
- Keep both tokens secret and rotate them if exposed.

## Agent Action Boundary

Agent tasks are fixed actions only. Dangerous payload keys are rejected:

- `command`
- `cmd`
- `shell`
- `script`
- `raw_nft`
- `raw_iptables`
- `raw_ip_route`

Write actions require `EDGE_ENABLE_WRITE_ACTIONS=true`.

## Redaction

The Agent redacts controller tokens, bearer headers, token query values, and token-like JSON fields from results, stdout, stderr, and errors.

## Root Privileges

Controller and Agent examples run as root because systemd management, nftables, routing policy, and service files require privileged operations on Linux.

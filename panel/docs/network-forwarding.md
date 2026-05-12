# Network Forwarding

## Entry

An Entry represents a public listening range on a node:

- `node_id`
- `listen_ip`
- `listen_port_start`
- `listen_port_end`
- `protocol`
- optional `domain`
- optional DDNS config

## Forward

A Forward maps one public port to a target:

- `entry_node_id`
- `protocol`
- `listen_port`
- `target_mode`
- `target_host`
- `target_port`

## Local Target

Use `target_mode=local` when the target is reachable from the Entry node without the overlay.

## Overlay Target

Use `target_mode=overlay` when the target is reachable through EasyTier.

## nftables Output

Agent writes structured forwarding config to:

- `/etc/edge-tunnel/agent/forward.json`
- `/etc/edge-tunnel/agent/nftables/edge-tunnel-forward.nft`

The Agent never accepts raw nftables payloads from tasks.

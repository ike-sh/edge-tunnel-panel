# PBR

Policy Based Routing lets a node steer selected traffic through a specific routing table, gateway, or interface.

## Model

A PBR policy can match:

- source CIDR
- destination CIDR
- protocol
- mark

And can apply:

- table id
- gateway
- output interface
- priority

## Files

Agent writes:

- `/etc/edge-tunnel/agent/pbr.json`
- `/etc/edge-tunnel/agent/pbr-apply.sh`

The script is generated from structured policy fields. Raw routing payloads are rejected.

## Requirements

PBR requires root privileges and Linux `iproute2`. Test rules carefully on remote hosts to avoid locking yourself out.

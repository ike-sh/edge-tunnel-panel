# Topology

## Direct Forwarding

Client traffic reaches a public Entry node. The Entry node forwards TCP/UDP traffic to a target on the same host or a directly reachable LAN address.

```text
Client -> Public Entry Node -> Local target service
```

Use `target_mode=local` for this mode.

## Overlay Forwarding

Client traffic reaches a public Entry node. The Entry node forwards traffic through EasyTier to a backend node or overlay address.

```text
Client -> Public Entry Node -> EasyTier overlay -> Backend Node -> Target service
```

Use `target_mode=overlay` for this mode.

## Node Roles

- `entry`: public ingress node that listens for client traffic.
- `relay`: overlay helper node for connectivity.
- `exit`: node that can route selected traffic out.
- `backend`: private service node behind NAT.

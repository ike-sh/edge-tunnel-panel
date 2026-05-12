# Quick Start

## Install Controller

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash
```

The installer creates:

- `/usr/local/bin/edge-tunnel-controller`
- `/etc/edge-tunnel/controller/controller.env`
- `/var/lib/edge-tunnel/controller`
- `/var/lib/edge-tunnel/controller/web`
- `edge-tunnel-controller.service`

## Join an Agent

Use the Web **Add Agent** page or run:

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | sudo bash -s -- \
  --controller-url http://YOUR_CONTROLLER:18080 \
  --token YOUR_AGENT_TOKEN \
  --node-name edge-node-1 \
  --role entry \
  --enable-tasks \
  --enable-write-actions
```

## First Web Flow

1. Save the Operator Token in **Login / Token**.
2. Confirm the Agent in **Nodes**.
3. Create a **Network Profile** with a CIDR such as `10.144.0.0/16`.
4. Apply the Network Profile to the Agent node.
5. Create an **Entry** on a public node.
6. Create a **Forward** for TCP or UDP.
7. Apply the Forward and watch **Tasks**.

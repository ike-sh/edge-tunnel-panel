# Edge Tunnel Panel

Edge Tunnel Panel is a Web controller and Agent system for building TCP/UDP tunnel networks with EasyTier. It is designed for hosts that do not have a public IPv4 address and need one or more public entry servers to expose services through direct forwarding or overlay forwarding.

## Use Cases

- Backend servers behind NAT with only a mapped SSH port.
- Public entry servers forwarding TCP/UDP traffic to local or overlay targets.
- Multi-node EasyTier networks with entry, relay, exit, and backend roles.
- Central Web management for nodes, network profiles, entries, forwards, PBR policies, DDNS settings, and tasks.

## Architecture

- **Controller**: Go HTTP API, JSON file storage, task scheduler, Agent bootstrap command generator, and static Web server.
- **Agent**: Go daemon installed on entry, relay, exit, or backend nodes. It reports status, polls fixed tasks, and applies structured configs.
- **Web**: React + Vite management UI for login, nodes, Add Agent, Network Profiles, Entries, Forwards, PBR, Tasks, and Settings.
- **EasyTier**: Overlay network layer managed by Agent config.
- **nftables**: Forwarding rule backend generated from structured Forward configs.
- **PBR**: Linux routing policy generated from structured PBR configs.
- **DDNS**: Entry/Node integrated config capability for dynamic address updates.

## Quick Start

Install Controller:

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash
```

Install an Agent:

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | sudo bash -s -- \
  --controller-url http://YOUR_CONTROLLER:18080 \
  --token YOUR_AGENT_TOKEN \
  --node-name edge-node-1 \
  --role entry \
  --enable-tasks \
  --enable-write-actions
```

## Web Flow

1. Open the Controller URL and save the Operator Token.
2. Use **Add Agent** to generate an Agent install command.
3. Confirm new nodes in **Nodes**.
4. Create a **Network Profile** and apply it to selected nodes.
5. Create an **Entry** on a public node.
6. Create a **Forward** for TCP or UDP traffic.
7. Add **PBR** policies when traffic needs a specific routing table or gateway.
8. Track task execution in **Tasks**.

## Forwarding Modes

- **Single-node direct forwarding**: the Entry node forwards traffic to a local target host and port.
- **Multi-node tunnel forwarding**: the Entry node forwards traffic to a target node or overlay address through EasyTier.

## Default Paths

| Purpose | Path |
| --- | --- |
| Controller binary | `/usr/local/bin/edge-tunnel-controller` |
| Agent binary | `/usr/local/bin/edge-tunnel-agent` |
| Controller config | `/etc/edge-tunnel/controller` |
| Agent config | `/etc/edge-tunnel/agent` |
| Controller data | `/var/lib/edge-tunnel/controller` |
| Agent state | `/var/lib/edge-tunnel/agent` |
| Logs | `/var/log/edge-tunnel` |
| Controller service | `edge-tunnel-controller.service` |
| Agent service | `edge-tunnel-agent.service` |
| EasyTier service | `edge-tunnel-easytier.service` |

## Security Boundary

- Agent does not accept arbitrary shell commands.
- Agent only accepts fixed actions from an allowlist.
- Dangerous payload keys are rejected: `command`, `cmd`, `shell`, `script`, `raw_nft`, `raw_iptables`, `raw_ip_route`.
- Tokens are redacted from task output and error strings.
- Task result size is limited by the Agent.
- Write actions are disabled unless `EDGE_ENABLE_WRITE_ACTIONS=true`.

## Development Validation

```bash
cd panel/controller
gofmt -w .
go test ./... -v -count=1 -timeout=30s

cd ../agent
gofmt -w .
go test ./... -v -count=1 -timeout=30s

cd ../..
npm --prefix panel/controller/web ci
npm --prefix panel/controller/web run build

bash -n panel/scripts/*.sh
bash panel/scripts/build-release.sh
```

## Current Limits

- This is the first MVP for online testing.
- EasyTier auto-download is intentionally conservative and can be enhanced later.
- DDNS currently focuses on safe config landing and provider integration points.
- PBR requires Linux root privileges plus `iproute2` and `nftables`.

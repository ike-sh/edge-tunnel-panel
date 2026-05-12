# Leikwan Toolkit

Leikwan Toolkit Shell Core is frozen at `1.4.0 LTS`.

Leikwan Toolkit is a TCP/UDP forwarding toolkit for an **A public entry + B relay host + C backend target** topology. The Shell Core remains responsible for local forwarding behavior: EasyTier, nftables, DDNS, PBR, snapshots and maintenance.

## Core Quick Start

```bash
curl -fsSL -o /tmp/lq-bootstrap.sh https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/main/scripts/bootstrap.sh && bash /tmp/lq-bootstrap.sh
lq init
```

Common Core commands:

```bash
lq init
lq status
lq --doctor
lq ddns overview
lq forward apply-relay --auto-fix-route
lq update check
```

## Leikwan Panel 2.1.0 Stable

Leikwan Panel `2.1.0` is the stable safety-control plane. It provides Controller / Agent / Web UI for observation, readonly diagnostics, manual planning and audit metadata.

It supports Controller / Agent, node heartbeat, readonly status reports, readonly Tasks, Plan manual execution, Plan dry-run, Snapshot / Rollback metadata, Safety Gate, Action Catalog, Write Action Review, Operator Auth and strict-auth.

It does **not** execute write operations, create write tasks, accept command strings, add/delete/modify forwards, switch public entries, restart relay, create snapshots, run rollback, or modify nftables, systemd, EasyTier, DDNS, entries, forwards or PBR.

## Leikwan Panel 3.0.0-alpha.4

`3.0.0-alpha.4` is a real-apply alpha for lab testing. It can install/configure EasyTier, write Panel-managed nftables/PBR/DDNS config, reload Panel firewall rules and queue fixed node actions when an operator explicitly enables `enable_write_actions=true` on that Agent.

This alpha is for testing the end-to-end Panel flow:

1. Install Controller.
2. Open Web Panel.
3. Login / unlock with the Operator token.
4. Open `添加节点` and copy the generated Agent install command.
5. Run that command on A/B VPS nodes.
6. Create a Network profile.
7. Create an Entry.
8. Create a Forward.
9. Apply and watch Tasks.

Controller one-click install:

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/panel-3-alpha/panel/scripts/install-controller.sh | sudo bash
```

Alpha 阶段默认使用 `panel-3-alpha` 分支。如果 GitHub Release 包已经上传，脚本会优先下载 release 包；如果 release 包不存在，脚本会 fallback 到同一 `source-ref` 的源码构建。源码构建会安装 `go`、`npm`、`nodejs`，耗时会更长；上传 release tarball 后安装会快很多。

Agent one-click join:

Open Web Panel -> `添加节点`, choose the node role and copy the generated command. A full command looks like:

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/panel-3-alpha/panel/scripts/install-agent.sh | sudo bash -s -- \
  --controller-url http://PANEL_HOST:18080 \
  --token AGENT_TOKEN \
  --node-name relay-1 \
  --role relay \
  --enable-tasks \
  --enable-write-actions
```

Alpha write actions are fixed allowlisted actions only. They do not accept command strings, do not run `shell -c`, do not run `bash -c`, do not run `eval`, and do not expose raw nft / iptables / ip route operations. The landing/backend machine does **not** need an Agent; it is configured as `target_host:target_port`.

Still disabled or blocked:

- `create_entry`
- `create_forward`
- `switch_entry`
- `rollback_config`
- `restart_relay`
- arbitrary commands
- raw shell
- raw nft / iptables / ip route

## Deployment Model

- Controller can run on a dedicated management host.
- Agents run on A public entry and B relay nodes.
- C backend/landing machines do not need Agents.
- Agents connect outward to Controller.
- Controller outage does not affect existing Core forwarding.
- `LEIKWAN_CONTROLLER_TOKEN` is for Agents.
- `LEIKWAN_OPERATOR_TOKEN` is for Web / Operator APIs.
- Agent token and Operator token are intentionally not interchangeable.

## Documentation

Panel docs live under `panel/docs/`:

- `quickstart.md`
- `install-controller.md`
- `install-agent.md`
- `network-forwarding.md`
- `pbr.md`
- `ddns.md`
- `security.md`
- `release-3.0-alpha.md`

## Panel Local Development

Controller:

```bash
cd panel/controller
go test ./...
go run ./cmd/leikwan-controller --listen 127.0.0.1:18080 --db ./data/controller.db --web-dir ./web/dist
```

Agent:

```bash
cd panel/agent
go test ./...
go run ./cmd/leikwan-agent --config ./agent.yml --once
```

Web:

```bash
cd panel/controller
npm --prefix web install
npm --prefix web run build
```
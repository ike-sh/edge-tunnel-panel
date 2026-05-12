# Leikwan Toolkit

当前 Core 版本：`1.4.0 LTS`

Leikwan Toolkit 是一个 **A 公网入口 + B 中转主机 + C 后端目标** 的 TCP/UDP 转发组网工具。

1.4.x 是 Shell Core / LTS：负责真实转发、EasyTier、nftables、DDNS、PBR、快照和本机维护。后续只做 bugfix、兼容性修复、安全修复和文档维护。

## 适用场景

典型链路：

```text
外部客户端 -> A 公网入口 -> EasyTier -> B 利群主机 -> C 后端目标
```

核心用途：

- 多公网入口接入
- 中转主机统一转发
- TCP/UDP 同时转发
- 可选 PBR 出口策略
- 可选 DDNS 自动刷新
- 可选配置备份 / 自更新

不做：

- Web 面板直接修改 Core 配置
- 多用户权限系统
- 自动负载均衡控制面
- 复杂监控平台
- DNS 服务商完整 SDK
- 代理协议客户端生成器

## 快速安装

```bash
curl -fsSL -o /tmp/lq-bootstrap.sh https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/main/scripts/bootstrap.sh && bash /tmp/lq-bootstrap.sh
lq init
```

常用 Core 命令：

```bash
lq init
lq status
lq --doctor
lq ddns overview
lq forward apply-relay --auto-fix-route
lq update check
```

## Leikwan Panel 2.1.0 Stable

Leikwan Panel 2.1.0 是安全控制面稳定版。它提供 Controller / Agent / Web UI，用于观察节点状态、审计人工操作、生成手动执行计划和运行只读诊断任务。

2.1.0 支持：

- Controller / Agent
- 节点心跳
- 只读状态上报
- 只读 Tasks
- Task lifecycle
- Plan manual execution
- Plan dry-run
- Snapshot / Rollback metadata
- Safety Gate
- Action Catalog
- Write Action Review
- Operator Auth

2.1.0 明确不支持：

- 不执行写操作
- 不自动新增、删除、修改转发
- 不自动切换公网入口
- 不自动 restart relay
- 不自动创建快照
- 不执行回滚
- 不接受 command 字符串
- 不修改 `leikwan-toolkit.sh`
- 不修改 nftables / systemd / EasyTier / DDNS / entries / forwards / PBR

推荐部署模型：

- Controller 可以部署在独立管理服务器。
- Agent 部署在 A/B/C 节点。
- Agent 主动连接 Controller。
- Controller 挂了不影响已有 Core 转发。

Token 区分：

- `LEIKWAN_CONTROLLER_TOKEN` 给 Agent 使用。
- `LEIKWAN_OPERATOR_TOKEN` 给 Web / Operator API 使用。

未来 2.2.0 以后才考虑极少量白名单写操作实验，并且必须建立在 dry-run、approval、snapshot、rollback、verification 和审计链路之上。

## Panel 本地运行

Controller：

```bash
cd panel/controller
go test ./...
go run ./cmd/leikwan-controller --listen 127.0.0.1:18080 --db ./data/controller.db
```

Agent：

```bash
cd panel/agent
go test ./...
go run ./cmd/leikwan-agent --config ./agent.yml --once
```

Web：

```bash
cd panel/controller
npm --prefix web install
npm --prefix web run build
```

发布包：

```bash
bash panel/scripts/build-release.sh
```

输出：

```text
panel/dist/leikwan-controller
panel/dist/leikwan-agent
panel/dist/web/
panel/dist/docs/
panel/dist/examples/
panel/dist/SHA256SUMS
```

## 文档索引

Core 文档：

- [最终使用手册](docs/final-guide.md)
- [CLI 参考](docs/cli.md)
- [组网流程](docs/workflow.md)
- [DDNS](docs/ddns-refresh.md)
- [安全说明](docs/security.md)
- [故障排查](docs/troubleshooting.md)
- [验收测试](docs/acceptance-test.md)

Panel 文档：

- [Panel 2.1.0 Release Notes](panel/docs/release-2.1.0.md)
- [Operator Auth](panel/docs/operator-auth.md)
- [Agent Protocol](panel/docs/agent-protocol.md)
- [Readonly Tasks](panel/docs/tasks-alpha.md)
- [Task Lifecycle](panel/docs/task-lifecycle.md)
- [Plan Dry-run](panel/docs/dry-run-alpha.md)
- [Plans](panel/docs/plans-beta.md)
- [Manual Execution](panel/docs/manual-execution.md)
- [Snapshot / Rollback Metadata](panel/docs/snapshot-rollback-beta.md)
- [Safety Gate](panel/docs/safety-gate.md)
- [Action Catalog](panel/docs/action-catalog.md)
- [Write Action Review](panel/docs/write-action-review.md)
- [Capabilities](panel/docs/capabilities.md)
- [Controller 安装](panel/docs/install-controller.md)
- [Agent 安装](panel/docs/install-agent.md)
- [systemd 示例](panel/docs/systemd.md)

## Release

Core release：

```text
leikwan-toolkit-1.4.0.tar.gz
leikwan-toolkit-1.4.0.tar.gz.sha256
```

Panel 2.1.0 release files are generated under `panel/dist/`.

# Leikwan Toolkit

当前版本：`1.3.1`

## 项目简介

Leikwan Toolkit 是一个面向多公网入口场景的快速组网与四层转发管理工具。它使用 EasyTier 连接公网入口和利群主机，并用 nftables 管理 TCP/UDP 业务转发。

典型链路：

```text
外部客户端 -> A 公网入口端口 -> EasyTier -> B 利群主机 -> C 后端目标
```

多公网入口的 PRIMARY / BACKUP 只用于推荐、排序和输出展示，不是 B 侧自动负载均衡。真正的自动负载均衡应由客户端、DNS 或外部 LB 实现。

## 核心能力

- 多公网入口接入、启用禁用、PRIMARY / BACKUP 切换
- TCP+UDP EasyTier peer 展开和 A/B 双侧 DNAT
- 转发目标、端口池、端口冲突预检和推荐避让
- IPv4 PBR、forward 来源 PBR、域名 PBR
- DDNS 刷新：后端目标、公网入口域名、PBR 域名
- 状态总览、doctor 诊断、状态缓存和脱敏 debug report
- 状态 / doctor JSON 摘要、运行锁状态和最近错误提示
- 配置快照 / 回滚，高危操作前自动快照
- 普通卸载 / 深度卸载，深度卸载前 final snapshot
- 日志查看 / 清理命令中心
- 配置导入 / 导出 / 迁移包，含 full / redacted 两种模式
- 转发端点分享输出：TXT / TSV / JSON / HTML / 可选 QR
- GitHub Release 自更新、sha256 校验和安全回滚
- 本地回归测试和 release 验证入口

## 快速安装

```bash
curl -fsSL -o /tmp/lq-bootstrap.sh https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/main/scripts/bootstrap.sh && bash /tmp/lq-bootstrap.sh
lq init
```

安装后入口：

```text
/root/leikwan-toolkit.sh
/usr/local/bin/lq
/usr/local/bin/LQ
```

查看版本：

```bash
lq --version
```

首次部署、重装恢复或不确定当前机器角色时，优先执行 `lq init`。它会先让你选择 B 利群主机、A 公网入口、从配置包恢复或仅检查状态。

## 三机角色说明

- A：公网入口，可部署多台，负责接收外部 TCP/UDP 流量。
- B：利群主机 / 中转主机，运行 EasyTier relay、nftables 转发和 PBR。
- C：后端目标，接收 B 转发来的业务流量。

常见端口：

- EasyTier 组网端口：默认 `8301`、`8302`、`8303`，建议位于 `8000-9000`。
- 业务入口端口：常用 `10001-19999`，A 侧端口池会 TCP+UDP DNAT 到 B。
- 后端目标端口：由用户填写。

## 快速组网流程

推荐按 B -> A -> B -> A -> B 执行：

1. B：修复 DNS / IPv4。
2. B：生成公网入口网络码。
3. A：粘贴网络码部署入口。
4. B：粘贴 A 返回码完成接入。
5. A：配置公网入口端口池。
6. B：添加后端转发目标。
7. B：执行 `lq status` 或 `lq --doctor` 检查。

进入交互菜单：

```bash
lq
```

菜单动作输出会停留，按回车返回。配对码输出需要输入 `y` 返回，输入 `r` 重显，输入 `p` 显示保存路径。

## 常用命令

```bash
lq init
lq init --dry-run
lq plan
lq status
lq status --json
lq --status
lq --status-json
lq --doctor
lq doctor --json
lq port check
lq --port-check
lq forward list
lq forward apply-relay --auto-fix-route
lq pbr show
lq pbr sync-from-forwards
lq pbr domain list
lq pbr domain sync
lq ddns status
lq ddns run --scope all
lq update check
lq update run
lq logs
lq logs ddns
```

配置导入 / 导出：

```bash
lq config export --full
lq config export --redacted
lq config inspect /root/leikwan-config-YYYYMMDD-HHMMSS.tar.gz
lq config import /root/leikwan-config-YYYYMMDD-HHMMSS.tar.gz
lq config list
```

端点输出：

```bash
lq output generate
lq output show
lq output json
lq output html
lq output qr
```

本地 release 验证：

```bash
bash scripts/verify-release.sh
```

## 功能模块

`init` 是首次初始化向导，`wizard` 和 `quickstart` 是别名。`lq init --dry-run` / `lq plan` 只输出计划，不写文件、不启动服务、不应用 nftables / PBR。主菜单和运维命令中心会把状态、诊断、端口预检、端点输出、配置导入导出、DDNS 和自更新聚合到更短路径。

`status` 是轻量日常总览：读取配置、状态缓存、systemd 状态和 nftables 表，不做大规模探测，也不自动修改系统。`doctor` 是详细诊断，适合部署后或故障时运行。

`status --json` / `--status-json` 和 `doctor --json` / `--doctor-json` 输出轻量 JSON 摘要，适合脚本读取，不包含 EasyTier secret。

配置快照位于 `/etc/leikwan-toolkit/snapshots/`，自动快照位于 `/etc/leikwan-toolkit/snapshots/auto/`。删除入口、删除转发目标、重新应用转发规则、恢复快照、配置导入等高危操作前会自动快照。

配置导出分为 full 和 redacted。full 包可迁移和恢复运行；redacted 包用于排错和 issue，不含可恢复 EasyTier 网络的 secret。导入前会 inspect、校验 sha256、校验 manifest、检查 tar 安全边界并自动快照。

端点输出位于 `/etc/leikwan-toolkit/outputs/`，用于分享 TCP/UDP 入口，不是代理链接，不包含 EasyTier secret 或配对码。

卸载分普通卸载和深度卸载。普通卸载只移除服务、规则和快捷命令，保留 `/etc/leikwan-toolkit`、快照、配置包和备份；深度卸载会删除配置、状态和运行日志，并先生成 final snapshot。

## 安全说明

- 配对码、完整快照、full config 包都可能包含 EasyTier network secret。
- redacted config 包和 debug report 会脱敏，但发送前仍建议人工快速检查。
- config import 会拒绝路径穿越、绝对路径以及 symlink / hardlink 包成员。
- 自更新只使用 GitHub Release 包，并校验 `.sha256`。
- `lq output *` 只输出端点信息，不输出 secret、token 或 password。
- 高危写操作使用 `/run/leikwan-*.lock` 锁；stale lock 会在下次获取锁时自动清理。

## 故障排查

```bash
lq status
lq --doctor
lq port check
lq ddns status
lq update status
```

如果 TCP/UDP DNAT 缺失，可在维护窗口执行：

```bash
nohup lq forward apply-relay --auto-fix-route >/root/lq-apply-relay.log 2>&1 &
tail -f /root/lq-apply-relay.log
```

如果公网入口 DDNS 变化，默认只记录 `relay restart needed`，不会自动重启 relay。可在维护窗口通过菜单重启 relay。

## 文档索引

- [工作流](docs/workflow.md)
- [初始化向导](docs/init-wizard.md)
- [运维命令中心](docs/operations-center.md)
- [DDNS 自动刷新](docs/ddns-refresh.md)
- [PBR](docs/pbr.md)
- [配置迁移](docs/config-migration.md)
- [端点输出](docs/endpoint-output.md)
- [卸载](docs/uninstall.md)
- [日志](docs/logs.md)
- [自更新](docs/self-update.md)
- [状态 / 快照 / 端口预检](docs/status-snapshot-port-check.md)
- [安全边界](docs/security.md)
- [测试与验收](docs/testing.md)
- [故障排查](docs/troubleshooting.md)
- [验收清单](docs/acceptance-test.md)

## Release

Release 包名：

```text
leikwan-toolkit-1.3.1.tar.gz
leikwan-toolkit-1.3.1.tar.gz.sha256
```

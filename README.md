# Leikwan Toolkit

当前版本：`1.4.0 LTS`

Leikwan Toolkit 是一个 **A 公网入口 + B 中转主机 + C 后端目标** 的 TCP/UDP 转发组网工具。

1.4.0 LTS 是功能冻结版。后续版本主要只做 bug fix、兼容性修复、安全修复和文档完善，不再扩展大功能。

## 适用场景

适合这样的链路：

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

- Web 面板
- 多用户权限系统
- 自动负载均衡控制面
- 复杂监控平台
- DNS 服务商完整 SDK
- 代理协议客户端生成器

## 三台机器角色

- **A 公网入口**：接收外部 TCP/UDP 流量，可以有多台。
- **B 利群主机**：中转和转发中心，管理公网入口、转发目标、PBR 和 nftables。
- **C 后端目标**：最终被访问的服务。

多公网入口的 PRIMARY / BACKUP 只用于排序、展示和端点输出，不是自动负载均衡控制面。

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

## 快速组网

如果你只是要用，按这个顺序：

1. 安装
2. 执行 `lq init`
3. B 生成接入码
4. A 粘贴接入码
5. B 粘贴 A 返回码
6. B 添加转发目标
7. 使用输出的端点

交互主菜单已经收敛为 6 个入口：

```text
1. 快速组网
2. 利群主机 B
3. 公网入口 A
4. DDNS
5. 状态 / 诊断
6. 高级维护
0. 退出
```

连接码输出仍支持：

- `y`：确认返回
- `r`：重显
- `p`：显示保存路径

## 常用命令

首页只列最常用命令，其它兼容 CLI 见 [CLI 参考](docs/cli.md)。

```bash
lq init
lq status
lq --doctor
lq ddns overview
lq forward apply-relay --auto-fix-route
lq update check
```

## DDNS 简明说明

DDNS 分成两端：

- **A 端 DDNS**：让域名指向 A 当前公网 IP。
- **B 端 DDNS**：发现域名变化后刷新转发 / PBR / relay 状态。

如果 A 的域名已经由路由器、云厂商客户端或其它外部 DDNS 客户端维护，可以不启用 `lq entry ddns`。

常用检查：

```bash
lq ddns overview
lq ddns check-consistency
lq ddns apply-entries
```

公网入口 DDNS 变化后，B 端默认不会自动重启 relay。需要在维护窗口确认后执行：

```bash
lq ddns apply-entries
```

## 故障排查

日常先看：

```bash
lq status
```

需要详细检查：

```bash
lq --doctor
```

常见修复：

```bash
lq doctor --auto-fix
lq forward apply-relay --auto-fix-route
lq port check
lq logs
```

## 升级与卸载

自更新：

```bash
lq update check
lq update run
lq update status
```

卸载在菜单中：

```text
高级维护 -> 卸载
```

普通卸载保留配置、快照和备份；深度卸载会删除配置和状态，执行前会生成 final snapshot 并二次确认。

## Leikwan Panel 2.0.0-alpha.3

`1.4.x` 是 Shell LTS / Leikwan Core，后续只做 bugfix、兼容性、安全和文档维护。

`2.0.0-alpha.3` 是只读 Web Panel 的部署和拓扑体验增强版：

- Controller / Agent 架构
- Agent 只采集本机状态并上报
- Controller 只保存和展示节点、入口、转发、事件
- 新增节点详情、历史上报、Topology、Bootstrap/Add Agent 和 systemd 示例
- 不会修改现有转发配置
- 不会远程执行任意命令

详细说明见 [Panel 2.0-alpha 文档](panel/docs/panel-2.0-alpha.md)。

## 文档索引

- [最终版使用手册](docs/final-guide.md)
- [CLI 参考](docs/cli.md)
- [推荐工作流](docs/workflow.md)
- [DDNS 自动刷新](docs/ddns-refresh.md)
- [A 端 DDNS](docs/entry-ddns.md)
- [PBR](docs/pbr.md)
- [配置迁移](docs/config-migration.md)
- [端点输出](docs/endpoint-output.md)
- [状态输出](docs/status.md)
- [doctor 诊断](docs/doctor.md)
- [安全边界](docs/security.md)
- [故障排查](docs/troubleshooting.md)
- [测试与验收](docs/testing.md)
- [验收清单](docs/acceptance-test.md)
- [Release Notes](docs/release-notes.md)

## Release

Release 包名：

```text
leikwan-toolkit-1.4.0.tar.gz
leikwan-toolkit-1.4.0.tar.gz.sha256
```

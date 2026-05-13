# 开发验证

## Controller

```bash
cd panel/controller
gofmt -w .
go test ./... -v -count=1 -timeout=30s
```

## Agent

```bash
cd panel/agent
gofmt -w .
go test ./... -v -count=1 -timeout=30s
```

## Web

```bash
npm --prefix panel/controller/web ci
npm --prefix panel/controller/web run build
```

## Release

```bash
bash -n panel/scripts/*.sh
VERSION=v0.2.3-test bash panel/scripts/build-release.sh
```

## v0.2.3-test 重点

- 添加节点改为紧凑卡片式接入流程，不再让用户选择节点角色。
- 组网配置收敛为“快速组网”主流程，并生成组网卡片。
- NetworkLink 记录入口节点、后端节点、任务、Peer、延迟、丢包、隧道和路由。
- EasyTier ExecStart 增加 `-d` 和 `-i CIDR`，并解析虚拟 IP。
- 新增转发规则 MVP：Controller CRUD、Web 表单、Agent 生成 nftables 文件。
- `apply_forward_config` 先执行 `nft -c` 检查，再执行 `nft -f` 加载。
- `verify_forward_rules` 可检查 nftables table、规则和 IPv4 forwarding 状态。

## 后续规划

- 多端口池转发。
- 转发规则批量启停。
- 转发状态和流量统计。
- 更完整的 DDNS provider。
- PBR 策略可视化和验证。
- 节点分组、权限和多面板对接。

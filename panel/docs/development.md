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
VERSION=v0.2.6-test bash panel/scripts/build-release.sh
```

## v0.2.6-test 重点

- 修复 Web 卡片、命令、JSON 和任务输出的溢出问题。
- 快速组网应用后由 Web 自动延迟触发验证任务。
- NetworkLink 状态回写为 applying、verifying、active、failed、disabled。
- 转发规则支持后端落地地址来源：后端虚拟 IP、后端内网 IP、手动地址。
- `apply_forward_config` 增加端口冲突预检和 IPv4 目标校验。
- ForwardRule 状态会根据 apply/verify 任务结果回写。

## 后续规划

- 多端口池转发。
- 转发规则批量启停。
- 转发状态和流量统计。
- 更完整的 DDNS provider。
- PBR 策略可视化和验证。
- 节点分组、权限和多面板对接。

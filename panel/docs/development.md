# 开发说明

当前版本：`v0.2.7-test`

## 本地验证

```bash
cd panel/controller
go test ./... -v -count=1 -timeout=30s

cd ../agent
go test ./... -v -count=1 -timeout=30s

cd ../..
npm --prefix panel/controller/web ci
npm --prefix panel/controller/web run build

VERSION=v0.2.7-test bash panel/scripts/build-release.sh
```

## 当前重点

- 节点接入使用卡片式流程。
- 快速组网自动生成 A/B 两侧配置并自动验证。
- 转发规则绑定组网链路。
- 转发规则使用双阶段模型：A 侧入口转发 + B 侧落地转发。
- 任务页展示 nft 预检错误和生成内容。

## 后续规划

- 多端口池转发。
- 转发规则批量启停。
- 转发状态和流量统计。
- 更完整的 PBR 可视化。
- 节点分组和规则分组。
- 限速、配额和告警。

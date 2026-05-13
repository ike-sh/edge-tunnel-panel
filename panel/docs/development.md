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
VERSION=v0.1.4-test bash panel/scripts/build-release.sh
```

## 后续规划

参考同类转发面板的产品思路，后续计划增强：

- 节点管理体验增强
- 隧道/转发规则管理
- 端口转发 / 隧道转发两种模式
- 转发规则批量启停
- 节点批量下发
- TCP/UDP 转发状态检查
- 隧道/转发流量统计
- 转发规则分组
- 节点分组
- 分组权限
- 限速/配额
- 节点分享或多面板对接
- 动态最优路径

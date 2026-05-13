# Development

当前版本：`v0.2.10-test`

## 验证命令

```bash
cd panel/controller && go test ./... -v -count=1 -timeout=30s
cd ../agent && go test ./... -v -count=1 -timeout=30s
cd ../..
npm --prefix panel/controller/web ci
npm --prefix panel/controller/web run build
VERSION=v0.2.10-test bash panel/scripts/build-release.sh
```

## 近期方向

- PBR domain/static 来源接入域名同步。
- 转发规则批量启停。
- 更完整的流量统计和链路诊断。
- MSS/MTU 自动探测更智能化。

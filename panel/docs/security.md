# 安全说明

## Token

- `EDGE_OPERATOR_TOKEN`：Web/API 操作员 Token。
- `EDGE_CONTROLLER_TOKEN`：Agent 接入主控使用的 Token。

两类 Token 不应混用，也不要写入公开日志。

## Agent 边界

Agent 只接受固定 action，不接受任意命令字符串。危险字段会被拒绝：

- `command`
- `cmd`
- `shell`
- `script`
- `raw_nft`
- `raw_iptables`
- `raw_ip_route`

## 写入动作

启用 `EDGE_ENABLE_WRITE_ACTIONS=true` 后，Agent 可以写入 EasyTier、转发、PBR、DDNS 配置。只应在可信服务器启用。

## 权限

安装脚本和 systemd 示例默认使用 root，因为 nftables、路由策略和服务管理都需要系统权限。

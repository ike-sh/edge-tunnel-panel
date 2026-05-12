# DDNS 动态域名

Leikwan Panel `3.0.0-alpha.4` 支持基础 DDNS Profile，并通过固定 Agent action 应用和同步。

## Provider

- `cloudflare`
- `generic_webhook`
- `manual`

## API Token 安全

`api_token` 只用于被控端同步。前端、日志、events、task result 和 raw_json 都应脱敏显示。

## Apply / Sync

- Apply 创建 `apply_ddns_config` 任务。
- Sync now 创建 `ddns_sync_now` 任务。
- `manual` provider 只检测公网 IP，不更新 DNS。

## 限制

不支持任意 shell，不支持用户自定义命令。generic webhook 只使用固定 HTTP 请求逻辑。
# Leikwan Agent Protocol 2.0-alpha

本协议用于 Leikwan Agent 向 Controller 注册和上报状态。2.0-alpha 只有 Agent -> Controller 的状态上报，不包含 Controller -> Agent 的配置下发或命令执行。

## Authorization

注册和上报接口都需要：

```text
Authorization: Bearer <token>
```

token 来自 Controller 的 `--token` 或 `LEIKWAN_CONTROLLER_TOKEN`。日志中不得打印完整 token。

## Role 枚举

```text
entry
relay
backend
mixed
unknown
```

无法识别时必须使用 `unknown`，不要猜测。

## Status 枚举

```text
online
offline
degraded
```

Agent 本机采集部分失败但仍能上报时使用 `degraded`。例如 `lq` 缺失、`lq status --json` 失败、public IP 获取失败。

## Register 请求

```http
POST /api/v1/agent/register
Authorization: Bearer <token>
Content-Type: application/json
```

```json
{
  "node_id": "relay-1",
  "node_name": "relay-1",
  "role": "relay",
  "hostname": "relay-1"
}
```

响应：

```json
{
  "status": "ok",
  "node_id": "relay-1"
}
```

## Report 请求

```http
POST /api/v1/agent/report
Authorization: Bearer <token>
Content-Type: application/json
```

```json
{
  "node_id": "relay-1",
  "node_name": "relay-1",
  "role": "relay",
  "hostname": "relay-1",
  "public_ip": "203.0.113.10",
  "primary_lan_ip": "10.0.0.10",
  "easytier_ip": "10.198.1.1",
  "agent_version": "2.0.0-alpha.1",
  "core_version": "1.4.0 LTS",
  "status": "online",
  "health_score": 96,
  "services": {
    "nftables": "active",
    "easytier": "active"
  },
  "entries": [],
  "forwards": [],
  "errors": []
}
```

响应：

```json
{
  "status": "ok",
  "node_id": "relay-1"
}
```

## Collector 规则

Agent 只允许采集只读状态：

- hostname
- public IP，失败时为 `unknown`
- primary LAN IP
- `lq --version`
- `lq status --json`
- `lq doctor --json`
- `systemctl is-active nftables`
- `systemctl is-active easytier...`

如果 `lq` 不存在：

- `core_version = "missing"`
- `status = "degraded"`
- 继续上报，不退出

## Redaction 规则

Controller 和 Agent 都必须在日志、events、raw_json 入库前脱敏以下字段：

```text
token
secret
password
private_key
privateKey
network_secret
custom_url
custom_cmd
Authorization
```

字符串中的 URL query 也要脱敏：

```text
token=...
key=...
password=...
secret=...
```

Bearer token 输出必须变成：

```text
Bearer REDACTED
```

## 禁止项

2.0-alpha 协议不包含：

- 命令执行
- 配置写入
- 服务重启
- nftables 应用
- EasyTier 网络修改
- DDNS 更新配置下发
- entries / forwards / PBR 修改

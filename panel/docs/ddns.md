# DDNS

DDNS 在 Edge Tunnel Panel 中作为节点或公网入口的内置配置能力，不作为独立主菜单功能。

当前 MVP 重点是组网和转发链路，DDNS 配置会通过固定 action 写入结构化配置文件：

- `/etc/edge-tunnel/agent/ddns.json`

安全要求：

- Token 不在任务输出中明文展示。
- 不接受任意 shell 或脚本。
- 后续可扩展 Cloudflare、Webhook 等 provider。

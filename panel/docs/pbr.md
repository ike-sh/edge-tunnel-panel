# 出口策略 PBR

PBR 用于让指定流量走特定路由表、网关或网卡。

## 配置字段

- 匹配源地址
- 匹配目标地址
- 协议
- mark
- 路由表 ID
- 网关
- 出口网卡
- 优先级

## 落地文件

- `/etc/edge-tunnel/agent/pbr.json`
- `/etc/edge-tunnel/agent/pbr-apply.sh`

脚本由结构化字段生成，不接受 raw ip route payload。

## 风险

PBR 会影响服务器路由，请先在测试节点验证，避免远程失联。

# PBR

PBR 用于在节点上按源地址、目标地址、协议、mark、路由表和网关控制出口路径。

当前 MVP 只保留结构化配置和验证基础：

- 配置文件：`/etc/edge-tunnel/agent/pbr.json`
- 应用脚本：`/etc/edge-tunnel/agent/pbr-apply.sh`

安全边界：

- 不接受 raw `ip route` payload。
- 不执行任意命令字符串。
- 写入动作必须来自固定 action。

后续会在转发链路稳定后增强 PBR 可视化和回滚能力。

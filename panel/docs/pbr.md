# PBR

PBR 是出口策略能力，当前版本只保留结构化配置和验证基础。

路径：

```text
/etc/edge-tunnel/agent/pbr.json
/etc/edge-tunnel/agent/pbr-apply.sh
```

安全边界：

- 不接受 raw `ip route` payload。
- 不执行任意命令字符串。
- 写入动作必须来自固定 action。

后续会在转发链路稳定后增强 PBR 可视化、回滚和诊断能力。

# PBR 出口策略

Leikwan Panel `3.0.0-alpha.4` 提供简单 PBR 策略模型，用于测试 relay 节点上的出口路由配置。

## 字段

- name
- relay_node_id
- source_cidr
- target_cidr
- output_interface
- gateway
- table_id
- priority
- mark

## Apply

点击 Apply 后，Controller 只会创建固定 action：

```text
apply_pbr_rules
```

Agent 会校验 CIDR、interface、table_id、priority 等字段。它不接受 raw `ip rule` 或 raw `ip route` 字符串。

## 当前限制

这是 alpha 测试实现，建议先在测试 VPS 上验证。修改出口策略可能影响现有连接。
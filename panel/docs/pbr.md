# 出口策略 / PBR

PBR 主要用于 B 落地节点具备多出口线路的场景。面板先让 Agent 识别线路组，再让用户选择线路，不需要手动填写出口接口或网关。

## 流程

1. 转发规则先跑通。
2. 选择 B 落地节点。
3. 点击“识别出口线路”。
4. 选择 9929 / CN2 / JPSDWAN / DESDWAN / KRSDWAN 等检测到的线路组。
5. 选择转发规则。
6. 创建并应用策略。
7. 验证策略。

如果没有检测到线路组，说明当前节点不适合创建 PBR。

## 行为

Agent 会写入 `/etc/iproute2/rt_tables`，执行固定 argv 的 `ip route replace`、`ip rule add`，并生成 `table ip edge_tunnel_pbr` 用于 mark 转发流量。

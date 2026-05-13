# PBR

PBR 是“出口策略”能力，用于 B 落地执行节点上的转发流量出口选择。它主要面向具备多出口线路的节点，不是所有普通服务器都适合启用。

## 推荐流程

1. 添加节点。
2. 快速组网。
3. 创建并应用转发。
4. 进入“出口策略 / PBR”。
5. 选择 B 落地节点。
6. 点击“识别出口线路”。
7. 从检测结果中选择线路组，例如 `CN2`、`9929` 或 `JPSDWAN`。
8. 选择该 B 节点上的转发规则。
9. 点击“创建并应用策略”。
10. 验证策略。

如果没有检测到线路组，页面会提示当前节点不建议创建 PBR。

## 线路组

Agent 的 `detect_pbr_route_groups` 会扫描本机 IPv4 地址，并匹配内置线路定义：

- `9929`：网关 `10.7.0.1`，匹配 `10.7.*`
- `CN2`：网关 `10.8.0.1`，匹配 `10.8.*`
- `JPSDWAN`：网关 `10.3.0.1`，匹配 `10.3.0.*` 到 `10.3.3.*`
- `DESDWAN`：网关 `10.3.10.1`
- `KRSDWAN`：网关 `10.4.0.1`
- `HKSDWAN` / `TWSDWAN` / `SEATTLE` / `MOSCOW` / `SINGAPORE` / `USSDWAN-LAX`

识别到线路后，Controller 会自动带出 `gateway`、`table_id`、`table_name`、`priority` 和 `fwmark`。

## v0.3.0-ui-test 限制

- 每个节点只支持一条启用中的 PBR 策略。
- 完整支持 `source_type=forward`。
- `domain` 和 `static` 保留模型，后续接入域名同步。
- 不支持 IPv6 PBR。
- 不接受 raw nft、raw route 或任意 shell 命令。

## Agent 落地文件

```text
/etc/edge-tunnel/agent/pbr.d/{policy_id}.json
/etc/edge-tunnel/agent/nftables/edge-tunnel-pbr.nft
/etc/iproute2/rt_tables
```

## 验证命令

```bash
ip rule show
ip route show table 101
nft list table ip edge_tunnel_pbr
```

# PBR

PBR 是“出口策略”能力，用于 B 落地执行节点上的转发流量出口选择。

## 推荐流程

1. 添加节点。
2. 快速组网。
3. 创建并应用转发。
4. 进入“出口策略 / PBR”。
5. 选择 B 落地节点。
6. 识别网卡。
7. 选择转发规则。
8. 选择出口接口和网关。
9. 创建并应用策略。
10. 验证策略。

## v0.2.9-test 限制

- 每个节点只支持一条启用中的 PBR 策略。
- 完整支持 `source_type=forward`。
- `domain` 和 `static` 保留模型，后续接入域名同步。
- 不支持 IPv6 PBR。
- 不接受 raw nft、raw route 或任意 shell 命令。

## Agent 落地文件

```text
/etc/edge-tunnel/agent/pbr.d/{policy_id}.json
/etc/edge-tunnel/agent/nftables/edge-tunnel-pbr.nft
```

## 验证命令

```bash
ip rule show
ip route show table 20000
nft list table ip edge_tunnel_pbr
```

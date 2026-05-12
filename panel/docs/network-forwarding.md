# 网络转发

## 公网入口

公网入口定义节点上的监听地址、端口范围、协议、域名和 DDNS 配置。

## 转发规则

转发规则定义公网端口到目标服务的映射：

- `target_mode=local`：入口节点本地或可直连地址。
- `target_mode=overlay`：通过 EasyTier overlay 到后端节点。

## 落地文件

Agent 写入：

- `/etc/edge-tunnel/agent/forward.json`
- `/etc/edge-tunnel/agent/nftables/edge-tunnel-forward.nft`

Agent 不接受 raw nftables payload，只根据结构化配置生成规则。

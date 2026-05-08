# v0.4 架构：EasyTier + nftables

v0.4 是 breaking change。主流程只保留 EasyTier 组网和 nftables 四层转发。

## 角色

- `cloud-entry`：有公网地址的入口机，暴露 `ENTRY_PORT`。
- `leikwan-relay`：利群主机，连接入口机并转发到后端目标。
- `target/upstream`：用户自备任意 TCP 服务，脚本不部署、不校验协议。

## 链路

```text
客户端 -> cloud-entry:ENTRY_PORT
cloud-entry nftables -> 10.198.1.1:ENTRY_PORT
EasyTier 虚拟网络
leikwan-relay nftables -> TARGET_HOST:TARGET_PORT
```

## 默认地址

| 节点 | EasyTier IP |
| --- | --- |
| relay | `10.198.1.1` |
| aliyun | `10.198.1.2` |
| tencent | `10.198.1.3` |
| home | `10.198.1.4` |

## 边界

脚本只理解 TCP 入口、EasyTier peer、nftables DNAT/SNAT 和 PBR。后端服务的协议、证书、认证和应用日志都由用户自行维护。

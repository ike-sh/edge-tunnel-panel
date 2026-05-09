# EasyTier 快速配对

快速配对只需要复制两段码。

## 1. B 生成网络码

在 `leikwan-relay`：

```bash
sudo lq pair relay-init
```

复制：

```text
-----BEGIN LEIKWAN EASYTIER NETWORK-----
...
-----END LEIKWAN EASYTIER NETWORK-----
```

也可以复制一行 `LEIKWAN_EASYTIER_NETWORK_BASE64=...`。

生成网络码前，脚本会读取现有 `entries.tsv` 并推荐唯一的公网入口名称、EasyTier IP 和 `8000-9000` 内监听端口。已有第一台入口时，第二台通常推荐：

```text
SUGGESTED_ENTRY_NAME=home
SUGGESTED_ENTRY_ET_IP=10.198.1.3
SUGGESTED_EASYTIER_PROTOCOLS=tcp,udp
SUGGESTED_EASYTIER_TCP_PORT=8302
SUGGESTED_EASYTIER_UDP_PORT=8302
SUGGESTED_EASYTIER_PROTOCOL=tcp
SUGGESTED_EASYTIER_PORT=8302
```

新字段 `SUGGESTED_EASYTIER_PROTOCOLS` 优先，默认是 `tcp,udp`。旧网络码如果只有 `SUGGESTED_EASYTIER_PROTOCOL=tcp` 和 `SUGGESTED_EASYTIER_PORT=8301`，A 侧会继续按 TCP-only 部署。

## 2. A 粘贴网络码并部署入口

在 `cloud-entry`：

```bash
sudo lq pair entry-join
```

粘贴 B 的整段网络码。脚本会把网络码里的 `SUGGESTED_ENTRY_NAME`、`SUGGESTED_ENTRY_ET_IP`、`SUGGESTED_EASYTIER_PROTOCOLS`、`SUGGESTED_EASYTIER_PORT` 作为默认值，允许修改，但会校验 EasyTier IP 非空、TCP/UDP 监听端口位于 `8000-9000`。

默认提示是：

```text
EasyTier 传输模式 [tcp+udp]:
EasyTier 监听端口（TCP+UDP，同端口，白名单 8000-9000） [8301]:
```

支持输入 `tcp+udp`、`dual`、`both`、`tcp,udp`、`tcp` 或 `udp`。`tcp+udp` 会让 A 的 `easytier-core` 同时监听 `tcp://0.0.0.0:PORT` 和 `udp://0.0.0.0:PORT`。

完成后复制：

```text
-----BEGIN LEIKWAN EASYTIER ENTRY-----
...
-----END LEIKWAN EASYTIER ENTRY-----
```

ENTRY 码会写入新旧字段：

```text
EASYTIER_PROTOCOLS=tcp,udp
EASYTIER_TCP_PORT=8301
EASYTIER_UDP_PORT=8301
EASYTIER_PROTOCOL=tcp
EASYTIER_PORT=8301
```

B 侧优先读取 `EASYTIER_PROTOCOLS`。旧 ENTRY 码如果只有 `EASYTIER_PROTOCOL=tcp`，仍保持 TCP-only peer。

## 3. B 粘贴入口码并接入

在 `leikwan-relay`：

```bash
sudo lq pair relay-join
```

粘贴 A 的入口码。脚本会写入 `entries.tsv`，协议字段允许 `tcp`、`udp` 或 `tcp,udp`。`tcp,udp` 会展开为两个 peer：`tcp://PUBLIC_HOST:PORT` 和 `udp://PUBLIC_HOST:PORT`。

## 非交互导入

```bash
cat /root/network.env | sudo lq pair entry-join -
cat /root/entry.env | sudo lq pair relay-join -
```

配对码不会包含系统私钥。网络密钥会保存在本机配置中，公开故障报告前必须脱敏。

## 端口说明

快速配对会从 `8301` 起自动寻找未使用端口，例如 `8301`、`8302`、`8303`。这是为了让 EasyTier TCP 和 UDP 连接都落在利群推荐 `8000-9000` 白名单端口段。TCP 和 UDP 默认使用同一个 EasyTier 端口。

EasyTier 组网端口不是业务入口端口。`8301` 用于 A/B EasyTier peer 建链；`10001` 这类业务入口端口用于外部客户端访问转发服务，需要在安全组或路由器上按实际端口开放 TCP+UDP。如果 UDP 不通，TCP 仍可工作；如果 TCP 受限，UDP 可能更稳定。

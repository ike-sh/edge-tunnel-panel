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
SUGGESTED_EASYTIER_PORT=8302
```

## 2. A 粘贴网络码并部署入口

在 `cloud-entry`：

```bash
sudo lq pair entry-join
```

粘贴 B 的整段网络码。脚本会把网络码里的 `SUGGESTED_ENTRY_NAME`、`SUGGESTED_ENTRY_ET_IP`、`SUGGESTED_EASYTIER_PORT` 作为默认值，允许修改，但会校验 EasyTier IP 非空、端口位于 `8000-9000`。

完成后复制：

```text
-----BEGIN LEIKWAN EASYTIER ENTRY-----
...
-----END LEIKWAN EASYTIER ENTRY-----
```

## 3. B 粘贴入口码并接入

在 `leikwan-relay`：

```bash
sudo lq pair relay-join
```

粘贴 A 的入口码。脚本会写入 `entries.tsv`、重启 relay 服务，并检查 peer 和 ping。

## 非交互导入

```bash
cat /root/network.env | sudo lq pair entry-join -
cat /root/entry.env | sudo lq pair relay-join -
```

配对码不会包含系统私钥。网络密钥会保存在本机配置中，公开故障报告前必须脱敏。

## 端口说明

快速配对会从 `8301` 起自动寻找未使用端口，例如 `8301`、`8302`、`8303`。这是为了让 EasyTier TCP 连接落在利群推荐 `8000-9000` 白名单端口段。

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

## 2. A 粘贴网络码并部署入口

在 `cloud-entry`：

```bash
sudo lq pair entry-join
```

粘贴 B 的整段网络码。脚本只会询问公网 IP 或域名，可直接回车使用自动探测值。

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

快速配对默认输出 `SUGGESTED_EASYTIER_PORT=8301`，入口码默认输出 `EASYTIER_PORT=8301`。这是为了让 EasyTier TCP 连接落在利群推荐 `8000-9000` 白名单端口段。

如果导入旧配对码发现端口是 `11010`，脚本会默认建议自动改为 `8301`。

# 工作流

v0.4 推荐只走 EasyTier 快速配对。

## 1. relay 生成网络码

在利群中转机：

```bash
sudo lq pair relay-init
```

输出 `LEIKWAN EASYTIER NETWORK` 配对码，复制整段到公网入口机。

## 2. entry 部署入口

在公网入口机：

```bash
sudo lq pair entry-join
```

粘贴 relay 网络码。脚本会：

- 安装或复用 EasyTier。
- 创建 `easytier-entry-<name>.service`。
- 监听 `tcp/8301`。
- 保存本机入口信息。
- 输出 `LEIKWAN EASYTIER ENTRY` 入口码。

## 3. relay 接入入口

回到利群中转机：

```bash
sudo lq pair relay-join
```

粘贴 entry 入口码。脚本会：

- 写入 `entries.tsv`。
- 重写并启动 `easytier-relay.service`。
- 检查 EasyTier peer 和 ping。

## 4. A 配置入口端口池

A 公网入口机只需要配置一次：

```bash
sudo lq entry expose-range --range 10000-19999 --relay-ip 10.198.1.1
```

这会让 A 把 `10000-19999/tcp` 全部 DNAT 到 B 的 EasyTier IP，并保持原端口不变。

安全组需要放行：

- `tcp/8301`：EasyTier。
- `tcp/10000-19999`：入口端口池。

如果只想暴露少量端口，可以改成：

```bash
sudo lq entry expose-range --range 10001-10020 --relay-ip 10.198.1.1
```

## 5. B 添加转发目标

推荐使用快速转发，不要手写 TSV。

B 利群中转机：

```bash
sudo lq forward add
```

示例：

```text
name=hk
entry_port=10001
target_host=203.0.113.30
target_port=30004
route_table=T_CN2
enabled=true
```

新增、修改、删除后端都只在 B 上操作：

```bash
sudo lq forward add
sudo lq forward edit hk
sudo lq forward delete hk
sudo lq forward apply-relay
```

## 6. 应用 nftables

`lq entry expose-range` 会自动应用 A 侧入口端口池。`lq forward add/edit/delete` 会自动应用 B 侧 relay nftables。高级用户也可以手动进入：

```text
高级功能 -> 转发目标管理 -> 应用 nftables 规则
```

## 7. 查看入口清单

```bash
sudo lq
```

选择：

```text
查看转发入口
```

生成文件：

```text
/etc/leikwan-wg-toolkit/outputs/forward-endpoints.txt
```

只会显示 `public_host:entry_port`，不会生成任何后端协议链接。

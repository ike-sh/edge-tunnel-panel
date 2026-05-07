# forwards.tsv

转发目标是任意 TCP 后端。脚本只需要知道入口端口和后端地址。

路径：

```text
/etc/leikwan-wg-toolkit/forwards/forwards.tsv
```

格式是 **8 列 TAB 分隔**，不是空格对齐：

```text
name  entry_port  target_host     target_port  out_iface  route_table  enabled  comment
hk    10001       203.0.113.30    30004        eth1       T_CN2        true     hk-target
jp    10002       target.example  30004                   T_9929       true     jp-target
```

默认推荐用快速转发，不要手写 TSV。v0.4 的新转发模型是：

- A 公网入口机只配置一次入口端口池。
- B 利群中转机负责所有后端目标的新增 / 修改 / 删除 / 应用。
- A 不需要知道每个 `target_host` / `target_port`。

A 公网入口机先执行一次：

```bash
sudo lq entry expose-range --range 10000-19999 --relay-ip 10.198.1.1
```

这会把 `10000-19999/tcp` 全部 DNAT 到 `10.198.1.1`，保持原端口。

B 利群中转机添加后端：

```bash
sudo lq forward add
```

以后只在 B 上管理：

```bash
sudo lq forward edit hk
sudo lq forward delete hk
sudo lq forward list
sudo lq forward apply-relay
```

菜单入口：

```text
主菜单 -> 快速转发
```

`forward import` 只保留为 legacy / 高级兼容，不再是默认流程。

手写 `forwards.tsv` 只适合高级用户，并且只应该在 B relay 上维护。如果必须命令行写入，请用 `printf` 明确输出 TAB，不要手工用空格排版：

```bash
sudo install -d -m 700 /etc/leikwan-wg-toolkit/forwards
{
  printf '# name\tentry_port\ttarget_host\ttarget_port\tout_iface\troute_table\tenabled\tcomment\n'
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    'hk' '10001' '203.0.113.30' '30004' 'eth1' 'T_CN2' 'true' 'hk-target'
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    'jp' '10002' 'target.example' '30004' '' 'T_9929' 'true' 'jp-target'
} | sudo tee /etc/leikwan-wg-toolkit/forwards/forwards.tsv >/dev/null
```

写坏成 `hk10001203.0.113.3030004truehk-target` 这类“粘在一起”的内容时，脚本会停止解析并拒绝应用 nftables，避免生成空转发表。

字段说明：

- `name`：转发目标名称。
- `entry_port`：公网入口端口，必须唯一。
- `target_host`：后端 IP 或域名。
- `target_port`：后端 TCP 端口。
- `out_iface`：可选出口接口。
- `route_table`：可选 PBR 表，例如 `T_CN2`。
- `enabled`：`true` 或 `false`。
- `comment`：备注。

保留端口如 `22`、`80`、`443`、`8301` 默认会要求二次确认。

域名解析结果写入：

```text
/etc/leikwan-wg-toolkit/forwards/resolved.tsv
```

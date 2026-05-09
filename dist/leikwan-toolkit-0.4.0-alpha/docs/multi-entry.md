# 多公网入口

多入口用于同时管理多台 A 公网入口，例如云入口、家宽入口或备用入口。

它不是自动负载均衡。外部客户端连接哪台 A，就从哪台 A 进入；B 侧不会把已经进入某个 A 的连接迁移到另一台 A。`weight` 用于排序和 PRIMARY / BACKUP 推荐，不代表自动按权重分流。

## 正确流程

不要把“手动添加公网入口”当成部署新 A 的小白流程。新增第二台公网入口时：

1. B 执行 `快速组网 -> 2`，生成新公网入口网络码。
2. 新 A 执行 `快速组网 -> 3`，粘贴网络码并部署本机入口。
3. 新 A 执行 `快速组网 -> 5`，配置入口端口池。
4. B 执行 `快速组网 -> 4`，粘贴 A 返回码。
5. B 进入 `利群主机 -> 公网入口列表管理` 查看 / 测试。

B 生成网络码时会读取 `entries.tsv` 并自动推荐唯一值：

```text
第一台：aliyun  10.198.1.2  tcp+udp/8301
第二台：home    10.198.1.3  tcp+udp/8302
第三台：entry3  10.198.1.4  tcp+udp/8303
```

旧 TCP-only 入口不会被自动改写；只有新生成的入口默认使用 TCP+UDP。

如果连续生成两份入口码但第一份还没有接回 B，脚本会用 pending reservation 避免重复推荐：

```text
/etc/leikwan-toolkit/entries/pending-entries.tsv
```

pending 字段为 `name et_ip protocols port created_at`。后续推荐会同时排除已保存入口和 pending 入口；ENTRY 返回码接入后，对应 pending 自动删除。若存在超过 24 小时的 pending，脚本会提示清理。

## entries.tsv

路径：

```text
/etc/leikwan-toolkit/entries/entries.tsv
```

格式：

```text
entry_name  public_host      et_ip        easytier_protocol  easytier_port  weight  enabled
aliyun      192.0.2.10       10.198.1.2   tcp,udp            8301           100     true
home        home.example.com 10.198.1.3   tcp                8302           100     true
entry3      198.51.100.20    10.198.1.4   udp                8303           50      false
```

要求：

- `entry_name` 唯一。
- `et_ip` 唯一。
- `easytier_protocol` 允许 `tcp`、`udp`、`tcp,udp`；列表显示会把 `tcp,udp` 显示成 `tcp+udp`。
- `easytier_port` 是 EasyTier 组网端口，TCP/UDP 都校验在 `8000-9000`，且唯一。
- `public_host` 可以是 IP 或域名。
- `enabled=false` 不参与输出和测试。

删除、启用/禁用、修改权重、测试入口都会先展示列表，支持编号或名称选择。

relay service 渲染 peer 时会展开多协议入口：`tcp,udp` 写成 `tcp://host:port` 和 `udp://host:port` 两个 peer；旧 `tcp` 行仍只生成 TCP peer。

## 变更应用

公网入口列表里的手动添加、修改详情、删除、启用/禁用、修改权重以及粘贴 ENTRY 返回码，都会先写入 `entries.tsv`，再询问是否重启 relay。默认不重启，避免误中断现有入口。

修改详情可切换 `tcp`、`udp`、`tcp+udp`。例如把 `aliyun` 从 `tcp,udp` 改成 `tcp` 并立即应用后，relay service 只保留 `tcp://host:8301`；改回 `tcp+udp` 后会重新生成 TCP 和 UDP 两个 peer。

## 主备策略

`切换主公网入口` 有两种模式：

- 只启用一个入口：用于手动切换，应用 relay 后只保留该入口 peer。
- 保留其它入口 enabled：用于主备推荐，选中入口会提高权重并在输出清单中标记 PRIMARY，其它 enabled 入口标记 BACKUP。

`批量启用 / 禁用公网入口` 可以启用全部、禁用全部，或只保留一个入口 enabled。禁用全部会导致 relay 没有公网入口 peer，脚本会二次确认。

`generate_forward_outputs` 和 doctor 使用同一排序：enabled entries 按 weight 降序、同权重按名称排序；第一条是 PRIMARY，后续是 BACKUP。真正自动负载均衡仍需要客户端、DNS 或外部 LB 配合。

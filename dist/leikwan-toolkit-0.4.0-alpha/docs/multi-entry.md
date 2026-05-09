# 多公网入口

多入口用于同时管理多台 A 公网入口，例如云入口、家宽入口或备用入口。

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

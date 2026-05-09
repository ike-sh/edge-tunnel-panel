# 工作流

`leikwan-toolkit` 的角色很固定：

- A：公网入口，只管理本机 EasyTier entry 和入口端口池。
- B：利群主机，管理公网入口列表、后端转发目标、PBR 和 nftables relay 规则。
- C：后端目标，任意用户自备 TCP 服务。

## 新安装

```bash
curl -fsSL -o /tmp/lq-bootstrap.sh https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/main/scripts/bootstrap.sh && bash /tmp/lq-bootstrap.sh && lq
```

唯一主脚本是 `/root/leikwan-toolkit.sh`，`lq` 和 `LQ` 都指向它。

## 快速组网菜单

```text
1. 我现在在利群主机：先执行 DNS / IPv4 优先修复
2. 我现在在利群主机：生成 / 新增公网入口网络码
3. 我现在在公网入口：粘贴利群网络码，部署本机入口
4. 我现在在利群主机：粘贴公网入口返回码，完成接入
5. 我现在在公网入口：配置入口端口池
6. 我现在在利群主机：添加后端转发目标
7. IPv4 多出口策略路由 / PBR
8. 查看完整分步说明
0. 返回
```

## 首台公网入口

1. B 执行第 1 项，修复 DNS / IPv4 优先。
2. B 执行第 2 项，生成网络码。
3. A 执行第 3 项，粘贴网络码并部署本机入口。
4. A 执行第 5 项，配置入口端口池，例如 `10001-10020 -> 10.198.1.1`。
5. B 执行第 4 项，粘贴 A 返回的 ENTRY 入口码。
6. B 执行第 6 项，添加后端转发目标。

## 新增第二台公网入口

不要在 B 侧手工添加一行 `entries.tsv` 当作部署流程。正确流程是：

1. B 执行第 2 项。若已有 `/etc/leikwan-toolkit/easytier/network.env` 且角色是 `leikwan-relay`，脚本会复用现有 `EASYTIER_NETWORK_NAME` / `EASYTIER_NETWORK_SECRET`，不会覆盖 `network.env`，不会重启 `easytier-relay`。
2. 脚本读取现有 `entries.tsv`，自动推荐下一个唯一 EasyTier IP 和监听端口，例如已有 `aliyun 10.198.1.2 tcp/8301` 时推荐 `home 10.198.1.3 tcp/8302`。
3. 新 A 执行第 3 项，粘贴 B 的网络码。默认使用网络码里的 `SUGGESTED_ENTRY_NAME`、`SUGGESTED_ENTRY_ET_IP`、`SUGGESTED_EASYTIER_PORT`。
4. 新 A 执行第 5 项，配置本机入口端口池。
5. B 执行第 4 项，粘贴 A 返回码。默认只保存 `entries.tsv`，不会自动重启 relay，避免影响已有在线入口。
6. 需要立即应用时，脚本会提示重启 EasyTier relay 会短暂中断所有入口，并要求用户确认；建议在维护窗口应用。
7. B 进入 `利群主机 -> 公网入口列表管理` 查看或测试。

B 侧菜单 `公网入口列表管理` 的“手动添加公网入口（高级）”只适合明确知道 `entries.tsv` 字段含义的用户。

## EasyTier IP 与公网地址

A 部署入口时会询问两类地址：

- 本机 EasyTier IP：虚拟网 IP，例如 `10.198.1.3`，只能填写 IPv4。
- 本机公网 IP / 域名：B 用来连接 A 的公网地址或 DDNS，例如 `home.ike-nicholas.xyz`。

如果把 DDNS 填到“本机 EasyTier IP”，脚本会提示这是域名而不是虚拟 IP，并继续保留网络码里的默认 EasyTier IP。

## 后端转发目标

B 侧路径：`利群主机 -> 转发目标管理`

添加目标时：

- 公网入口端口会显示入口端口池范围，并推荐下一个未使用端口。
- 后端目标端口必须输入，没有旧固定默认值。
- 如果后端目标是域名，脚本会显示当前解析 IP，并提示每次 `apply-relay` 都会重新解析。

修改、删除、启用/禁用、测试单个转发目标都会先展示列表，支持编号或名称选择，空输入返回上级菜单。

## PBR 规则管理

B 侧路径：`利群主机 -> IPv4 多出口策略路由 / PBR`

```text
1. 添加静态 PBR
2. 从现有转发目标添加 PBR
3. 删除 PBR 规则
4. 应用 PBR
5. 查看 PBR
0. 返回
```

删除 PBR 会先展示当前规则列表，支持编号、CIDR 或裸 IP 选择；删除后会重新应用 PBR。来自 DDNS / forward 的规则删除的是当前解析 IP 对应的 PBR 记录。如果同一 CIDR 有多条不同路由表规则，请用编号精确删除。

## A 侧和 B 侧菜单区别

主菜单的“公网入口”只表示 A 机器本机管理：

```text
1. 粘贴利群网络码，部署本机入口
2. 配置本机入口端口池
3. 查看本机公网入口状态
0. 返回
```

B 侧多个公网入口的列表管理在：

```text
利群主机 -> 公网入口列表管理
```

如果在 B 上误进 A 侧公网入口状态，脚本会提示当前机器是利群主机，并引导回 B 侧入口列表管理。

## 输出文件

```text
/etc/leikwan-toolkit/entries/entries.tsv
/etc/leikwan-toolkit/forwards/forwards.tsv
/etc/leikwan-toolkit/forwards/resolved.tsv
/etc/leikwan-toolkit/outputs/forward-endpoints.txt
```

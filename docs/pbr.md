# IPv4 多出口策略路由

本模块用于利群中转机把指定 IPv4 目标走指定出口，例如让 Reality 海外落地机 IP 走 `9929` 或 `CN2`。

PBR 通常只需要在利群中转机启用。公网入口机只负责 WG + 转发，海外落地机只负责 Reality inbound，默认不需要 PBR。

它只处理项目保存或用户明确导入的 IPv4 PBR 规则：

- 不接管整机默认路由
- 不修改 `main` 默认路由
- 不删除系统已有默认网关
- 不引入 IPv6 智能管家
- 不引入 FRP/UoT/WSS/OpenVPN/gost/udp2raw

## 1. 为什么需要 PBR

利群主机常见多个 IPv4 出口线路组，例如 `9929`、`CN2`、`HKSDWAN`。Reality 落地机通常是一个固定 IPv4，给它指定出口可以避免业务链路走到不理想的默认出口。

PBR 只对命中的目标生效。没有命中的流量仍然按系统原来的默认路由走。

## 2. Reality 落地机指定 9929 示例

在利群中转机执行菜单：

```text
IPv4 多出口策略路由
4. 一键为当前 Reality 落地机指定出口
```

如果落地机 IP 是 `<LANDING_PUBLIC_IP>`，选择 `9929` 后会写入：

```text
/etc/leikwan-wg-toolkit/pbr/static-routes.conf

<LANDING_PUBLIC_IP>/32 9929
```

验收：

```bash
sudo bash wg-toolkit.sh --pbr-show
ip rule show | egrep '15000|15005'
ip route get <LANDING_PUBLIC_IP>
```

`ip route get` 应显示走 `10.7.0.1` 这一类 `T_9929` 表中的出口。

## 3. 如何导入已有手工规则

如果机器已有手工规则：

```bash
ip rule show | grep <LANDING_PUBLIC_IP>
```

示例输出：

```text
15000: from all to <LANDING_PUBLIC_IP> lookup T_9929
```

导入到项目：

```bash
sudo bash wg-toolkit.sh --pbr-import-existing
```

导入后会写入：

```text
<LANDING_PUBLIC_IP>/32 9929
```

再验证：

```bash
sudo bash wg-toolkit.sh --pbr-show
sudo bash wg-toolkit.sh --pbr-audit
ip route get <LANDING_PUBLIC_IP>
```

导入不会删除原规则。因为目标、priority 和路由表相同，后续 `--pbr-apply` 会把它识别为本项目托管规则，避免重复添加。

导入流程也会扫描 priority `15005` 的 IPv4 `to` 规则。此类规则导入后仍写入 `static-routes.conf`，项目会按同一目标和线路组把它视为已接管，卸载时也只删除这个已记录目标的精确规则。

## 4. priority 15000 / 15005 的安全边界

项目约定：

- 静态 IP/CIDR 规则使用 priority `15000`
- 域名 DDNS 解析出的 A 记录使用 priority `15005`

脚本不会执行按 priority 全删的逻辑。删除静态规则时只按配置文件里的 `cidr + group` 精确删除：

```bash
ip rule del to "$cidr" table "$table_id" priority 15000
```

域名规则只删除状态文件中记录过的旧 A 记录，不会碰同 priority 下的其他手工规则。

## 5. 为什么不删除非本项目规则

很多用户会先用手工命令调通 PBR，或者已有其他业务也使用 priority `15000` / `15005`。项目只管理自己的账本：

```text
/etc/leikwan-wg-toolkit/pbr/static-routes.conf
/etc/leikwan-wg-toolkit/pbr/domain-routes.conf
/var/lib/leikwan-wg-toolkit/pbr/domain-state.conf
```

`--pbr-audit` 会把同 priority 但未进入项目账本的规则列为 WARN，并提示可导入接管。

## 6. 域名规则为什么需要状态文件

域名每次刷新会解析新的 A 记录。为了避免误删手工规则，项目把上一次由域名解析生成的规则保存到：

```text
/var/lib/leikwan-wg-toolkit/pbr/domain-state.conf
```

格式：

```text
domain group ip cidr table_id
```

示例：

```text
example.com 9929 192.0.2.123 192.0.2.123/32 101
```

刷新流程：

1. 读取旧状态。
2. 只删除旧状态中记录过的 priority `15005` 规则。
3. 重新解析 `domain-routes.conf` 里的 A 记录。
4. 添加新规则。
5. 写入新的状态文件。
6. 如果域名解析失败，保留旧状态和旧规则，并输出 WARN。

## 7. systemd timer 如何刷新 DDNS

开机恢复服务：

```text
leikwan-pbr.service
```

它执行：

```bash
bash wg-toolkit.sh --pbr-apply
```

域名刷新 timer：

```text
leikwan-pbr-ddns.timer
```

默认每 5 分钟触发：

```text
leikwan-pbr-ddns.service
```

它执行：

```bash
bash wg-toolkit.sh --pbr-refresh-domains
```

## 8. 如何回滚

查看当前项目与系统规则：

```bash
sudo bash wg-toolkit.sh --pbr-show
sudo bash wg-toolkit.sh --pbr-audit
```

只删除本项目托管的运行中规则：

```text
主菜单 15 卸载 -> 仅删除 IPv4 PBR 规则
```

该操作会列出：

- 将删除的本项目托管规则
- 同 priority 但会保留的未托管规则

默认不会删除 `/etc/iproute2/rt_tables` 中的 `T_` 表名。删除表名需要二次确认，且不会影响 `local/main/default/unspec` 基础表。

## CLI

```bash
sudo bash wg-toolkit.sh --pbr-apply
sudo bash wg-toolkit.sh --pbr-refresh-domains
sudo bash wg-toolkit.sh --pbr-audit
sudo bash wg-toolkit.sh --pbr-import-existing
bash wg-toolkit.sh --pbr-show
```

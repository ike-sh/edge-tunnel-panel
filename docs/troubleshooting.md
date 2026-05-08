# 排错说明

v0.4 主线是 EasyTier 组网加 nftables 四层 TCP 转发。脚本不部署后端协议，只负责把 A 公网入口端口转到 B，再由 B 转到用户自备的 TCP 后端。

## doctor

```bash
sudo lq --doctor
sudo lq --doctor --verbose
```

doctor 只输出 `[OK] [WARN] [INFO] [FAIL]`。检查命令失败只会变成 WARN 或 FAIL，不应因为 `grep`、`nft`、`ping`、`nc`、`ip route get`、`easytier-cli` 等命令失败直接退出脚本。

## EasyTier 下载失败

EasyTier release 包较大，GitHub 慢时容易下载中断。安装器会轮询自定义镜像、内置镜像和官方 GitHub，并先写入 `.part` 临时文件，只有文件大小和压缩包校验通过后才安装。

可设置镜像：

```bash
export LEIKWAN_GITHUB_MIRRORS="https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/,https://ghproxy.net/"
```

仍失败时：

1. 先执行 `DNS / IPv4 优先修复`。
2. 再运行 EasyTier 安装。
3. 仍不通时，手动下载 EasyTier zip 或 tar.gz，按提示输入本地路径。

## A 公网入口端口不通

在 A 上检查：

```bash
systemctl status easytier-entry-aliyun --no-pager
ss -lntup | grep 8301
nft list table inet leikwan_forward
```

安全组需要放行：

- EasyTier TCP `8301`
- 入口端口池，例如 `10000-19999` 或 `10001-10020`

A 侧端口池 DNAT 应类似：

```text
tcp dport 10001-10020 dnat ip to 10.198.1.1
```

## B 到后端超时

如果 A 能连到 B 的 EasyTier IP，但外部访问入口端口超时，常见原因是 B 的后端出口接口或 PBR 路由表不一致。

在 B 上检查：

```bash
ip route get <TARGET_IP>
nft list table inet leikwan_forward
sudo lq --doctor
```

如果 `ip route get` 显示：

```text
dev eth1 table T_CN2
```

但 nftables 里是：

```text
oifname "eth0"
```

就会出现 A 已经到 B，但 B 转后端超时。执行：

```bash
sudo lq forward apply-relay
```

交互模式会询问是否自动修正。非交互可使用：

```bash
sudo lq forward apply-relay --auto-fix-route
```

`lq forward add` 和 `lq forward edit` 会自动通过 `ip route get TARGET_IP` 推荐实际 `out_iface` 和 `route_table`，普通用户不用手动猜 `eth0` / `eth1`。

## 缺少 nc

链路测试和后端 TCP 测试依赖 `nc`。干净系统缺少时，脚本会提示安装 `netcat-openbsd`，不会直接报 `nc: command not found`。

手动安装：

```bash
sudo apt-get install -y netcat-openbsd
```

## PBR 输入非法

PBR 目标必须是合法 IPv4 或 CIDR：

```text
203.0.113.30
203.0.113.0/24
```

这些输入会被拒绝：

```text
123456
abc
999.1.1.1
203.0.113.10/99
```

非法输入不会写入 `static-routes.conf`，也不会执行 `ip route add`。

## MSS clamp

EasyTier/tun 双 NAT 转发部分 TCP 后端时，可能出现“能 ping、有延迟，但 TCP 业务连不上”。项目默认在 A/B 的项目 nftables 规则中加入：

```text
tcp flags syn tcp option maxseg size set 1320
```

doctor 应显示：

```text
[OK] TCP MSS clamp enabled: 1320
```

如果仍不稳定，可以降到 `1280` 或 `1200`：

```bash
sudo install -d -m 700 /etc/leikwan-wg-toolkit/nft
printf 'TCP_MSS_CLAMP=1280\nENABLE_MSS_CLAMP=true\n' | sudo tee /etc/leikwan-wg-toolkit/nft/mss.env >/dev/null
sudo lq entry expose-range --range 10000-19999 --relay-ip 10.198.1.1
sudo lq forward apply-relay
```

## forwards.tsv

默认不要手写 TSV，推荐：

```bash
sudo lq forward add
sudo lq forward edit <name>
sudo lq forward delete <name>
```

高级用户手写时必须使用 TAB 分隔 8 列：

```text
name    entry_port    target_host    target_port    out_iface    route_table    enabled    comment
```

如果字段数不对，脚本会明确提示行号、实际字段数和当前行内容，并停止应用空 nftables 规则。

## 生成脱敏报告

菜单路径：

```text
高级功能 -> 生成脱敏故障报告
```

输出：

```text
/root/leikwan-debug-report.txt
```

报告会脱敏 EasyTier network secret 和历史敏感字段。

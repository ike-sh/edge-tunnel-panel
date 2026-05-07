# 实机验收清单

本文用于三台机器部署完成后的发布前验收。

## 通用验收

三台机器都建议执行：

```bash
bash wg-toolkit.sh --doctor
bash wg-toolkit.sh --doctor --verbose
```

合格标准：

- `--doctor` 默认输出简洁摘要。
- `--doctor --verbose` 输出完整分组报告，使用 `[OK] [WARN] [FAIL]`。
- 核心角色相关服务为 `[OK]`。
- 不属于当前角色的组件应显示为 `[INFO]` 或不检查，不应报 WARN。
- 不应出现与当前角色主链路有关的 `[FAIL]`。

默认主菜单验收：

```bash
sudo bash wg-toolkit.sh
```

合格标准：首屏只显示 4 个主要入口：

```text
--------------------------------------------------
  Leikwan WG Toolkit
  利群三机链式代理部署工具
  Author : ike-sh
  Version: 0.2.9-alpha
  GitHub : https://github.com/ike-sh/leikwan-wg-toolkit
--------------------------------------------------

1. 极速部署向导
2. 查看复制参数 / 客户端链接
3. 一键诊断 doctor
4. 高级功能
0. 退出
```

快捷命令验收：

```bash
command -v lq
command -v LQ
lq --version
LQ --version
```

合格标准：

- `lq --version` 和 `LQ --version` 均输出 `leikwan-wg-toolkit 0.2.9-alpha`。
- `lq --show-wg-identity`、`lq --doctor`、`lq --pbr-show` 不输出大 banner。
- 主菜单和极速部署向导显示虚线框，包含 `Author : ike-sh`、`Version: 0.2.9-alpha`、`GitHub : https://github.com/ike-sh/leikwan-wg-toolkit`。

菜单输入回归：

```text
主菜单直接按回车
主菜单输入 0
主菜单输入 " 0 "
主菜单粘贴 Windows CRLF 形式的 0\r
```

合格标准：

- 直接按回车不会刷“无效选择”，可提示“请输入选项编号”并重新显示菜单。
- `0`、` 0 `、`0\r` 都能正常退出或返回。

查看部署输出：

```bash
cat /root/leikwan-wg-toolkit-output.txt
ls -l /etc/leikwan-wg-toolkit/outputs/
```

该文件只包含给其他机器或客户端复制的参数，不包含 Reality PrivateKey。

## 公网入口机

命令：

```bash
wg show
ping -c 3 10.198.1.1
nc -vz 10.198.1.1 30000
sudo bash wg-toolkit.sh --doctor
nft list ruleset | grep -A20 leikwan || true
iptables -t nat -S | grep 10.198.1.1 || true
```

合格标准：

- `wg show` 能看到利群中转机 peer。
- `latest handshake` 存在且时间较新。
- `ping 10.198.1.1` 成功。
- `nc -vz 10.198.1.1 30000` 成功。
- `FORWARD_MODE` 对应的转发规则存在。
- nftables / iptables 模式不要求 `ss` 看到 `30000` 用户态监听。
- realm 模式下 `realm-leikwan.service` 为 active/running，且 `ss` 能看到 `30000` 监听。

输出文件应包含：

```text
CLOUD_PUBLIC_KEY
CLOUD_ENDPOINT
CLOUD_WG_PORT
CLIENT_ENTRY_PORT
FORWARD_MODE
FORWARD_TARGET
```

并存在：

```text
/etc/leikwan-wg-toolkit/outputs/cloud-entry.env
```

## 利群中转机

命令：

```bash
wg show
ping -c 3 10.198.1.2
ss -lntup | grep 30000
ip route get LANDING_ADDRESS
nc -vz LANDING_ADDRESS LANDING_PORT
systemctl status xray-leikwan --no-pager
/usr/local/bin/xray run -test -config /usr/local/etc/xray/leikwan/config.json
journalctl -u xray-leikwan -e --no-pager
```

把 `LANDING_ADDRESS` 和 `LANDING_PORT` 替换为落地机输出值。

合格标准：

- `wg show` 能看到公网入口机 peer。
- `latest handshake` 存在且时间较新。
- `ping 10.198.1.2` 成功。
- `ss` 能看到 `10.198.1.1:30000` 或 `30000` 监听。
- `ip route get LANDING_ADDRESS` 有明确出口路由。
- `nc -vz LANDING_ADDRESS LANDING_PORT` 成功。
- `xray-leikwan.service` 为 active/running。
- `xray run -test` 返回配置测试通过。

输出文件应包含：

```text
CLIENT_LINK
ENTRY_UUID
VLESSENC_ENCRYPTION
CLOUD_ENDPOINT
CLIENT_ENTRY_PORT
LANDING_ADDRESS
LANDING_PORT
WG_STATUS_HINT
```

并存在：

```text
/etc/leikwan-wg-toolkit/outputs/leikwan-relay.env
/etc/leikwan-wg-toolkit/outputs/client-link.txt
```

## 海外落地机

命令：

```bash
systemctl status xray-leikwan --no-pager
ss -lntup | grep 30004
/usr/local/bin/xray run -test -config /usr/local/etc/xray/leikwan/config.json
journalctl -u xray-leikwan -e --no-pager
```

合格标准：

- `xray-leikwan.service` 为 active/running。
- `ss` 能看到 `30004` 监听。
- `xray run -test` 返回配置测试通过。
- 云安全组或防火墙已放行 `LANDING_PORT/tcp`。

输出文件应包含：

```text
LANDING_ADDRESS
LANDING_PORT
LANDING_UUID
LANDING_PUBLIC_KEY
LANDING_SHORT_ID
LANDING_SERVER_NAME
LANDING_FLOW
```

并存在：

```text
/etc/leikwan-wg-toolkit/outputs/landing-server.env
```

输出文件不应包含：

```text
Reality PrivateKey
privateKey
```

## 客户端验收

使用利群中转机输出的 `CLIENT_LINK` 导入客户端。

合格标准：

- 客户端连接到 `CLOUD_ENDPOINT:30000`。
- 公网入口机 nftables / iptables / realm 转发命中；realm 模式才要求 `realm-leikwan` 有连接日志。
- 利群中转机 `xray-leikwan` 有入站和出站日志。
- 海外落地机 `xray-leikwan` 有 Reality 入站日志。
- 实际业务访问出口为海外落地机。

## IPv4 PBR 验收

在利群中转机执行：

```bash
sudo bash wg-toolkit.sh --pbr-audit
sudo bash wg-toolkit.sh --pbr-show
sudo bash wg-toolkit.sh --pbr-apply
ip rule show | egrep '15000|15005'
ip route get <LANDING_PUBLIC_IP>
systemctl status leikwan-pbr.service --no-pager
systemctl status leikwan-pbr-ddns.timer --no-pager
```

如果为 Reality 落地机 `<LANDING_PUBLIC_IP>` 指定 `9929` 出口：

```bash
ip route get <LANDING_PUBLIC_IP>
```

如已有手工规则，先导入再验收：

```bash
sudo bash wg-toolkit.sh --pbr-import-existing
sudo bash wg-toolkit.sh --doctor
```

合格标准：

- `/etc/leikwan-wg-toolkit/pbr/static-routes.conf` 或 `domain-routes.conf` 中存在目标规则。
- 如使用域名规则，`/var/lib/leikwan-wg-toolkit/pbr/domain-state.conf` 中存在已解析的 A 记录状态。
- `/etc/iproute2/rt_tables` 中存在 `T_9929`、`T_CN2` 等项目表名。
- `ip rule show` 中能看到 priority `15000` 或 `15005`。
- `ip route get <LANDING_PUBLIC_IP>` 显示的路由使用指定表对应的出口。
- `leikwan-pbr.service` 可执行成功。
- 如果 `leikwan-pbr.service` 未安装但规则已生效，doctor 应提示“当前规则已生效但重启后可能丢失”，并给出安装 / 重启 PBR 开机恢复服务的菜单路径。
- 如使用域名规则，`leikwan-pbr-ddns.timer` 为 active。
- 重复执行 `--pbr-apply` 不产生重复 `ip rule`。
- 未托管 priority `15000` / `15005` 规则不会被删除。
- 导入已有规则后，`--doctor` 不再对该规则输出未托管 WARN。
- `LANDING_ADDRESS` 实际走用户选择的出口。
- `main` 默认路由不变。

不合格情况：

- `ip route get` 仍走 main 默认出口。
- `ip rule show` 没有 priority `15000` / `15005`。
- 未托管手工规则在 `--pbr-apply` 或卸载后被删除。
- 重复执行 `--pbr-apply` 后出现重复规则。
- 指定线路组的网关不可达。
- 域名只有 AAAA 记录，没有 A 记录。

## 回归测试

### 1. 落地机部署

```bash
systemctl is-active xray-leikwan
ss -lntup | grep 30004
test -f /etc/leikwan-wg-toolkit/outputs/landing-server.env
```

合格标准：`xray-leikwan` 为 active，`30004` listening，`landing-server.env` 存在且不包含 Reality PrivateKey。

### 2. 利群只生成 PublicKey

```bash
sudo bash wg-toolkit.sh --show-wg-identity --role leikwan
sudo bash wg-toolkit.sh --show-wg-identity --role leikwan
sudo bash wg-toolkit.sh --show-wg-identity --role leikwan
cat /etc/wireguard/wg0_publickey
```

合格标准：命令直接输出 `ROLE_HINT`、`WG_INTERFACE`、`LEIKWAN_PUBLIC_KEY`，不进入交互菜单；重复执行 3 次，`LEIKWAN_PUBLIC_KEY` 不变。

### 3. 公网入口机部署

```bash
systemctl is-active wg-quick@wg1
bash wg-toolkit.sh --doctor
test -f /etc/leikwan-wg-toolkit/outputs/cloud-entry.env
grep '^FORWARD_MODE=' /etc/leikwan-wg-toolkit/outputs/cloud-entry.env
```

合格标准：`wg1` active，`cloud-entry.env` 存在，且 `FORWARD_MODE` 对应的 nftables / iptables / realm 转发检查通过。

### 4. 利群完成中转部署

```bash
systemctl is-active xray-leikwan
ss -lntup | grep 30000
test -f /etc/leikwan-wg-toolkit/outputs/client-link.txt
grep '^CLIENT_LINK=' /etc/leikwan-wg-toolkit/outputs/client-link.txt
```

合格标准：`xray-leikwan` active，`10.198.1.1:30000` listening，`client-link.txt` 存在。

### 5. PBR

```bash
sudo bash wg-toolkit.sh --pbr-show
ip route get <LANDING_PUBLIC_IP>
```

合格标准：`LANDING_ADDRESS -> T_9929` 或用户选择的线路组，`pbr-show` 无未托管规则。

### 6. doctor

三台机器分别运行：

```bash
sudo bash wg-toolkit.sh --doctor
sudo bash wg-toolkit.sh --doctor --verbose
```

合格标准：默认 `--doctor` 是简洁摘要，`--doctor --verbose` 是完整报告；不会误报其他角色组件缺失。例如利群中转机不应因 `realm-leikwan`、`8301/udp`、`30004/tcp` 不存在而 WARN。

状态推断回归：

```bash
test -s /etc/leikwan-wg-toolkit/outputs/leikwan-relay.env
test -s /etc/leikwan-wg-toolkit/outputs/client-link.txt
grep '^CLIENT_LINK=' /etc/leikwan-wg-toolkit/outputs/client-link.txt
sudo bash wg-toolkit.sh --doctor
```

合格标准：已跑通的利群中转机不再提示缺少 `CLOUD 参数` / `LANDING 参数`；状态机应能从 outputs、`client-link.txt`、Xray outbound 和 PBR 配置推断链路已完成。

### 7. dry-run

```bash
bash wg-toolkit.sh --dry-run
```

合格标准：不写入系统，不显示“已启动”，只显示 `[DRY-RUN] 跳过启动 ...`；如输出参数卡片，标题必须标明“DRY-RUN 预览参数，不能用于真实部署”。

### 8. realm-slim

使用 `zhboner/realm v2.9.3` 只包含 `realm-slim` 的安装包测试。

合格标准：脚本能自动找到 `realm-slim`，安装为 `/usr/local/bin/realm`，并通过 `realm -v` 或 `realm --version` 验证。

### 9. TOOL_VERSION

```bash
bash wg-toolkit.sh --version
sudo bash wg-toolkit.sh
head -n 3 /root/leikwan-wg-toolkit-output.txt
```

合格标准：菜单和输出始终显示 `0.2.9-alpha`，不会显示 `12 (bookworm)` 或 `13 (trixie)`。

### 10. 极速部署向导按角色显示

分别在三类机器运行：

```bash
sudo bash wg-toolkit.sh
# 选择 1. 极速部署向导
```

合格标准：

- 海外落地机只显示 Reality 落地、LANDING 参数、doctor。
- 公网入口机只显示导入 LEIKWAN_PUBLIC_KEY、部署 WireGuard + 转发、CLOUD 参数、doctor。
- 利群中转机只显示 LEIKWAN_PUBLIC_KEY、导入 CLOUD、导入 LANDING、完成链式部署、PBR、客户端链接、doctor。
- unknown 角色只显示“我这是海外落地机 / 公网入口机 / 利群中转机”。

### 11. 重建 outputs

在已运行的利群中转机上临时移开输出文件后执行：

```bash
sudo mkdir -p /root/leikwan-output-bak
sudo mv /etc/leikwan-wg-toolkit/outputs/client-link.txt /root/leikwan-output-bak/ 2>/dev/null || true
sudo bash wg-toolkit.sh --rebuild-outputs
test -f /etc/leikwan-wg-toolkit/outputs/leikwan-relay.env
```

合格标准：缺少 `VLESSENC_ENCRYPTION` 时不崩溃，生成 partial `leikwan-relay.env`，包含能解析到的 `ENTRY_UUID`、`CLOUD_ENDPOINT`、`CLIENT_ENTRY_PORT`、`LANDING_ADDRESS`、`LANDING_PORT`、`VLESSENC_DECRYPTION`，不生成新的 `client-link.txt`，并输出 WARN。

补充 `VLESSENC_ENCRYPTION` 后执行：

```bash
sudo bash wg-toolkit.sh --rebuild-outputs --vlessenc-encryption '<VLESSENC_ENCRYPTION>'
test -f /etc/leikwan-wg-toolkit/outputs/client-link.txt
grep '^CLIENT_LINK=' /etc/leikwan-wg-toolkit/outputs/client-link.txt
```

合格标准：成功生成 `client-link.txt`。

删除 outputs 和 `/root` 输出，只保留 Xray 配置，再用 CLI 参数补齐不可从配置反推的字段：

```bash
sudo rm -rf /etc/leikwan-wg-toolkit/outputs
sudo rm -f /root/leikwan-wg-toolkit-output.txt
sudo bash wg-toolkit.sh --rebuild-outputs \
  --vlessenc-encryption '<VLESSENC_ENCRYPTION>' \
  --cloud-endpoint <CLOUD_PUBLIC_IP> \
  --client-entry-port 30000 \
  --landing-address <LANDING_PUBLIC_IP> \
  --landing-port 30004
test -f /etc/leikwan-wg-toolkit/outputs/client-link.txt
grep '^ENTRY_UUID=.' /etc/leikwan-wg-toolkit/outputs/client-link.txt
grep '^CLIENT_LINK=' /etc/leikwan-wg-toolkit/outputs/client-link.txt
```

合格标准：能从 `/usr/local/etc/xray/leikwan/config.json` 解析 `inbounds[0].settings.clients[0].id` 作为 `ENTRY_UUID`，不会再提示缺少 `ENTRY_UUID`。

旧 `/root/leikwan-wg-toolkit-output.txt` 已有 `CLIENT_LINK` 时执行：

```bash
sudo rm -f /etc/leikwan-wg-toolkit/outputs/client-link.txt
sudo bash wg-toolkit.sh --rebuild-outputs
grep '^CLIENT_LINK=' /etc/leikwan-wg-toolkit/outputs/client-link.txt
grep '^ENTRY_UUID=.' /etc/leikwan-wg-toolkit/outputs/client-link.txt
grep '^CLOUD_ENDPOINT=.' /etc/leikwan-wg-toolkit/outputs/client-link.txt
grep '^CLIENT_ENTRY_PORT=.' /etc/leikwan-wg-toolkit/outputs/client-link.txt
grep '^VLESSENC_ENCRYPTION=.' /etc/leikwan-wg-toolkit/outputs/client-link.txt
```

合格标准：自动迁移旧 `/root/leikwan-wg-toolkit-output.txt` 中的 `CLIENT_LINK`，并从 `vless://ENTRY_UUID@host:port?...encryption=...` 反解析回填 `ENTRY_UUID`、`CLOUD_ENDPOINT`、`CLIENT_ENTRY_PORT`、`VLESSENC_ENCRYPTION`。

公网入口机 outputs 缺失时：

```bash
sudo mkdir -p /root/leikwan-output-bak
sudo mv /etc/leikwan-wg-toolkit/outputs/cloud-entry.env /root/leikwan-output-bak/ 2>/dev/null || true
timeout 20 sudo bash wg-toolkit.sh --doctor
test -s /etc/leikwan-wg-toolkit/outputs/cloud-entry.env
grep '^CLOUD_PUBLIC_KEY=' /etc/leikwan-wg-toolkit/outputs/cloud-entry.env
grep '^CLIENT_ENTRY_PORT=' /etc/leikwan-wg-toolkit/outputs/cloud-entry.env
grep '^FORWARD_TARGET=' /etc/leikwan-wg-toolkit/outputs/cloud-entry.env
```

合格标准：doctor 不进入交互；如果 `wg1`、`wg1.conf`、realm/nftables/iptables 项目配置足够完整，会自动重建 `cloud-entry.env`。不能重建时只输出修复命令。

### 12. doctor 不阻塞 outputs 重建

在已运行的利群中转机上临时移开 outputs 后执行：

```bash
sudo mkdir -p /root/leikwan-output-bak
sudo mv /etc/leikwan-wg-toolkit/outputs /root/leikwan-output-bak/outputs-missing 2>/dev/null || true
timeout 15 sudo bash wg-toolkit.sh --doctor
timeout 15 sudo bash wg-toolkit.sh --doctor --verbose
```

合格标准：

- doctor 不进入交互 read。
- 只输出 outputs 缺失 WARN 和 `bash wg-toolkit.sh --rebuild-outputs` 修复命令。
- 如果需要 `VLESSENC_ENCRYPTION`，只输出命令示例，不要求现场输入。
- 同一次 doctor 执行不会重复提示 outputs 缺失。

### 13. cloud-entry nftables 转发

公网入口机选择 `nftables 内核转发` 后执行：

```bash
systemctl status leikwan-forward-nft --no-pager
nft list ruleset | grep -A20 leikwan
sysctl net.ipv4.ip_forward
systemctl status realm-leikwan --no-pager 2>/dev/null || true
```

合格标准：

- `leikwan-forward-nft.service` active/exited 或上次执行成功。
- `nft list ruleset` 能看到 `leikwan_nat` 和 `leikwan_filter`。
- `net.ipv4.ip_forward = 1`。
- 不需要 `realm-leikwan` 进程。
- 外部客户端连接 `<CLOUD_PUBLIC_IP>:30000` 能到 `10.198.1.1:30000`。

### 14. cloud-entry iptables 转发

公网入口机选择 `iptables 内核转发` 后执行：

```bash
systemctl status leikwan-forward-iptables --no-pager
iptables -t nat -S | grep -- '--dport 30000'
iptables -S FORWARD | grep '10.198.1.1'
sysctl net.ipv4.ip_forward
```

合格标准：

- `leikwan-forward-iptables.service` active/exited 或上次执行成功。
- `iptables -t nat -S` 能看到 DNAT 到 `10.198.1.1:30000`。
- `net.ipv4.ip_forward = 1`。
- 重复部署不会产生重复规则。
- 外部客户端连接 `<CLOUD_PUBLIC_IP>:30000` 能到 `10.198.1.1:30000`。

### 15. redaction 脱敏检查

```bash
scripts/check-redaction.sh
```

合格标准：

- README/docs 不包含真实公网 IP、公钥、UUID、VLESSENC 或真实 `CLIENT_LINK`。
- 示例客户端链接使用：

```text
vless://<ENTRY_UUID>@<CLOUD_PUBLIC_IP>:30000?type=raw&security=none&encryption=<VLESSENC_ENCRYPTION>#Leikwan-WG-Xray-Reality
```

### 16. UDP / WireGuard 质量检测

在公网入口机或利群中转机执行：

```bash
sudo bash wg-toolkit.sh
# 高级功能 -> UDP / WireGuard 质量检测
```

合格标准：

- 输出 `wg show` 握手时间。
- 执行 30 秒 ping 采样，显示丢包率和 min/avg/max/mdev。
- 显示 `wg transfer` 是否增长。
- 如果缺少 `iperf3`，只提示可选安装，不强制安装。
- 结论使用 `[OK] UDP 正常` 或 `[WARN] 疑似 UDP QoS / 入口机线路差 / 利群侧出口问题`。

### 17. 多公网入口机与 DDNS 入口

在利群中转机执行：

```bash
sudo bash wg-toolkit.sh
# 高级功能 -> 多公网入口机管理
# 添加入口 entry-test，CLOUD_ENDPOINT 可填 <CLOUD_PUBLIC_IP> 或 <DDNS_DOMAIN>
ls /etc/leikwan-wg-toolkit/entries/
sudo bash wg-toolkit.sh
# 高级功能 -> 多公网入口机管理 -> 查看入口
```

合格标准：

- 生成 `/etc/leikwan-wg-toolkit/entries/entry-test.env`。
- 字段包含 `ENTRY_NAME`、`CLOUD_PUBLIC_KEY`、`CLOUD_ENDPOINT`、`CLOUD_WG_PORT`、`CLIENT_ENTRY_PORT`、`FORWARD_MODE`、`ENABLED`。
- 利群 `wg0.conf` 追加新 Peer，不覆盖原有 Peer。
- 质量测试后写入 `LAST_RTT` 和 `LAST_PACKET_LOSS`。
- 生成多个链接时写入 `/etc/leikwan-wg-toolkit/outputs/client-links.txt`。

公网入口机选择 DDNS endpoint 后执行：

```bash
grep '^CLOUD_ENDPOINT_TYPE=ddns' /etc/leikwan-wg-toolkit/outputs/cloud-entry.env
sudo bash wg-toolkit.sh --doctor
```

合格标准：doctor 检查 DDNS A 记录解析，并提示家宽上行可能成为瓶颈。

### 18. PBR 落地机出口质量测试

在利群中转机执行：

```bash
sudo bash wg-toolkit.sh
# 高级功能 -> IPv4 多出口策略路由 -> 测试落地机出口质量
ip route get <LANDING_PUBLIC_IP>
```

合格标准：

- 测试 `main`、`T_9929`、`T_CN2` 和已配置线路组。
- 输出 `ip route get` 结果和 `nc -vz <LANDING_PUBLIC_IP> <LANDING_PORT>` 可达性。
- 如系统有 `ping` / `mtr`，可以辅助显示；缺失时不报 fatal。
- 推荐线路组给出原因。
- 用户确认后只写入 `<LANDING_PUBLIC_IP>/32 线路组`，不接管整机默认路由。

### 19. BBR / 系统优化

```bash
sudo bash wg-toolkit.sh
# 高级功能 -> BBR / 系统优化 -> 查看当前拥塞控制状态
# 高级功能 -> BBR / 系统优化 -> 启用 BBR + fq
test -f /etc/sysctl.d/99-leikwan-bbr.conf
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc
# 高级功能 -> BBR / 系统优化 -> 恢复系统默认拥塞控制
```

合格标准：

- 启用时只写入 `/etc/sysctl.d/99-leikwan-bbr.conf`，不修改用户其他 sysctl 文件。
- 恢复时只删除本项目文件并执行 `sysctl --system`。
- BBR 判断以 `sysctl` 为准；`tcp_bbr` 未出现在 `lsmod` 时只显示 INFO，不降级为 WARN。
- 未启用 BBR 时 doctor 只显示 INFO/WARN，不作为 FAIL。
- 执行利群官方 `optimize.sh` 必须输入 `YES` 二次确认，并先备份 `sysctl -a`。

### 20. 多落地机管理

```bash
sudo bash wg-toolkit.sh
# 高级功能 -> 多落地机管理 -> 添加落地机
# 分别添加 us01 / hk01，使用 <LANDING_PUBLIC_IP> 或示例域名占位
ls /etc/leikwan-wg-toolkit/landings/
# 高级功能 -> 多落地机管理 -> 切换当前落地机
cat /etc/leikwan-wg-toolkit/landings/current
grep '^ACTIVE_LANDING_' /etc/leikwan-wg-toolkit/outputs/leikwan-relay.env
```

合格标准：

- 每个 landing profile 写入 `landing-<name>.env`。
- 添加 landing profile 后选择“不立即切换”时，不写 `current/current.env`，不修改 Xray config，不重启 `xray-leikwan`，只生成 `landing-<name>.env`。
- 添加 landing profile 后选择“立即切换”时，必须复用事务化 `switch_landing_by_name` 流程。
- 切换当前落地机必须先展示编号列表，再选择编号，再显示确认摘要；空输入取消，非法编号不崩溃。
- 存在 `landing-HK.env` 和 `landing-old-current.env` 两个 profile 时，进入“切换当前落地机”必须先显示包含 `No. Name Address Port SNI Status Active` 的表格，然后才显示“请选择落地机编号，留空取消：”。
- 在切换选择处直接回车应取消并返回；输入超出范围的编号应显示“编号不存在”，不崩溃。
- 如果没有任何 `landing-*.env`，应提示“当前没有落地机 profile”；如果 profile 全部 `ENABLED=no`，应提示“当前没有已启用的落地机 profile”。
- 测试所有落地机时执行 `nc`；如果当前利群 Xray inbound 参数可读，也生成临时 outbound 配置并执行 `xray run -test`。
- 切换 active landing 时，`xray run -test` 和 `nc LANDING_ADDRESS LANDING_PORT` 都成功后才 restart `xray-leikwan`。
- 多落地切换生成的临时 Xray 配置必须位于 `/usr/local/etc/xray/leikwan/`，文件名以 `.json` 结尾，例如 `config.tmp.XXXXXX.json`。
- 临时配置写入后先执行 `jq empty "$TMP_CONFIG"`，再执行 `xray run -test -config "$TMP_CONFIG"`，确保 Xray 能按 JSON 格式识别。
- 临时配置测试失败时，不覆盖正式 `config.json`，不重启 `xray-leikwan`，并打印临时配置路径和完整 Xray 输出。
- 临时配置测试成功后，才覆盖正式 `config.json` 并 restart。
- `systemctl restart xray-leikwan` 后不能只做一次 `ss grep`；必须等待 `30000/tcp` 监听恢复，超时建议 15 秒。
- 如果监听等待成功，不回滚；如果等待超时，输出 `ss -lntup`、`systemctl status xray-leikwan --no-pager -l`、`journalctl -u xray-leikwan -n 50 --no-pager` 等 debug 信息，再回滚旧配置。
- 添加 bad landing 并尝试切换时，失败后回滚旧 Xray 配置，`current.env` 不变，`xray-leikwan` 仍 active。
- `ENTRY_UUID` / `VLESSENC_ENCRYPTION` 不因切换落地而变化。
- `current.env` 与 Xray outbound 不一致时，doctor 和部署总览输出 WARN；“从 Xray 实际 outbound 修复 current 状态”只修复状态，不改配置、不重启。
- PBR 一键指定出口默认读取 Xray 实际 outbound；PBR 质量测试可选择当前 Xray 实际 outbound 或任意 landing profile。
- 海外落地机部署不写 `landings/current`，输出 `LANDING_DIRECT_LINK`，并明确它不是最终链式 `CLIENT_LINK`。

### 21. IX 转发目标

cloud-entry 默认目标仍为：

```text
direct-leikwan-xray -> 10.198.1.1:30000
```

测试 IX target：

```bash
sudo bash wg-toolkit.sh
# 高级功能 -> 公网入口转发目标管理
# 选择 ix-qianhai，输入 <IX_QIANHAI_ENDPOINT> 和端口 30000
sudo bash wg-toolkit.sh --refresh-forward-target
sudo bash wg-toolkit.sh --doctor --verbose
```

合格标准：

- 选择 IX 目标前有“将绕过 10.198.1.1:30000”的确认提示。
- `cloud-entry.env` 包含 `FORWARD_TARGET_MODE`、`FORWARD_TARGET_ADDRESS`、`FORWARD_TARGET_PORT`、`FORWARD_TARGET_RESOLVED_IP`。
- nftables/iptables 模式下域名 target 被解析为 A 记录 IP；`--refresh-forward-target` 能刷新并重载项目转发规则。
- realm 模式允许域名 remote。
- docs/README 只出现 `<IX_QIANHAI_ENDPOINT>` / `<IX_SHANGHAI_ENDPOINT>`，不出现真实 IX IP。

### 22. 断点续跑状态

执行任一部署步骤后检查：

```bash
test -f /etc/leikwan-wg-toolkit/state.json
sudo bash wg-toolkit.sh
```

合格标准：

- `state.json` 包含 `ROLE`、`CURRENT_STEP`、`COMPLETED_STEPS`、`MISSING_FIELDS`、`NEXT_ACTION`。
- 如果缺少关键参数，主菜单前只提示一次未完成部署。
- 用户可选择继续上次流程、查看状态或忽略。

### 23. 脱敏故障报告

```bash
sudo bash wg-toolkit.sh
# 高级功能 -> 生成脱敏故障报告
sudo test -f /root/leikwan-debug-report.txt
sudo grep -E '<PUBLIC_IP>|<WG_PUBLIC_KEY>|<UUID>|<VLESSENC>|<CLIENT_LINK>' /root/leikwan-debug-report.txt
```

合格标准：

- 报告包含 os-release、地址/路由、`wg show`、leikwan 服务状态、端口监听、nft/iptables 项目规则、Xray test、doctor verbose 和 outputs 字段完整性。
- 公网 IP、公钥、UUID、VLESSENC、Reality key/shortId、CLIENT_LINK 均被替换为占位符。
- README/docs 中的故障报告示例同样使用占位符，`scripts/check-redaction.sh` 通过。

### 24. 快捷命令卸载

```bash
sudo bash wg-toolkit.sh --uninstall
# 选择“删除快捷命令 lq / LQ”
test ! -e /usr/local/bin/lq
test ! -e /usr/local/bin/LQ
```

合格标准：本项目创建的 `/usr/local/bin/lq` 和 `/usr/local/bin/LQ` 被删除；如果同名文件没有 `# Managed by leikwan-wg-toolkit` 标识，脚本只输出 WARN 并保留。

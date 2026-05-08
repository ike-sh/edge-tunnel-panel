# 验收测试

## 基础检查

```bash
shellcheck wg-toolkit.sh uninstall.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
bash -n wg-toolkit.sh uninstall.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
scripts/check-redaction.sh
git diff --check
scripts/package-release.sh
```

## 菜单检查

主 banner 应显示专业框线样式，至少包含：

```text
╔════════════════════════════════════════════════════════════════════╗
║ Leikwan Toolkit
║ 利群快速组网工具
║ Author : ike-sh
║ Version: 0.4.0-alpha
║ GitHub : https://github.com/ike-sh/leikwan-wg-toolkit
╚════════════════════════════════════════════════════════════════════╝
```

主菜单应显示：

```text
1. 快速组网（分步提示）
2. 利群主机
3. 公网入口
4. 高级功能
5. 一键诊断
6. 卸载全部
0. 退出
```

进入 `快速组网（分步提示）` 后，第一屏必须提示利群主机先执行 DNS / IPv4 优先修复，并显示：

```text
1. 我现在在利群主机：先执行 DNS / IPv4 优先修复
2. 我现在在利群主机：生成给公网入口的 EasyTier 网络码
3. 我现在在公网入口：粘贴利群网络码，部署公网入口
4. 我现在在利群主机：粘贴公网入口码，完成组网
5. 我现在在公网入口：配置入口端口池
6. 我现在在利群主机：添加后端转发目标
7. IPv4 多出口策略路由 / PBR
8. 查看完整分步说明
0. 返回
```

`利群主机` 菜单只包含 B 侧转发目标、PBR、IPv6 收口和状态检查。`公网入口` 菜单只包含 A 侧入口机管理、端口池和状态检查。`高级功能 -> nftables 规则管理` 在未配置规则文件或 nft table 时应显示 WARN，不应退出脚本。

## bootstrap 非交互输入

```bash
echo "" | bash scripts/bootstrap.sh
cat scripts/bootstrap.sh | bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/leikwan-wg-toolkit/main/scripts/bootstrap.sh | bash
```

预期：

- 非 TTY stdin 下只安装，不自动进入 `lq` 菜单。
- 输出 `[OK] 安装完成。` 和 `请执行：lq`。
- 不会反复打印 `请输入选项编号。`。
- `bash scripts/bootstrap.sh --run-menu` 在非 TTY 下提示无法进入交互菜单。

## EasyTier 下载器

```bash
export LEIKWAN_GITHUB_MIRRORS="https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/,https://ghproxy.net/"
sudo lq
```

预期：

- 下载日志只输出到 stderr，不会污染被捕获的 URL。
- 不再出现 `curl: (3) bad range in URL position 3` 后跟 `[INFO]` 的情况。
- API JSON 只用于解析 release asset，不会被当作 EasyTier zip。
- EasyTier 大文件下载使用 `.part` 临时文件。
- 小于 10MB 或 `unzip -t` / `tar -tzf` 失败的包会被判定失败，并继续尝试下一个镜像。
- 下载失败时列出已尝试 URL，并提示 DNS / IPv4 修复、`LEIKWAN_GITHUB_MIRRORS` 和本地包 fallback。

## clean-room 最小流程

### B：生成网络码

```bash
sudo lq pair relay-init
```

合格标准：

- `/etc/leikwan-wg-toolkit/easytier/network.env` 存在。
- 输出 `BEGIN LEIKWAN EASYTIER NETWORK`。
- 输出 `LEIKWAN_EASYTIER_NETWORK_BASE64=`。
- 不包含系统私钥。

### A：部署入口

```bash
sudo lq pair entry-join
```

粘贴 B 网络码。

合格标准：

- `easytier-entry-aliyun.service` active。
- `ss -lntup` 可见 `8301/tcp`。
- `systemctl cat easytier-entry-aliyun` 中 `ExecStart` 包含 `tcp://0.0.0.0:8301`。
- 不应出现默认监听 `11010/tcp`。
- `/etc/leikwan-wg-toolkit/outputs/easytier-entry-code.env` 存在。
- 输出 `BEGIN LEIKWAN EASYTIER ENTRY`。

### B：接入入口

```bash
sudo lq pair relay-join
```

粘贴 A 入口码。

合格标准：

- `/etc/leikwan-wg-toolkit/entries/entries.tsv` 存在并包含入口。
- `easytier-relay.service` active。
- `systemctl cat easytier-relay` 中 peer 目标包含 `:8301`，不应连接 `:11010`。
- `easytier-cli peer` 能看到入口，或 doctor 给出明确 WARN。
- `ping 10.198.1.2` 成功，或输出可排查原因。

## doctor 端口与延迟

合格标准：

- `lq --doctor` 对 `8301` 显示白名单 OK。
- 如果手工改成 `11010`，doctor 必须 WARN。
- ping 100% loss 不能显示 OK。
- ping 平均 RTT 大于 `200ms` 时 WARN，大于 `1000ms` 时 FAIL 或强 WARN。

## nftables 转发

在 A 公网入口机配置入口端口池：

```bash
sudo lq entry expose-range --range 10000-19999 --relay-ip 10.198.1.1
```

合格标准：

- `nft list table inet leikwan_forward` 存在。
- A 侧有 `tcp dport 10000-19999 dnat ip to 10.198.1.1`。
- A 侧有 `tcp flags syn tcp option maxseg size set 1320`。
- A doctor 显示 `[OK] 入口端口池：10000-19999 -> 10.198.1.1`。
- A doctor 显示 `[OK] TCP MSS clamp enabled: 1320`。

在 B 使用 `利群主机 -> 转发目标管理` 添加：

```bash
sudo lq forward add
```

输入示例：

```text
name=service-a
entry_port=10001
target_host=203.0.113.30
target_port=37592
```

脚本应自动写入 B 的 `forwards.tsv`，并应用 B relay nftables。A 不需要导入转发码。

合格标准：

- `nft list table inet leikwan_forward` 存在。
- B 侧有 `tcp dport 10001 dnat ip to <resolved-target>:37592`。
- B 侧有 `tcp flags syn tcp option maxseg size set 1320`。
- B doctor 显示 `service-a relay DNAT 正常`。
- B doctor 显示 `[OK] TCP MSS clamp enabled: 1320`。
- 外部访问 `A_PUBLIC_HOST:10001` 能到达后端 TCP 服务。

新增第二个后端：

```bash
sudo lq forward add
```

使用 `entry_port=10002`。合格标准：不需要重新操作 A，外部访问 `A_PUBLIC_HOST:10002` 能到达第二个后端。

已验证场景：

```text
A expose-range: 10001-10020 -> 10.198.1.1
B forward: 10001 -> 203.0.113.30:37592
B forward: 10002 -> 198.51.100.20:37593
```

外部验收：

```bash
nc -vz -w 5 A_PUBLIC_HOST 10001
nc -vz -w 5 A_PUBLIC_HOST 10002
```

合格标准：两条连接都成功；新增第二个后端时不需要修改 A。

## MSS clamp 验收

已验证故障模型：

```text
直连 TARGET_HOST:TARGET_PORT 成功。
经 A_PUBLIC_HOST:ENTRY_PORT -> A -> EasyTier/tun -> B -> TARGET_HOST:TARGET_PORT 初始失败。
A/B 的 leikwan_forward 表加入 MSS 1320 后链路成功。
```

合格标准：

- A 和 B 都不需要手工创建 `lq_mss` 临时表。
- `/etc/leikwan-wg-toolkit/nft/leikwan-forward.nft` 包含 `tcp option maxseg size set 1320`。
- `leikwan-nft-forward.service` 重启后 MSS clamp 仍存在。
- `sudo lq --doctor` 对 A/B 都显示 `TCP MSS clamp enabled: 1320`。
- 修改 `/etc/leikwan-wg-toolkit/nft/mss.env` 为 `TCP_MSS_CLAMP=1280` 后重新应用，doctor 显示 `TCP MSS clamp enabled: 1280`。
- 如果 1320/1280 仍不稳定，可降到故障兜底值 `1200`。

删除一个后端：

```bash
sudo lq forward delete service-a
```

合格标准：不需要重新操作 A，`10001` 不再通，`10002` 仍然通。

## forwards.tsv 容错

人为写入错误内容：

```text
# nameentry_porttarget_hosttarget_portout_ifaceroute_tableenabledcomment
service-a10001203.0.113.3037592truecomment
```

合格标准：

- 应用 nftables 时必须失败，不能继续生成空转发表。
- 输出第 N 行字段数错误，并提示“期望 8 列，实际 X 列”。
- 输出当前行内容，并提醒必须使用 TAB 分隔。
- enabled forwards 为 0 时，应用空规则必须二次确认，默认不应用。
- `resolved.tsv` 没有可用转发时，不显示“nftables 转发规则已应用”。
- 如果 `table inet leikwan_forward` 存在但没有 DNAT 规则，doctor 必须 WARN。

## 多入口

添加 `aliyun`、`tencent`、`home` 三个入口。

合格标准：

- `entry_name` 唯一。
- `et_ip` 唯一。
- disabled 入口不参与输出。
- `forward-endpoints.txt` 按权重列出入口。

## doctor

```bash
sudo lq --doctor
sudo lq --doctor --verbose
```

合格标准：

- cloud-entry 检查 EasyTier entry、监听端口、nftables。
- relay 检查 EasyTier relay、entries、forwards、target、PBR。
- 主流程诊断不出现旧 0.2/0.3 组件字段。
- A/B 在 DNAT 检查、MSS 检查、ping RTT 解析、EasyTier peer 获取、target TCP 检查失败时只能输出 WARN/FAIL，不能崩溃退出。
- 菜单路径 `主菜单 -> 一键诊断`、`利群主机 -> 查看利群主机状态`、`公网入口 -> 查看公网入口状态`、`高级功能 -> 查看全部状态` 都不能在 DNAT 检查后退出。

## nc 缺失

在没有 `nc` 的干净系统上进入：

```text
高级功能 -> 链路测试
```

合格标准：

- 不出现 `nc: command not found`。
- 交互模式提示是否安装 `netcat-openbsd`。
- 非交互模式提示 `apt-get install -y netcat-openbsd` 并跳过当前 TCP 测试。

## 后端目标端口必填

执行：

```bash
sudo lq forward add
```

在 `后端目标端口` 处直接回车。

合格标准：

- 不显示 `[30004]` 默认值。
- 输出 `后端目标端口不能为空，请输入 1-65535。`
- 非法端口会重新提示，不崩溃。

## PBR 非法输入

菜单：

```text
利群主机 -> IPv4 多出口策略路由 / PBR -> 添加静态 PBR
```

输入：

```text
123456
```

合格标准：

- 输出目标 IP/CIDR 无效。
- 不写入 `static-routes.conf`。
- 不执行 `ip rule add`。
- 不崩溃。

线路组选择：

```text
1. CN2 -> T_CN2
2. 9929 -> T_9929
3. 自定义路由表
0. 返回
```

合格标准：

- 选择 CN2 后写入 `CN2` / 应用到 `T_CN2`。
- 选择 9929 后写入 `9929` / 应用到 `T_9929`。
- 非法选择重新提示。

## forward 出口自动识别

在 B 上添加后端：

```text
target_host=203.0.113.30
target_port=37592
```

如果：

```bash
ip route get 203.0.113.30
```

显示：

```text
dev eth1 table T_CN2
```

合格标准：

- `lq forward add` 显示检测到实际出口。
- 默认推荐 `out_iface=eth1`、`route_table=T_CN2`。
- 不再默认写 `eth0`。

人为把 `forwards.tsv` 改坏：

```text
out_iface=eth0
route_table=
```

执行：

```bash
sudo lq forward apply-relay
```

合格标准：

- 交互模式 WARN 配置和实际路由不一致。
- 选择自动修正后，`forwards.tsv` 改为实际 `dev/table`。
- nftables 规则使用实际 `oifname "eth1"`。
- 非交互可执行 `sudo lq forward apply-relay --auto-fix-route`。

## 脱敏

```bash
scripts/check-redaction.sh
```

合格标准：

- README/docs 不包含真实公网测试 IP。
- README/docs 不包含 EasyTier network secret。
- README/docs 不包含任何代理协议链接。

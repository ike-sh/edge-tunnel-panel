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
1. 极速部署向导
2. 查看复制参数 / 客户端链接
3. 一键诊断 doctor
4. 高级功能
0. 退出
```

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
ss -lntup | grep 30000
systemctl status realm-leikwan --no-pager
journalctl -u realm-leikwan -e --no-pager
```

合格标准：

- `wg show` 能看到利群中转机 peer。
- `latest handshake` 存在且时间较新。
- `ping 10.198.1.1` 成功。
- `nc -vz 10.198.1.1 30000` 成功。
- `ss` 能看到 `30000` 监听。
- `realm-leikwan.service` 为 active/running。

输出文件应包含：

```text
CLOUD_PUBLIC_KEY
CLOUD_ENDPOINT
CLOUD_WG_PORT
CLIENT_ENTRY_PORT
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
- 公网入口机 `realm-leikwan` 有连接日志。
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
ip route get 216.45.59.72
systemctl status leikwan-pbr.service --no-pager
systemctl status leikwan-pbr-ddns.timer --no-pager
```

如果为 Reality 落地机 `216.45.59.72` 指定 `9929` 出口：

```bash
ip route get 216.45.59.72
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
- `ip route get 216.45.59.72` 显示的路由使用指定表对应的出口。
- `leikwan-pbr.service` 可执行成功。
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
systemctl is-active realm-leikwan
test -f /etc/leikwan-wg-toolkit/outputs/cloud-entry.env
```

合格标准：`wg1` active，`realm-leikwan` active，`cloud-entry.env` 存在。

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
ip route get 216.45.59.72
```

合格标准：`LANDING_ADDRESS -> T_9929` 或用户选择的线路组，`pbr-show` 无未托管规则。

### 6. doctor

三台机器分别运行：

```bash
sudo bash wg-toolkit.sh --doctor
sudo bash wg-toolkit.sh --doctor --verbose
```

合格标准：默认 `--doctor` 是简洁摘要，`--doctor --verbose` 是完整报告；不会误报其他角色组件缺失。例如利群中转机不应因 `realm-leikwan`、`8301/udp`、`30004/tcp` 不存在而 WARN。

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

合格标准：菜单和输出始终显示 `0.2.1-alpha`，不会显示 `12 (bookworm)` 或 `13 (trixie)`。

### 10. 极速部署向导按角色显示

分别在三类机器运行：

```bash
sudo bash wg-toolkit.sh
# 选择 1. 极速部署向导
```

合格标准：

- 海外落地机只显示 Reality 落地、LANDING 参数、doctor。
- 公网入口机只显示导入 LEIKWAN_PUBLIC_KEY、部署 WG + realm、CLOUD 参数、doctor。
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
sudo bash wg-toolkit.sh --rebuild-outputs --vlessenc-encryption 'mlkem768x25519plus.native.0rtt.xxx'
test -f /etc/leikwan-wg-toolkit/outputs/client-link.txt
grep '^CLIENT_LINK=' /etc/leikwan-wg-toolkit/outputs/client-link.txt
```

合格标准：成功生成 `client-link.txt`。

删除 outputs 和 `/root` 输出，只保留 Xray 配置，再用 CLI 参数补齐不可从配置反推的字段：

```bash
sudo rm -rf /etc/leikwan-wg-toolkit/outputs
sudo rm -f /root/leikwan-wg-toolkit-output.txt
sudo bash wg-toolkit.sh --rebuild-outputs \
  --vlessenc-encryption 'mlkem768x25519plus.native.0rtt.xxx' \
  --cloud-endpoint 8.163.46.205 \
  --client-entry-port 30000 \
  --landing-address 216.45.59.72 \
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

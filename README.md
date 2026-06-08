# Edge Tunnel Panel v0.3.1

Edge Tunnel Panel 是一个面向节点组网、端口转发和出口策略的轻量 Web 面板。它用于把外部访问流量从 A 公网入口节点转发到 B 落地节点，再转发到最终落地服务器 IP/域名和端口。

## 适用场景

- B 节点没有公网 IPv4，需要通过 A 公网入口暴露服务。
- A 与 B 已通过 EasyTier 建立隧道。
- A 与 B 已经通过前海 IX、IPLC、公网或内网专线互通，不需要 EasyTier。
- B 节点需要转发到第三方落地服务器 IP/域名。
- B 节点具备多出口线路，需要通过 PBR 选择出口。
- EasyTier / 多层转发出现大包异常时，需要 MSS/MTU 诊断和钳制。

## 架构链路

```text
外部用户
  -> A 公网入口节点公网端口
  -> A nftables
  -> EasyTier 隧道 或 B 公网/专线直连
  -> B 落地节点
  -> B nftables
  -> 落地服务器 IP/域名:端口
```

## 一键安装（推荐）

**生产环境**（默认开启 Operator 鉴权，安装后打印登录地址与 Token）：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/quick-install.sh | sudo bash

**生产反代一键（本机 18080 + 防火墙，配合 Nginx/Caddy）：**

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/quick-install.sh | sudo bash -s -- --production --production-proxy nginx
```
```

**国内服务器**（GitHub 镜像 + 自动放行 ufw 18080）：

```bash
curl -fsSL https://gh.llkk.cc/https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/quick-install.sh | sudo bash -s -- --cn --open-ufw
```

安装完成后打开 `http://服务器公网IP:18080/login`（生产建议 Nginx + HTTPS，见 [deployment-v2.md](docs/deployment-v2.md) 与 `panel/examples/nginx-edge-tunnel-panel.conf`），Token 见终端输出或 `/etc/edge-tunnel/controller/install-summary.txt`。

### 安装 Agent（面板生成或手动）

在 Web「机器」页点击「安装向导」复制命令；或手动：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/quick-install.sh | sudo bash -s -- agent \
  --url http://YOUR_CONTROLLER:18080 \
  --token YOUR_MACHINE_TOKEN \
  --machine-id YOUR_MACHINE_ID \
  --name nat-ix-1
```

国内机器加 `--cn`（放在 `agent` 前）：

```bash
curl -fsSL https://gh.llkk.cc/https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/quick-install.sh | sudo bash -s -- --cn agent \
  --url http://YOUR_CONTROLLER:18080 \
  --token YOUR_MACHINE_TOKEN \
  --machine-id YOUR_MACHINE_ID
```

### 生产反代（Nginx / Caddy）

- Nginx：`panel/examples/nginx-edge-tunnel-panel.conf`
- Caddy（自动 HTTPS）：`panel/examples/Caddyfile.edge-tunnel-panel`
- Traefik + Docker：`panel/examples/docker-compose.traefik.yml`
- 防火墙 + certbot 续期：`sudo bash panel/scripts/setup-production-edge.sh --nginx --open-ssh`

详见 [docs/deployment-v2.md](docs/deployment-v2.md)。

## 高级安装（install-controller.sh）

如需自定义 listen / token / 目录，仍可使用底层脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- \
  --version latest \
  --strict-auth
```

## 卸载 Controller

保留配置和数据：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | bash -s -- --uninstall
```

彻底删除配置、数据和日志：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | bash -s -- --purge
```

## 添加 Agent

进入 Web「机器」页 → 添加机器 →「安装向导」复制一键命令（含国内镜像版）。

## 卸载 Agent

保留配置和状态：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | bash -s -- --uninstall
```

彻底删除 Agent、EasyTier service/config、状态和日志：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | bash -s -- --purge
```

同时删除 easytier-core/easytier-cli：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-agent.sh | bash -s -- --purge --remove-easytier-binaries
```

## Web 使用流程

1. “节点”页添加 A 节点和 B 节点。
2. “组网链路”页创建链路：
   - EasyTier 链路：自动安装/启动 EasyTier，A 与 B 建立 peer。
   - 直连链路：填写 A 可访问的 B 公网 IP、专线 IP 或内网 IP，不安装 EasyTier。
3. “转发规则”页选择链路，填写公网监听端口、落地服务器 IP/域名、落地端口，点击“创建并应用转发”。
4. “出口策略 / PBR”页选择 B 落地节点，先识别出口线路，再选择线路组和转发规则创建策略。
5. 需要暂停时，对组网链路、转发规则或 PBR 策略执行“停用”；需要恢复时执行“启用/应用”。
6. 出现问题时进入“诊断”，运行一键诊断并复制报告。

## 直连链路

直连链路适合前海 IX、IPLC、A/B 公网互通或内网专线互通场景。它不依赖 EasyTier：

```text
外部用户 -> A 公网端口 -> A nftables -> B 可达地址:中继端口 -> B nftables -> 落地服务器:端口
```

创建直连链路时需要填写：

- A 公网入口节点
- B 落地节点
- B 可达地址
- 默认中继端口
- TCP / UDP 协议

## 转发规则

当前 MVP 使用两段 nftables：

- A 侧：公网监听端口 -> B 的 EasyTier IP 或直连可达地址。
- B 侧：中继端口 -> 落地服务器 IP/域名:端口。

测试示例：

```bash
# B 或落地服务器上
python3 -m http.server 8080 --bind 0.0.0.0

# 外部客户端
curl -v http://A公网IP:18081/
```

排查命令：

```bash
nft list table ip edge_tunnel_entry_forward
nft list table ip edge_tunnel_landing_forward
cat /proc/sys/net/ipv4/ip_forward
journalctl -u edge-tunnel-agent -n 100 --no-pager
```

## 出口策略 / PBR

PBR 主要用于具备多出口线路的 B 落地节点。面板不会让用户手填出口接口和网关，而是让 Agent 识别线路组，例如 9929、CN2、JPSDWAN、DESDWAN、KRSDWAN 等。识别成功后选择线路组，网关、table、fwmark、priority 自动带出。

推荐流程：

1. 确认转发已跑通。
2. 进入“出口策略 / PBR”。
3. 选择 B 落地节点。
4. 点击“识别出口线路”。
5. 选择识别到的线路组。
6. 选择转发规则。
7. 创建并应用策略。
8. 验证策略。

如果没有识别到线路组，说明该节点可能不是多出口节点，不建议创建 PBR。

## MSS / MTU

默认 MTU 为 1380，默认启用 MSS clamp。它用于缓解 EasyTier、tun、多层 NAT 转发下的大包异常、网页卡顿或 TLS 握手后无响应问题。

可在组网高级参数中调整：

- MTU
- MSS clamp 开关
- auto / fixed / disabled 模式
- 固定 MSS 值

## 删除节点与远程清理

删除节点支持三种模式：

- `record_only`：仅删除 Controller 记录。
- `clean_deployed`：远程清理 EasyTier、nftables 转发表、PBR、MSS、转发配置和组网配置，保留 Agent。
- `purge_agent`：清理部署内容并卸载 Agent。

如果节点离线，Controller 无法远程清理，只能删除面板记录或等待节点上线后再清理。

## 一键诊断

诊断会创建只读任务，收集：

- Controller 版本和存储摘要
- 节点在线状态
- Agent 状态
- EasyTier 状态和 peer/route
- nftables 转发表
- PBR 线路组和策略
- MSS/MTU 状态
- 最近失败任务

诊断报告可复制为 Markdown，方便粘贴排查。

## 国内安装加速

设置 `EDGE_GITHUB_MIRRORS` 后，安装脚本会按顺序尝试官方源和镜像源：

```bash
export EDGE_GITHUB_MIRRORS="https://gh.llkk.cc/,https://gh.ddlc.top/,https://gh-proxy.com/,https://ghproxy.net/"
```

Web 添加节点时也可以选择“国内加速轮询”，面板会生成官方命令和多个备用镜像命令。

## 安全边界

- Agent 不接受任意 shell/cmd/script/raw 命令。
- 所有写入动作必须是固定 allowlist action。
- nftables、ip rule、ip route、systemctl 均由结构化配置渲染并用固定 argv 执行。
- Token 在任务结果中会被裁剪和脱敏。

## Credits / License

Web UI 布局和交互体验参考 [bqlpfy/flux-panel](https://github.com/bqlpfy/flux-panel) 的面板思路，原项目使用 Apache-2.0 License。本项目仅借鉴 UI/UX，不接入其后端、隧道或计费业务。

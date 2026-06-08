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
```

**生产反代一键**（本机 18080 + 防火墙，配合 Nginx/Caddy）：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/quick-install.sh | sudo bash -s -- --production --production-proxy nginx
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

## 维护者：构建与发布 Release

**本地构建**（Linux / Git Bash）：

```bash
VERSION=v0.3.1 bash panel/scripts/build-release.sh
```

**Windows PowerShell**（无 bash 时）：

```powershell
.\panel\scripts\build-release.ps1 -Version v0.3.1
```

产物位于 `panel/dist/`（`*.tar.gz` + `SHA256SUMS`）。

**发布到 GitHub**（需 `gh auth login` 或 `GH_TOKEN`）：

```powershell
.\panel\scripts\publish-release.ps1 -Version v0.3.1 -SkipBuild
```

或推送 tag 后由 GitHub Actions 自动发布（`.github/workflows/release.yml`）；也可在 Actions 页手动 **Run workflow** 指定版本。

**Docker 本地验证**（无需 Release 资产；国内拉不到 docker.io 时可指定镜像源）：

```bash
docker build -f panel/examples/docker/Dockerfile.local \
  --build-arg VERSION=v0.3.1 \
  --build-arg BASE_IMAGE=docker.m.daocloud.io/library/debian:bookworm-slim \
  -t edge-tunnel-panel:local panel/dist
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

## Web 使用流程（v2）

1. **登录**：打开 `/login`，粘贴安装时输出的 Operator Token。
2. **机器**：「机器」页添加 NAT IX 机器 →「安装向导」复制命令到目标服务器执行 Agent 安装。
3. **线路**：「线路」页通过向导创建 NAT IX Profile，填写落地地址与端口规则。
4. **应用**：在线路详情点击「应用 / 同步」，在「任务」页查看 SSE 进度。
5. **接入码**：NAT IX 线路在「接入码」Tab 复制完整码；公网入口机器通过「导入接入码」向导加入。
6. **诊断**：「诊断」页或线路详情一键诊断，报告可复制为 Markdown。

> v1 页面（组网链路 / 转发规则 / PBR 独立页）已废弃，能力合并到 **线路 Profile + ix-transit-fabric**。临时恢复 v1 API：`EDGE_LEGACY_V1_API=1`。

## 线路 Profile 与规则

一条线路对应 ix-transit-fabric 的一个 Profile，规则描述 NAT IX / 公网入口 / 落地端口映射：

```text
外部用户 -> 公网入口监听端口 -> NAT IX 中继 -> 落地服务器:端口
```

测试示例：

```bash
# 落地服务器上
python3 -m http.server 8080 --bind 0.0.0.0

# 外部客户端（公网入口 IP + 规则中的监听端口）
curl -v http://A公网IP:18081/
```

排查命令（Agent 所在机器）：

```bash
journalctl -u edge-tunnel-agent -n 100 --no-pager
# ix-transit-fabric / nftables 状态见诊断报告
```

## 删除机器与远程清理

删除机器时可选择：

- **仅删除记录**：保留 Agent 与现场配置。
- **远程清理**：清理已部署的 Profile / 转发配置，保留 Agent。
- **卸载 Agent**：清理并卸载 Agent 服务。

机器离线时 Controller 无法远程清理，只能删除面板记录或等待上线后再清理。

## 一键诊断

诊断会创建只读任务，收集：

- Controller 版本和存储摘要
- 机器 / Agent 在线状态
- ix-transit-fabric Profile 健康与端口映射
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

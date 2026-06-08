# Edge Tunnel Panel v2 部署指南

## 架构概览

```
Web UI (5173 dev / dist 静态)
  ├─ react-router 深链 (/machines, /profiles/:id, …)
  ├─ WebSocket 实时流 /api/v2/stream/machines (2s snapshot)
  └─ SSE 任务流 /api/v2/tasks/:id/stream
        ↓
Controller (18080) → store.json (machines / profiles / tasks / nodes)
        ↓
Agent heartbeat (/api/v1/agent/report) + ix-transit-fabric CLI
  └─ sysmetrics: CPU / 内存 / 网络流量 (Linux /proc)
```

## 1. 构建

```bash
# Controller
cd panel/controller && go build -o edge-tunnel-controller ./cmd/edge-tunnel-controller

# Agent
cd panel/agent && go build -o edge-tunnel-agent ./cmd/edge-tunnel-agent

# Web UI
cd panel/controller/web && npm ci && npm run build
```

## 2. 安装 Controller（一键）

```bash
# 生产（默认 strict 鉴权）
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/quick-install.sh | sudo bash

# 国内
curl -fsSL https://gh.llkk.cc/https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/quick-install.sh | sudo bash -s -- --cn --open-ufw

```

安装摘要：`/etc/edge-tunnel/controller/install-summary.txt`

### 源码 / 开发启动

```bash
export EDGE_LISTEN=0.0.0.0:18080
export EDGE_DATA_DIR=/var/lib/edge-tunnel/controller
export EDGE_WEB_DIR=/path/to/panel/controller/web/dist
export EDGE_OPERATOR_TOKEN=your-operator-token
export EDGE_CONTROLLER_TOKEN=your-agent-token
export EDGE_STRICT_AUTH=true   # 本地 E2E 可设为 false

./edge-tunnel-controller
```

> v1 API（networks/forwards/pbr）默认返回 **410 Gone**。临时恢复：`EDGE_LEGACY_V1_API=1`

## 3. 安装 Agent（生产）

在 Panel「机器」→「安装向导」复制命令（含国内镜像版），或：

```bash
curl -fsSL .../quick-install.sh | sudo bash -s -- agent \
  --url https://panel.example.com \
  --token <machine-token> \
  --machine-id <machine-uuid> \
  --name nat-ix-1
```

### 关键环境变量

| 变量 | 说明 |
|------|------|
| `EDGE_MACHINE_ID` | 绑定 Panel 机器记录 |
| `EDGE_IX_NATIVE` | `true` 启用 Go 原生 ix 写操作 |
| `IXTF_PROFILES_DIR` | profile .env 目录 |

### Agent 上报指标（Linux）

每次 heartbeat（`/api/v1/agent/report`）附带：

| 字段 | 来源 | 说明 |
|------|------|------|
| `cpu_percent` | `/proc/stat` | 两次采样差值；首次可能为 0 |
| `mem_percent` / `mem_*_mb` | `/proc/meminfo` | 内存使用率 |
| `uptime_sec` | `/proc/uptime` | 系统运行时间 |
| `bytes_sent` / `bytes_received` | `/proc/net/dev` | 累计流量（排除 lo） |
| `net_tx_bps` / `net_rx_bps` | 两次 heartbeat 差值 | 实时速率 |

> 部署新版本 Agent 后需 **重启 edge-tunnel-agent** 才会开始上报。

## 4. 安全与环境变量（生产）

| 变量 | 说明 |
|------|------|
| `EDGE_STRICT_AUTH=true` | 生产默认，启用 Operator Token |
| `EDGE_FORCE_HTTPS=1` | 反代终止 TLS 时强制 `X-Forwarded-Proto: https` |
| `EDGE_CORS_ORIGINS` | 逗号分隔允许跨域来源（默认同源，不开放 CORS） |

WebSocket `/api/v2/stream/machines`：**禁止** `?token=`，连接后首帧发送 `{"type":"auth","token":"..."}`。

```bash
node panel/scripts/e2e-ws-auth.mjs   # BASE=http://127.0.0.1:19081 TOKEN=...
```


## 4.1 Nginx 反代 + HTTPS（推荐生产）

Controller 仅监听本机，由 Nginx 终止 TLS 并转发 WebSocket。

**1. 安装 Controller（本机 18080）**

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/quick-install.sh | sudo bash
```

确认 `/etc/edge-tunnel/controller/controller.env`：

```bash
EDGE_LISTEN=127.0.0.1:18080
EDGE_STRICT_AUTH=true
EDGE_FORCE_HTTPS=1
```

修改后：`systemctl restart edge-tunnel-controller`

**2. 复制 Nginx 配置**

示例文件：`panel/examples/nginx-edge-tunnel-panel.conf`

```bash
# 替换 panel.example.com 与证书路径
sudo cp panel/examples/nginx-edge-tunnel-panel.conf /etc/nginx/sites-available/edge-tunnel-panel
sudo ln -sf /etc/nginx/sites-available/edge-tunnel-panel /etc/nginx/sites-enabled/
```

在 `/etc/nginx/nginx.conf` 的 `http {}` 内确保有 WebSocket map：

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
```

**3. 申请证书（Let's Encrypt）**

```bash
sudo certbot certonly --webroot -w /var/www/certbot -d panel.example.com
sudo nginx -t && sudo systemctl reload nginx
```

**4. 防火墙与 certbot 续期**

```bash
sudo bash panel/scripts/setup-production-edge.sh --nginx --open-ssh
```

**5. 验证**

```bash
curl -fsS https://panel.example.com/api/v1/health
# 浏览器打开 https://panel.example.com/login
```

WebSocket 鉴权：前端连接 `wss://panel.example.com/api/v2/stream/machines`，首帧发送 `{"type":"auth","token":"..."}`（**不要**使用 `?token=`）。

**6. Agent 安装命令中的 URL**

面板生成的 Agent 命令会使用 `https://panel.example.com`（需从 HTTPS 访问面板，或手动将 `--url` 改为公网 HTTPS 地址）。


## 4.2 Caddy 反代（自动 HTTPS）

比 Nginx 更省事：Caddy 自动申请与续期 Let's Encrypt 证书。

示例：`panel/examples/Caddyfile.edge-tunnel-panel`

```bash
# 1. Controller 仅本机 + 强制 HTTPS 头
# EDGE_LISTEN=127.0.0.1:18080
# EDGE_FORCE_HTTPS=1

# 2. 安装 Caddy 后
sudo cp panel/examples/Caddyfile.edge-tunnel-panel /etc/caddy/Caddyfile
# 编辑 panel.example.com 为你的域名
sudo systemctl enable --now caddy

# 3. 防火墙（放行 80/443，关闭公网 18080）
sudo bash panel/scripts/setup-production-edge.sh --caddy --open-ssh
```

验证：`curl -fsS https://panel.example.com/api/v1/health`


## 4.3 Traefik + Docker Compose

适合已有 Docker 的环境，Traefik 自动 HTTPS + WebSocket 反代。

```bash
cp panel/examples/.env.example panel/examples/.env
# 编辑 DOMAIN、ACME_EMAIL（域名需解析到本机公网 IP）
docker compose -f panel/examples/docker-compose.traefik.yml --env-file panel/examples/.env up -d --build
docker compose -f panel/examples/docker-compose.traefik.yml logs -f controller
```

**本地 smoke test（HTTP，无需域名）**：

```bash
# 需先构建镜像 edge-tunnel-panel:v0.3.1（见 README 维护者章节）
cd panel/examples
docker compose -f docker-compose.traefik.local.yml up -d
curl -fsS http://127.0.0.1:18088/api/v1/health
```

国内拉取基础镜像可在 build 时指定 `BASE_IMAGE=docker.m.daocloud.io/library/debian:bookworm-slim`；Traefik 可使用 `docker.m.daocloud.io/library/traefik:v3.3`。

文件：
- `panel/examples/docker-compose.traefik.yml`
- `panel/examples/docker/Dockerfile`

验证：`curl -fsS https://你的域名/api/v1/health`

## 4.4 Kubernetes Helm

```bash
# 1. 构建/推送镜像（见 docker/Dockerfile）
helm upgrade --install etp panel/examples/helm/edge-tunnel-panel \
  --set ingress.hosts[0].host=panel.example.com \
  --set env.EDGE_OPERATOR_TOKEN=YOUR_TOKEN
```

Chart：`panel/examples/helm/edge-tunnel-panel`（Deployment + PVC + Ingress + cert-manager 注解）

## 5. Web UI 路由与实时流

| 路径 | 页面 | 说明 |
|------|------|------|
| `/dashboard` | 总览 | 任务趋势、健康分布、网络 BarChart |
| `/machines` | 机器 | Modal CRUD、WS 实时指标、安装命令 |
| `/profiles` | 线路列表 | 创建向导入口 |
| `/profiles/:id` | 线路详情 | Tab：概览 / 规则 / 接入码 / 端口地图 |
| `/tasks` | 任务 | 过滤 + SSE 联动 |
| `/diagnostics` | 诊断 | 一键 ix_read_health |
| `/settings` | 设置 | Token / API Base |
| `/login` | 登录 | 严格鉴权时输入 Operator Token（参考 flux 独立登录页） |

**H5 移动布局**（参考 flux-panel `layouts/h5.tsx`）：
- 视口 ≤768px 自动启用，或通过 `?h5=true` / `?h5=false` 强制开关
- 底部 Tab：总览 / 机器 / 线路 / 任务 / 设置（诊断从总览或设置进入）
- Toast 位置改为 `bottom-center`，避免被 Tab 遮挡

### WebSocket 机器流

```
ws://<controller>/api/v2/stream/machines?token=<operator-token>
```

- 严格鉴权：`Authorization: Bearer` 或 query `token`
- 每 **2s** 推送：`{ type: "snapshot", machines: [...], nodes: [...] }`
- 服务端每 30s Ping；客户端 15s 无消息自动重连
- `machines[].status` 由 Node 心跳推导（online / stale / offline）

### 本地 Web 开发

```bash
cd panel/controller/web && npm run dev
# 默认 http://127.0.0.1:5173
# 跨域时在设置页填 API Base；保存 Token 后自动跳回原页面
```

## 6. 本地 E2E（Mock Agent）

```bash
# Terminal 1: Controller
EDGE_LISTEN=127.0.0.1:18080 EDGE_STRICT_AUTH=false go run ./cmd/edge-tunnel-controller

# Terminal 2: Mock Agent
MACHINE_ID=<uuid> CONTROLLER_URL=http://127.0.0.1:18080 node panel/scripts/mock-agent.mjs

# Terminal 3: Smoke
BASE=http://127.0.0.1:18080 bash panel/scripts/e2e-v2-smoke.sh
```

PowerShell 等价：`EDGE_LISTEN=127.0.0.1:8080` + `Invoke-RestMethod` 调用 v2 API。

## 6. 主要 v2 API

| 方法 | 路径 | 说明 |
|------|------|------|
| GET/POST | `/api/v2/machines` | 机器列表 / 创建 |
| POST | `/api/v2/machines/:id/rotate-token` | 轮换 Token（一次性返回） |
| GET/POST | `/api/v2/profiles` | 线路列表 / 创建 |
| GET | `/api/v2/profiles/:id` | 单条线路 |
| POST | `/api/v2/profiles/:id/sync` | 同步（3 任务：config / port_map / rules） |
| POST | `/api/v2/profiles/:id/apply` | 应用；body 可选 `{ rules: [...] }` |
| POST | `/api/v2/profiles/:id/code/refresh` | 刷新接入码 |
| POST | `/api/v2/diagnostics/run` | 按机器诊断 |
| GET | `/api/v2/stream/machines` | WebSocket 实时 snapshot |
| GET | `/api/v2/tasks/:id/stream` | SSE 任务进度 |

## 7. flux-panel 参考对照

参考项目：[flux-panel](https://github.com/bqlpfy/flux-panel)（GOST 面板，作者已暂停更新，但 UI/交互模式成熟）。

### 页面映射

| flux-panel | ETP v2 | 状态 |
|------------|--------|------|
| `/dashboard` 流量包 + 折线 + 转发列表 | `/dashboard` 任务趋势 + 健康 + 网络 | ✅ 部分 |
| `/node` WS 实时 CPU/流量 + 安装 Modal | `/machines` WS + Modal + 指标条 | ✅ 大部分 |
| `/forward` 转发 CRUD + 拖拽 + 诊断 | `/profiles/:id` 规则 Tab Modal | ✅ 部分 |
| `/tunnel` 隧道 in/out 节点 | `/profiles` 创建向导（NAT IX） | ✅ 合并 |
| `/limit` 限速 | — | ❌ Phase 4+ |
| `/user` 多用户 | 单 Operator Token | ❌ 不需要 |
| `/config` 网站配置 | `/settings` | ✅ |

### 已借鉴模式

- react-router 深链 + 侧栏 NavLink
- react-hot-toast 全局反馈
- Card + Table + Modal CRUD
- WebSocket 节点 snapshot（flux: `/system-info` → ETP: `/stream/machines`）
- Dashboard Recharts（懒加载 chunk）
- 移动端侧栏抽屉（768px 以下）
- Profile 规则 dnd-kit 拖拽排序 → `ix_write_apply_rules`
- ProfileDetail 暂停/恢复/诊断（`ix_write_disable_profile` / `enable` / `ix_read_diagnose`）
- 机器 stale/离线 + 线路异常 toast 告警
- 接入码 Tab「复制完整码」CopyModal + 接入地址推导

### 待借鉴（优先级）

| 优先级 | flux 特性 | ETP 建议 | 状态 |
|--------|-----------|----------|------|
| ~~**P0**~~ | forward 拖拽排序 | Profile 规则 Tab dnd-kit | ✅ |
| ~~**P0**~~ | forward 暂停/恢复/诊断 | ProfileDetail 暂停/恢复/诊断 | ✅ |
| ~~**P1**~~ | dashboard 过期 toast | 机器 stale/离线、线路失败 toast | ✅ |
| ~~**P1**~~ | forward 复制接入地址 Modal | 接入码 Tab CopyModal | ✅ |
| ~~**P1**~~ | node 安装命令分步 Modal | 机器页 InstallWizardModal 四步向导 | ✅ |
| ~~**P2**~~ | H5 底部 Tab 布局 | ≤768px 或 `?h5=true` 自动切换底部 Tab | ✅ |
| **P2** | 多用户 RBAC + JWT | 暂不需要（单 Operator） | — |
| **P2** | HeroUI 组件库 | 保留 macOS Glass，不整站迁移 | — |

### 数据模型差异（勿照搬 API）

```
flux:  User → Tunnel(inNode/outNode) → Forward(listen→remote)
ETP:   Machine → Profile(ix line) → Rules(nat/transit/landing ports)
```

## 8. 故障排查

| 现象 | 排查 |
|------|------|
| 任务 `waiting_agent` | Agent 未注册或未传 `machine_id` |
| SSE 长时间不结束 | 任务未 terminal；检查 Agent 日志 / Mock Agent |
| profile 无 port_map | sync 完成且 `ix_read_port_map` 成功 |
| WS 显示「轮询」非「实时」 | Token 未填 / 严格鉴权失败 / 防火墙拦截 WS |
| CPU/流量始终为 0 | 非 Linux Agent；或仅第一次 heartbeat（需第二次才有速率） |
| 机器 online 但 Node offline | 刷新页面；WS 每 2s 从 Node 推导机器状态 |

## 9. 相关文档

- [ix-transit-fabric 迁移设计](./migration-ix-transit-fabric-design.md)
- flux-panel 参考 clone：`D:\code\_ref\flux-panel\vite-frontend\`

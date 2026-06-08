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

## 2. 启动 Controller

```bash
export EDGE_LISTEN=0.0.0.0:18080
export EDGE_DATA_DIR=/var/lib/edge-tunnel/controller
export EDGE_WEB_DIR=/path/to/panel/controller/web/dist
export EDGE_OPERATOR_TOKEN=your-operator-token
export EDGE_CONTROLLER_TOKEN=your-agent-token
export EDGE_STRICT_AUTH=true   # 默认 true；本地 E2E 可设为 false

./edge-tunnel-controller
```

> v1 API（networks/forwards/pbr）默认返回 **410 Gone**。临时恢复：`EDGE_LEGACY_V1_API=1`

## 3. 安装 Agent（生产）

在 Panel「机器」页生成安装命令，或：

```bash
curl -fsSL .../install-agent.sh | bash -s -- \
  --controller-url https://panel.example.com \
  --token <machine-token> \
  --node-name nat-ix-1 \
  --machine-id <machine-uuid> \
  --enable-tasks --enable-write-actions --install-ixtf
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

## 4. Web UI 路由与实时流

| 路径 | 页面 | 说明 |
|------|------|------|
| `/dashboard` | 总览 | 任务趋势、健康分布、网络 BarChart |
| `/machines` | 机器 | Modal CRUD、WS 实时指标、安装命令 |
| `/profiles` | 线路列表 | 创建向导入口 |
| `/profiles/:id` | 线路详情 | Tab：概览 / 规则 / 接入码 / 端口地图 |
| `/tasks` | 任务 | 过滤 + SSE 联动 |
| `/diagnostics` | 诊断 | 一键 ix_read_health |
| `/settings` | 设置 | Token / API Base |

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

## 5. 本地 E2E（Mock Agent）

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

### 待借鉴（优先级）

| 优先级 | flux 特性 | ETP 建议 |
|--------|-----------|----------|
| **P0** | forward 拖拽排序 | Profile 规则 Tab 加 dnd-kit 排序后 apply |
| **P0** | forward 暂停/恢复/诊断按钮 | ProfileDetail 加「暂停线路」「诊断」enqueue ix_read_diagnose |
| **P1** | dashboard 过期 toast 提醒 | Profile/机器长时间 stale 时 toast |
| **P1** | forward 复制接入地址 Modal | 接入码 Tab 一键复制完整地址 |
| **P1** | node 安装命令分步 Modal | 机器页安装 Modal 加分步说明 |
| **P2** | H5 底部 Tab 布局 | 可选 `?h5=true` 移动布局 |
| **P2** | 多用户 RBAC + JWT | 暂不需要（单 Operator） |
| **P2** | HeroUI 组件库 | 保留 macOS Glass，不整站迁移 |

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

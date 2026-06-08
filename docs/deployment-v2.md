# Edge Tunnel Panel v2 部署指南

## 架构概览

```
Web UI (5173 dev / dist 静态) → Controller (18080) → Agent + ix-transit-fabric CLI
                                      ↓
                              store.json (machines / profiles / tasks)
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
export EDGE_STRICT_AUTH=true   # 生产环境建议开启

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

关键环境变量：

| 变量 | 说明 |
|------|------|
| `EDGE_MACHINE_ID` | 绑定 Panel 机器记录 |
| `EDGE_IX_NATIVE` | `true` 启用 Go 原生 ix 写操作 |
| `IXTF_PROFILES_DIR` | profile .env 目录 |

## 4. 本地 E2E（Mock Agent）

```bash
# Terminal 1: Controller（strict_auth=false 可跳过 Token）
EDGE_LISTEN=127.0.0.1:18080 EDGE_STRICT_AUTH=false go run ./cmd/edge-tunnel-controller

# Terminal 2: 创建机器后启动 Mock Agent
MACHINE_ID=<uuid> CONTROLLER_URL=http://127.0.0.1:18080 node panel/scripts/mock-agent.mjs

# Terminal 3: Smoke 测试
BASE=http://127.0.0.1:18080 bash panel/scripts/e2e-v2-smoke.sh
```

## 5. Web 开发

```bash
cd panel/controller/web && npm run dev
# http://127.0.0.1:5173 — API 默认同源，跨域时在设置页填 API Base
```

## 6. 主要 v2 API

| 方法 | 路径 | 说明 |
|------|------|------|
| GET/POST | `/api/v2/machines` | 机器 CRUD |
| GET/POST | `/api/v2/profiles` | 线路 CRUD（ingress 传 `code`） |
| POST | `/api/v2/profiles/:id/sync` | 同步（3 任务） |
| GET | `/api/v2/tasks/:id/stream` | SSE 任务流 |
| POST | `/api/v2/diagnostics/run` | 按机器诊断 |

## 7. 故障排查

- 任务 `waiting_agent`：Agent 未注册或未传 `machine_id`
- SSE 长时间不结束：任务未 terminal，检查 Agent 日志 / Mock Agent
- profile 无 port_map：需 sync 完成且 Agent 回报 `ix_read_port_map` 成功

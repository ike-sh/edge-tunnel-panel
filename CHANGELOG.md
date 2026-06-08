# Changelog — v0.3.2

文档与安全补丁：审查修复、CI 门禁、Traefik 本地验证。

## 文档

- README 更新为 v2 使用流程（机器 / 线路 Profile / 接入码）
- `deployment-v2.md` 修正 WebSocket 鉴权说明、端口与章节编号
- Helm 镜像 tag 统一为 `v0.3.2`，补充 build/push 说明

## 安全

- `EDGE_STRICT_AUTH=true` 时拒绝默认硬编码 Token，须使用 `quick-install.sh` 或自定义环境变量

## CI / 发布

- 新增 `.github/workflows/ci.yml`（go test + web build）
- Release workflow 增加测试门禁
- 新增 Traefik 本地 smoke compose（端口 18088，file provider）

## 其他

- `e2e-v2-smoke.sh` 默认端口改为 18080
- Topbar 文案对齐 v2
- `.gitignore` 忽略 `tmp/`

---

# Changelog — v0.3.1

正式版发布：v2 UI、一键安装、安全加固、生产反代示例。

## 一键安装

- 新增 `panel/scripts/quick-install.sh` 统一入口（Controller / Agent）
- `--cn` 国内镜像、`--production` 生产反代模式（127.0.0.1:18080 + UFW）
- `install-controller.sh` 默认严格鉴权、安装摘要、SHA256SUMS 校验
- 面板/API 生成 `quick-install agent` 命令（含国内镜像版）
- 安装向导支持 sudo 命令 + 国内镜像 + Token 轮换提示

## v2 Web UI（参考 flux-panel）

- react-router 深链、`/login` 独立登录页、401 全局拦截
- 机器 WebSocket 实时指标（首帧 auth，禁止 `?token=`）
- 规则拖拽排序、线路暂停/诊断、规则 JSON 导入导出
- H5 底部 Tab、Dashboard 快速开始、安装向导四步流程

## 安全

- Agent `machine_id` 绑定鉴权（禁止全局 Token 劫持机器）
- API 安全头、CORS（`EDGE_CORS_ORIGINS`）、登录限流、HTTPS 强制（`EDGE_FORCE_HTTPS`）
- Release 包 SHA256 校验（有 SHA256SUMS 时）

## 生产部署示例

- Nginx：`panel/examples/nginx-edge-tunnel-panel.conf`
- Caddy：`panel/examples/Caddyfile.edge-tunnel-panel`
- Traefik Docker Compose：`panel/examples/docker-compose.traefik.yml`
- Kubernetes Helm：`panel/examples/helm/edge-tunnel-panel`
- 防火墙 + certbot：`panel/scripts/setup-production-edge.sh`

## 测试

- WS 鉴权单元测试 + `panel/scripts/e2e-ws-auth.mjs`
- Agent 绑定安全测试、中间件测试

## 迁移说明

- 版本号：`v0.3.1-test` → **`v0.3.1`**
- WebSocket 客户端须改用首帧 `{"type":"auth","token":"..."}`
- 生产环境请使用 `--production` 或反代 + `EDGE_FORCE_HTTPS=1`

# Quickstart

当前版本：`v0.2.9-test`

## 1. 安装 Controller

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- \
  --version v0.2.9-test
```

打开：`http://服务器IP:18080`

## 2. 添加节点

进入“节点”页面，点击“添加节点”，复制 root 或 sudo 命令到服务器执行。

建议至少准备：

- A 公网入口节点
- B 落地执行节点

## 3. 快速组网

进入“组网配置”：

1. 选择 A 公网入口节点。
2. 选择 B 落地执行节点。
3. 保持默认 MTU `1380` 和 MSS clamp `auto`。
4. 点击“创建并应用组网”。
5. 等待组网卡片显示“组网成功”。

## 4. 创建转发

进入“转发规则”：

1. 选择组网链路。
2. 填公网监听端口，例如 `18081`。
3. 填落地服务器地址，例如 `1.2.3.4` 或 `backend.example.com`。
4. 填落地服务器端口，例如 `8080`。
5. 点击“创建并应用转发”。

## 5. 配置 PBR

进入“出口策略 / PBR”：

1. 选择 B 落地节点。
2. 点击“识别网卡”。
3. 选择转发规则。
4. 填出口接口和网关。
5. 点击“创建并应用策略”。

当前每个节点只允许一条启用中的 PBR 策略。

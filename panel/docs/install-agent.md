# 安装 Leikwan Agent

Leikwan Agent 2.0.0-beta.2 是只读采集器。它只读取本机状态并上报 Controller，不会修改 nftables、systemd、EasyTier、DDNS、entries.tsv、forwards.tsv 或 PBR。

## 手动安装

在 Agent 机器上构建：

```bash
cd panel/agent
go build -o leikwan-agent ./cmd/leikwan-agent
sudo install -m 0755 leikwan-agent /usr/local/bin/leikwan-agent
```

也可以使用安装脚本：

```bash
sudo bash panel/scripts/install-agent.sh \
  --controller http://controller.example.com:18080 \
  --token your-token \
  --name relay-1 \
  --role relay
```

该脚本只安装 agent、写入 `/etc/leikwan-agent/config.yml`、安装 systemd 示例，不碰 Leikwan Core 转发配置。

创建配置目录：

```bash
sudo mkdir -p /etc/leikwan-agent
sudo install -m 0600 panel/examples/agent.yml /etc/leikwan-agent/config.yml
```

编辑：

```bash
sudo nano /etc/leikwan-agent/config.yml
```

## agent.yml 示例

```yaml
controller_url: http://127.0.0.1:18080
token: change-me
node_id: relay-1
node_name: relay-1
role: relay
interval_seconds: 30
```

role 支持：

```text
entry
relay
backend
mixed
unknown
```

## --once 测试

```bash
leikwan-agent --config /etc/leikwan-agent/config.yml --once
```

也可以只生成配置文件：

```bash
leikwan-agent --init-config \
  --config /etc/leikwan-agent/config.yml \
  --controller-url http://controller.example.com:18080 \
  --token your-token \
  --node-name relay-1 \
  --role relay
```

调试模式会输出脱敏后的采集内容：

```bash
leikwan-agent --config /etc/leikwan-agent/config.yml --once --debug
```

## systemd

示例服务：

```text
panel/examples/leikwan-agent.service
```

安装：

```bash
sudo cp panel/examples/leikwan-agent.service /etc/systemd/system/leikwan-agent.service
sudo systemctl daemon-reload
sudo systemctl enable --now leikwan-agent.service
```

日志：

```bash
journalctl -u leikwan-agent.service -n 100 --no-pager
```

## 安全说明

beta.2 仍然只读：

- 不执行 Controller 下发命令
- 不写 Core 配置
- 不重启 relay
- 不应用 nftables
- 不修改 entries / forwards / PBR

Agent 上报前会脱敏 raw JSON，Controller 入库前也会再次脱敏。

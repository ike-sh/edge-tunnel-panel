# 安装 Leikwan Controller

Leikwan Controller 2.1.0-alpha.1 是面板服务端。它保存 Agent 上报的节点、历史、入口、转发、事件和 Plans，不会修改任何节点系统�?
## 手动构建

```bash
cd panel/controller
go build -o leikwan-controller ./cmd/leikwan-controller
sudo install -m 0755 leikwan-controller /usr/local/bin/leikwan-controller
```

创建目录�?
```bash
sudo mkdir -p /etc/leikwan-panel /var/lib/leikwan-panel
sudo chmod 0750 /etc/leikwan-panel /var/lib/leikwan-panel
```

配置 token�?
```bash
sudo install -m 0600 /dev/null /etc/leikwan-panel/controller.env
sudo sh -c 'echo LEIKWAN_CONTROLLER_TOKEN=your-strong-token > /etc/leikwan-panel/controller.env'
```

不要使用�?token。安装脚本不会自动生�?token�?
## 使用安装脚本

```bash
export LEIKWAN_CONTROLLER_TOKEN='your-strong-token'
sudo -E bash panel/scripts/install-controller.sh
```

脚本会：

- 安装 `/usr/local/bin/leikwan-controller`
- 创建 `/etc/leikwan-panel/`
- 创建 `/var/lib/leikwan-panel/`
- 安装 `leikwan-controller.service`
- 在提供环境变量时写入 `/etc/leikwan-panel/controller.env`

脚本不会启动一个没�?token �?Controller�?
## 启动

```bash
sudo systemctl enable --now leikwan-controller.service
```

健康检查：

```bash
curl http://127.0.0.1:18080/api/v1/health
```

## 安全边界

Controller 不会�?
- 远程执行命令
- 下发配置
- 修改 nftables / systemd / EasyTier / DDNS
- 修改 entries / forwards / PBR
- 返回真实 token �?Web API

`/api/v1/bootstrap/agent-command` 只返�?`REDACTED` token 模板�?

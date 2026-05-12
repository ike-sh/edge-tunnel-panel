# 安装 Agent

Leikwan Agent `3.0.0-alpha.4` 运行在 A 公网入口和 B 中转节点上。落地/后端机器不需要安装 Agent。

## 从 Web 复制命令

进入 Web 面板 `添加节点` 页面，填写节点名称、角色和开关后复制命令。例如：

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/panel-3-alpha/panel/scripts/install-agent.sh | sudo bash -s -- \
  --controller-url http://1.2.3.4:18080 \
  --token AGENT_TOKEN \
  --node-name relay-1 \
  --role relay \
  --enable-tasks \
  --enable-write-actions
```

## 参数

```bash
--controller-url http://1.2.3.4:18080
--token <agent-token>
--node-name relay-1
--role relay
--enable-tasks
--enable-write-actions
--version 3.0.0-alpha.4
--source-ref panel-3-alpha
--release-url https://example.com/leikwan-panel.tar.gz
```

`--enable-write-actions` 默认关闭。开启后，Agent 只允许执行固定白名单 alpha action，不接受任意命令字符串。

## 安装路径

```text
/usr/local/bin/leikwan-agent
/etc/leikwan-agent/config.yml
/var/lib/leikwan-agent
/etc/systemd/system/leikwan-agent.service
```

`config.yml` 权限为 `0600`。

## 安装后检查

```bash
systemctl status leikwan-agent --no-pager
journalctl -u leikwan-agent -n 100 --no-pager
```

安装脚本会执行一次：

```bash
leikwan-agent --config /etc/leikwan-agent/config.yml --once
```

如果这次上报失败，脚本会提示，但不会阻止 systemd service 启动。
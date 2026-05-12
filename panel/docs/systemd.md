# systemd 示例

本文档说明 Leikwan Panel `3.0.0-alpha.4` 的 systemd 部署方式。

## Controller

安装脚本会生成：

```text
/etc/leikwan-panel/controller.env
/etc/systemd/system/leikwan-controller.service
```

`controller.env` 至少包含：

```text
LEIKWAN_LISTEN=0.0.0.0:18080
LEIKWAN_DATA_DIR=/var/lib/leikwan-panel
LEIKWAN_WEB_DIR=/var/lib/leikwan-panel/web
LEIKWAN_CONTROLLER_TOKEN=...
LEIKWAN_OPERATOR_TOKEN=...
LEIKWAN_ADMIN_USER=admin
LEIKWAN_ADMIN_PASSWORD_HASH=...
LEIKWAN_SESSION_SECRET=...
```

service 示例：

```ini
[Unit]
Description=Leikwan Panel Controller
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/leikwan-panel/controller.env
ExecStart=/usr/local/bin/leikwan-controller --listen ${LEIKWAN_LISTEN} --db ${LEIKWAN_DATA_DIR}/controller.db --web-dir ${LEIKWAN_WEB_DIR} --strict-auth=${LEIKWAN_STRICT_AUTH}
Restart=on-failure
RestartSec=5s
User=root

[Install]
WantedBy=multi-user.target
```

安装脚本会先确认 binary 支持 `--web-dir`，避免旧 binary 和新 service 参数不匹配。

## Agent

Agent service 示例：

```ini
[Unit]
Description=Leikwan Panel Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/leikwan-agent --config /etc/leikwan-agent/config.yml
Restart=on-failure
RestartSec=5s
User=root

[Install]
WantedBy=multi-user.target
```

## 查看日志

```bash
systemctl status leikwan-controller --no-pager
journalctl -u leikwan-controller -n 100 --no-pager
systemctl status leikwan-agent --no-pager
journalctl -u leikwan-agent -n 100 --no-pager
```

日志中不应出现 token、secret、password、privateKey、custom_url、custom_cmd 或 Authorization 明文。
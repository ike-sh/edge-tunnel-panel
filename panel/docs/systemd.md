# systemd

## 主控服务

```bash
sudo systemctl status edge-tunnel-controller.service
sudo journalctl -u edge-tunnel-controller.service -f
sudo systemctl restart edge-tunnel-controller.service
```

## Agent 服务

```bash
sudo systemctl status edge-tunnel-agent.service
sudo journalctl -u edge-tunnel-agent.service -f
sudo systemctl restart edge-tunnel-agent.service
```

## EasyTier 服务

```bash
sudo systemctl status edge-tunnel-easytier.service
sudo journalctl -u edge-tunnel-easytier.service -f
sudo systemctl restart edge-tunnel-easytier.service
```

EasyTier 配置默认在 `/etc/edge-tunnel/agent/easytier.toml`。

Agent 应用组网配置时会写入：

- `/etc/edge-tunnel/agent/easytier.toml`
- `/etc/edge-tunnel/agent/systemd/edge-tunnel-easytier.service`
- `/etc/systemd/system/edge-tunnel-easytier.service`

随后使用固定参数执行：

```bash
systemctl daemon-reload
systemctl enable edge-tunnel-easytier.service
systemctl restart edge-tunnel-easytier.service
systemctl is-active edge-tunnel-easytier.service
```

## EasyTier 启动参数

`edge-tunnel-easytier.service` 的 `ExecStart` 使用 `easytier-core` CLI 参数生成：`--network-name`、`--network-secret`、多个 `-l` listeners，以及多个 `-p` peers。`/etc/edge-tunnel/agent/easytier.toml` 仍会写入，方便审计和后续模板调整。

## 空间不足排障

EasyTier 安装临时目录优先使用 `/var/lib/edge-tunnel/agent/tmp`，也会清理旧的 `edge-easytier-*` 临时目录。如果任务提示空间不足：

```bash
df -h
journalctl --vacuum-size=100M
apt clean
rm -rf /tmp/edge-easytier-*
```

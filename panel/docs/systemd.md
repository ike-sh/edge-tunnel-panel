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

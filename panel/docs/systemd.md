# systemd

## Controller

```bash
sudo systemctl status edge-tunnel-controller.service
sudo journalctl -u edge-tunnel-controller.service -f
sudo systemctl restart edge-tunnel-controller.service
```

Service file:

- `/etc/systemd/system/edge-tunnel-controller.service`
- environment file: `/etc/edge-tunnel/controller/controller.env`
- working directory: `/var/lib/edge-tunnel/controller`

## Agent

```bash
sudo systemctl status edge-tunnel-agent.service
sudo journalctl -u edge-tunnel-agent.service -f
sudo systemctl restart edge-tunnel-agent.service
```

Service file:

- `/etc/systemd/system/edge-tunnel-agent.service`
- environment file: `/etc/edge-tunnel/agent/agent.env`
- working directory: `/var/lib/edge-tunnel/agent`

## EasyTier

```bash
sudo systemctl status edge-tunnel-easytier.service
sudo journalctl -u edge-tunnel-easytier.service -f
sudo systemctl restart edge-tunnel-easytier.service
```

EasyTier config:

- `/etc/edge-tunnel/agent/easytier.toml`

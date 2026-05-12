# 安装 Controller

Leikwan Controller `3.0.0-alpha.4` 是 Panel 的 Web/API 主控服务。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/panel-3-alpha/panel/scripts/install-controller.sh | sudo bash
```

## 常用参数

```bash
--version 3.0.0-alpha.4
--repo ike-sh/leikwan-toolkit
--source-ref panel-3-alpha
--listen 0.0.0.0:18080
--data-dir /var/lib/leikwan-panel
--agent-token <token>
--operator-token <token>
--strict-auth
--public-url http://1.2.3.4:18080
--release-url https://example.com/leikwan-panel.tar.gz
```

## 下载顺序

1. 用户指定的 `--release-url` / `--install-url`。
2. GitHub Release asset：脚本会自动尝试 `v3.0.0-alpha.4` 和 `panel-3.0.0-alpha.4` 两种 tag，以及多个 asset 名称。
3. 同一 `--source-ref` 的源码 fallback 构建。alpha 阶段默认 source ref 是 `panel-3-alpha`，不会硬编码 main。

源码构建会安装 `golang`、`npm`、`nodejs`，耗时较长。

## 安装路径

```text
/usr/local/bin/leikwan-controller
/etc/leikwan-panel/controller.env
/var/lib/leikwan-panel/controller.db
/var/lib/leikwan-panel/web
/var/log/leikwan-panel
/etc/systemd/system/leikwan-controller.service
```

## web-dir 兼容校验

安装脚本写入的 systemd service 会使用 `--web-dir`。安装 binary 后脚本会先执行：

```bash
/usr/local/bin/leikwan-controller -h | grep -q "web-dir"
```

如果 binary 不支持 `--web-dir`，脚本会报错：

```text
controller binary does not support --web-dir; source/ref mismatch
```

这样可以避免旧 binary + 新 service 参数不匹配导致 systemd 反复重启。

## 启动和排查

```bash
systemctl status leikwan-controller --no-pager
journalctl -u leikwan-controller -n 100 --no-pager
```

安装完成后会输出 Web URL、admin 密码、Operator token、Agent token 和添加节点入口。
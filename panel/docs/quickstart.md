# Leikwan Panel 快速开始

当前 Panel 版本：`3.0.0-alpha.4`。Shell Core 仍是 `1.4.0 LTS`，本轮不修改 `leikwan-toolkit.sh`。

## 1. 安装 Controller

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/leikwan-toolkit/panel-3-alpha/panel/scripts/install-controller.sh | sudo bash
```

安装脚本会优先下载 GitHub Release 包。如果 release asset 暂未上传，会 fallback 到同一 `panel-3-alpha` source ref 源码构建。

## 2. 登录面板

安装完成后脚本会输出：

- Web URL
- admin 初始密码
- Operator token
- Agent token

打开 Web，输入 Operator token 解锁操作按钮。

## 3. 添加节点

进入 `添加节点` 页面，填写：

- Controller URL
- 节点名称
- 角色：entry / relay / mixed
- 是否启用只读任务
- 是否启用 alpha 写操作

复制生成的一键命令，在被控 VPS 上以 root 或 sudo 执行。Agent 会主动连接 Controller，Controller 不需要 SSH 到节点。

## 4. 创建组网和转发

1. 创建 Network。
2. 创建公网入口 Entry。
3. 创建转发规则 Forward。
4. 点击 Apply。
5. 在任务中心查看执行结果。

落地/后端机器不需要安装 Agent，只需要在 Forward 中填写 `target_host:target_port`。

## 安全边界

- 不接受任意命令字符串。
- 不执行 `shell -c` / `bash -c` / `eval`。
- 不暴露 raw nft / iptables / ip route 输入。
- `enable_write_actions=false` 时 Agent 拒绝 alpha 写动作。
- alpha 写动作只走固定白名单 action。
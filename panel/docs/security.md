# 安全边界

Leikwan Panel `3.0.0-alpha.4` 是 alpha 测试版，但仍保留明确边界。

## Token

- `LEIKWAN_CONTROLLER_TOKEN`：Agent register/report/tasks/result 使用。
- `LEIKWAN_OPERATOR_TOKEN`：Web 和 Operator API 使用。
- 两类 token 不能混用。
- 日志、events、timeline、raw_json 中不得保存完整 token。

## 命令边界

Panel 不接受：

- 任意 command/cmd/shell 字符串
- `shell -c`
- `bash -c`
- `eval`
- raw nft / iptables / ip route
- `rm`
- `curl | bash` 作为 Agent 任务动作

Agent 只能执行固定 action，并使用固定 argv 或 Go 内部逻辑。

## 写操作边界

`enable_write_actions=false` 时 Agent 拒绝所有 alpha 写动作。

`enable_write_actions=true` 时，Agent 只允许固定白名单 action，例如 EasyTier 配置、Panel nftables/PBR/DDNS 配置、验证任务和带确认的 reboot。

Shell Core `leikwan-toolkit.sh` 不被 Panel 修改。
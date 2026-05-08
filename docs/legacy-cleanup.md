# legacy 清理

v0.4 主流程不再使用旧 0.2/0.3 组件。

旧组件清理入口：

```text
高级功能 -> legacy 清理
```

每一项都需要二次确认，默认不会执行。清理只针对本项目旧版创建的服务、配置和二进制，不会删除用户其它防火墙规则。

当前清理项使用通用中文描述：

- 清理旧 WireGuard 残留
- 清理旧 Phantun 残留
- 清理旧 FRP 残留
- 清理旧 realm 残留
- 清理旧 Xray 测试残留
- 清理脚本生成的 nftables 规则
- 清理 EasyTier 服务和配置

适用场景：

- 从旧版本升级到 v0.4 后，希望清掉不再使用的历史服务。
- doctor 已确认 v0.4 EasyTier + nftables 主链路正常。

建议先备份 `/etc/leikwan-wg-toolkit` 和相关系统配置，再执行 legacy 清理。

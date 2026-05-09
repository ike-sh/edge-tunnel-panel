# legacy 清理

Leikwan Toolkit 1.0.1 主流程只使用 EasyTier、nftables、IPv4 PBR 和 MSS clamp。旧版本残留清理入口：

```text
高级功能 -> legacy 清理
```

每一项都需要二次确认，默认不会执行。清理只针对本项目旧版创建的服务、配置和二进制，不会删除用户其它业务。

当前清理项使用通用描述：

- 清理旧内核隧道残留
- 清理旧 UDP 加速残留
- 清理旧端口代理残留
- 清理旧四层转发残留
- 清理旧测试服务残留
- 清理脚本生成的 nftables 规则
- 清理 EasyTier 服务和配置

建议先备份 `/etc/leikwan-toolkit` 和相关系统配置，再执行 legacy 清理。

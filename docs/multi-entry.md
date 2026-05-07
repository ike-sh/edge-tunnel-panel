# 多公网入口

多入口用于同时管理多台 `cloud-entry`，例如云厂商入口、家宽入口或备用入口。

## entries.tsv

路径：

```text
/etc/leikwan-wg-toolkit/entries/entries.tsv
```

格式：

```text
entry_name  public_host      et_ip        easytier_protocol  easytier_port  weight  enabled
aliyun      192.0.2.10       10.198.1.2   tcp                8301          100     true
tencent     198.51.100.20    10.198.1.3   tcp                8301          50      true
home        home.example.com 10.198.1.4   tcp                8301          20      false
```

要求：

- `entry_name` 唯一。
- `et_ip` 唯一。
- `public_host` 可以是 IP 或域名。
- `enabled=false` 不参与输出和规则生成。

## 权重

脚本不会实现复杂代理层负载均衡，只会按 `weight` 生成推荐顺序。用户可以结合客户端、DNS 或外部负载均衡器自行切换。

## 健康检查

检查项：

- `public_host:easytier_port` 是否可达。
- EasyTier peer 是否可见。
- EasyTier IP 是否可 ping。
- 对应 `ENTRY_PORT` 是否已生成输出。

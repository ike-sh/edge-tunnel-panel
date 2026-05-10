# 初始化向导

Leikwan Toolkit 1.3.0 新增 `lq init`，适合首次部署、重装恢复和不确定当前机器角色时使用。

## 入口

```bash
lq init
lq wizard
lq quickstart
lq init --dry-run
lq init --plan
lq plan
```

`wizard` 和 `quickstart` 是 `init` 的别名。`--dry-run` / `--plan` 只输出计划，不写文件、不启动服务、不应用 nftables / PBR。

## 角色选择

初始化向导会先问这台机器的角色：

```text
1. B：利群主机 / 中转主机
2. A：公网入口
3. 从配置包恢复
4. 仅检查当前状态
```

B 利群主机负责 EasyTier relay、entries、forwards、PBR、DDNS 和 nftables 转发。A 公网入口负责 entry service、端口池和入口网络码部署。

## B 利群主机

B 向导聚合这些步骤：

1. 环境预检
2. 修复 DNS / IPv4 优先
3. 安装 / 修复 EasyTier
4. 生成第一个公网入口接入码
5. 添加后端转发目标
6. 可选配置 PBR
7. 可选启用 DDNS 自动刷新
8. 查看状态总览

如果检测到已有 entries / forwards / pbr 或 network.env，向导会进入维护模式，不会重新初始化 network.env。生成公网入口接入码会复用现有 network name / secret。

## A 公网入口

A 向导聚合这些步骤：

1. 环境预检
2. 粘贴 B 生成的公网入口接入码
3. 安装 / 修复 EasyTier
4. 部署 entry service
5. 配置公网入口端口池
6. 生成入口返回码
7. 查看本机公网入口状态

EasyTier IP 必须是 10.x 虚拟 IP。DDNS 域名应填入公网地址 / 域名字段，不能作为 EasyTier IP。

## 配置包恢复

配置包恢复向导复用：

```bash
lq config inspect /path/to/pkg.tar.gz
lq config import /path/to/pkg.tar.gz
```

导入前会校验 sha256、manifest、checksums，并拒绝路径穿越、绝对路径、symlink 和 hardlink 包成员。redacted 包不能用于完整恢复运行。

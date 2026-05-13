# 快速开始

当前版本：`v0.2.7-test`

## 安装 Controller

```bash
curl -fsSL https://raw.githubusercontent.com/ike-sh/edge-tunnel-panel/main/panel/scripts/install-controller.sh | sudo bash -s -- \
  --version v0.2.7-test
```

打开：

```text
http://服务器IP:18080
```

## 添加节点

1. 进入“节点”页面。
2. 点击右上角“添加节点”。
3. 在“新节点接入”卡片中填写节点名称。
4. 点击“获取一键安装命令”。
5. root 用户复制 root 命令；普通用户复制 sudo 命令。
6. 回到节点页等待上线。

## 快速组网

1. 至少准备两个在线节点。
2. 进入“组网配置”。
3. 选择 A 公网入口节点和 B 落地执行节点。
4. 点击“创建并应用组网”。
5. 等待自动验证，组网卡片显示“组网成功”。

## 创建转发规则

1. 进入“转发规则”。
2. 选择一条已经成功的组网链路。
3. 填写公网监听端口。
4. 填写落地服务器 IP/域名。
5. 填写落地服务器端口。
6. 选择协议和 A 到 B 的传输方式。
7. 点击“创建并应用转发”。

转发链路：

```text
外部客户端
-> A 公网服务器公网端口
-> A nftables
-> EasyTier 隧道或 B 公网直连
-> B 节点
-> B nftables
-> 落地服务器 IP/域名:端口
```

## 测试命令

落地服务器：

```bash
python3 -m http.server 8080 --bind 0.0.0.0
```

外部客户端：

```bash
curl -v http://入口公网IP:18081/
```

# Topology

## 组网

```text
A 公网入口节点
<-> EasyTier
<-> B 落地执行节点
```

## 转发

```text
外部客户端
-> A 公网服务器公网端口
-> A nftables
-> EasyTier 隧道或 B 公网直连
-> B 节点
-> B nftables
-> 落地服务器 IP/域名:端口
```

## PBR

PBR 作用在 B 节点上，用于给转发流量打 mark，并通过自动识别到的线路组 route table 选择出口线路。

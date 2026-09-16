# kwrt-router (192.168.6.1) 运维操作时间线

> Kwrt 25.12-SNAPSHOT（OpenWrt 分支，mediatek/filogic，aarch64）。
> 跑 Passwall（xray 全局模式，节点 `cyp-tizi`）。SSH 直连 `root@192.168.6.1`。
> 与 `home-router`（`192.168.2.1`，经 mac-mini 跳板）不是同一台设备。
> WAN 为 DHCP，上级网关 `192.168.1.1`（光猫），路由器 WAN IP `192.168.1.2`。

## 2026-09-16 11:5x CST - 排查微信发图失败，WAN/LAN MTU 降为 1480

- 服务器：`192.168.6.1`（Kwrt 路由器）
- 操作人：`Claude`
- 原因：Mac 版微信发图片持续失败（红色感叹号），发文字正常。用户怀疑 Passwall 导致，要求检查日志。
- 排查结论：**与 Passwall 无关**，根因是上级链路 PMTU 只有 1480 而路由器按 1500 转发，形成 PMTUD 黑洞。
  - Passwall 日志（`/tmp/log/passwall.log`）最近两次重载（10:52、11:28）均为「运行完成」，无任何错误。
  - 微信服务器 IP（`183.131.41.124`、`61.151.230.185`、`180.101.242.212` 等）同时命中 `psw_chn_static` 与 `psw_white` 两个直连白名单，nftables 动作为 `return`，**未走代理**。
  - 从 Mac 实测微信图片 CDN `mmsns.qpic.cn` HTTP 400、`szminorshort.weixin.qq.com` HTTP 200，TCP 通道正常。
  - `short.weixin.qq.com` 用 curl 握手失败（`SSL_ERROR_SYSCALL`）属正常现象——该域名跑微信私有 mmtls 协议，会拒绝标准 TLS Client Hello，非故障。
  - MTU 探测：`ping -D -s 1472`（MTU 1500）FAIL，`-s 1452`（MTU 1480）OK → 上级实际 PMTU = 1480。
  - 症状只出现在发图：文字包小不触发；发图走 QUIC over UDP 大包，而 fw4 的 MSS clamp 规则 `tcp option maxseg size set rt mtu` **只对 TCP 生效，UDP 无钳制机制**，故大包被静默丢弃。
- 影响：
  - WAN（`wan`）与 LAN（`br-lan`）接口 MTU 由 1500 降为 1480。
  - 两次 `/etc/init.d/network reload`，每次全屋断网约 5-15 秒。
  - Passwall 随 network reload 自动重启，防火墙规则（`table inet passwall`）完好。
- 备份：
  - `/etc/config/network.bak.20260916`
  - 回滚基线：变更前 `network.wan.mtu` 与 `network.lan.mtu` **均未设置**（走默认 1500），`wan` 的 device 段只有 `name` + `macaddr`，无 `mtu`。
- 回滚方式：
  ```bash
  uci delete network.wan.mtu
  uci delete network.lan.mtu
  uci delete network.cfg0b0f15.mtu   # wan device 段的 mtu
  uci commit network
  /etc/init.d/network reload
  ```
  或直接恢复 `cp /etc/config/network.bak.20260916 /etc/config/network && /etc/init.d/network reload`。
- 变更时序：
  1. `cp /etc/config/network /etc/config/network.bak.20260916` 备份。
  2. `uci set network.wan.mtu=1480`、`uci set network.lan.mtu=1480`，`uci commit network`。
  3. `/etc/init.d/network reload`（后台 nohup 执行，避免 SSH 断连打断）。
  4. 验证发现 **LAN 生效 1480，WAN 仍为 1500** —— WAN 是 DHCP 协议，`interface` 段的 `mtu` 未应用到接口。
  5. `uci add network device` 新建段并设 `name=wan`、`mtu=1480`，commit 后发现与已存在的 `@device[7]`（`name=wan` + `macaddr`）**同名冲突**。
  6. `uci delete network.@device[8]` 删除重复段，改为 `uci set network.@device[7].mtu=1480` 合并进原有段（保留 macaddr），`uci commit network`。
  7. 再次 `/etc/init.d/network reload`。
- 验证：
  - `ip link show wan` → `mtu 1480`；`ip link show br-lan` → `mtu 1480`。
  - reload 日志 `/tmp/mtu-reload2.log` 为空，无报错。
  - Passwall `xray` + `chinadns-ng` 两进程在线，`nft list tables` 仍有 `table inet passwall`。
  - 默认路由正常：`default via 192.168.1.1 dev wan`。
  - 微信 CDN：`mmsns.qpic.cn` HTTP 400、`szminorshort.weixin.qq.com` HTTP 200。
  - 大包链路：从 Mac 下载阿里云镜像 3,000,001 bytes 完整通过，速度 16.4 MB/s。
- 备注：
  - Mac 本机 `en0` 仍为 MTU 1500，`ping -D -s 1472` 依旧 FAIL 属**预期**。关键差别在于路由器现在会主动回 ICMP「需要分片，MTU=1480」，客户端可正常 PMTUD 降速重发；改动前路由器自认 1500 可转发，包丢在上游且无 ICMP 返回，形成黑洞。
  - 若后续仍偶发大包问题，可考虑把 MTU 再降至 1460（PPPoE 常见值）或为 UDP 增加分片处理。

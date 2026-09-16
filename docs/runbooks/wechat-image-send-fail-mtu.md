# 微信发图片失败（发文字正常）— MTU 黑洞排查手册

**适用症状**：微信能发文字、能收消息，但发图片一直转圈，最后红色感叹号。
网页浏览、看视频都正常，唯独发图挂。

**结论先行**：这类问题九成不是代理/科学上网的锅，是**路由器 MTU 高于链路实际能力**。
按下面三步走，10 分钟能定位。

---

## 第一步：确认是不是 MTU 问题（1 分钟）

在**连着这个 WiFi 的电脑**上开终端，跑：

```bash
# -D = 禁止分片。payload + 28 = 实际 MTU
ping -D -s 1472 -c 1 -W 2 223.5.5.5   # 探 MTU 1500
ping -D -s 1452 -c 1 -W 2 223.5.5.5   # 探 MTU 1480
```

- Linux 上如果 `-D` 不认，用 `ping -M do -s 1472 -c 1 223.5.5.5`
- Windows 用 `ping -f -l 1472 223.5.5.5`

**判读**：

| 1472 | 1452 | 结论 |
|------|------|------|
| OK   | OK   | 链路支持 1500，**不是 MTU 问题**，去查别的 |
| FAIL | OK   | 链路实际 PMTU = 1480 → **就是这个毛病，继续第二步** |
| FAIL | FAIL | PMTU 比 1480 还低，继续往下探 1432（MTU 1460）、1412（MTU 1440） |

---

## 第二步：为什么偏偏是发图（理解原理，方便说服自己）

- **发文字**：包很小，远不到 MTU 上限，怎么都能过
- **发图片**：上传时塞满整个包，一旦超过链路实际 MTU 就被丢弃

关键在于路由器如果自己也配成 1500，它会认为这包能转发，直接丢给上游；
上游丢弃且**不回 ICMP 通知**，客户端什么反馈都收不到，只能干等超时 —— 这叫 **PMTUD 黑洞**。

**为什么网页正常、微信发图挂**：OpenWrt 防火墙有条 MSS 钳制规则
`tcp option maxseg size set rt mtu`，它会自动帮 **TCP** 连接协商合适的包大小，
所以网页浏览没事。但微信发图走的是 **QUIC over UDP**，
**UDP 没有任何 MSS 钳制机制**，大包就这么被静默吃掉了。

---

## 第三步：改路由器 MTU（OpenWrt / Kwrt）

SSH 登上路由器。**先备份**：

```bash
cp /etc/config/network /etc/config/network.bak.$(date +%Y%m%d)
```

记下当前值（回滚基线），很可能是「未设置」即默认 1500：

```bash
uci get network.wan.mtu 2>/dev/null || echo "wan.mtu 未设置(默认1500)"
uci get network.lan.mtu 2>/dev/null || echo "lan.mtu 未设置(默认1500)"
ip link show wan | grep -o "mtu [0-9]*"
```

### 改 LAN

```bash
uci set network.lan.mtu='1480'
```

### 改 WAN —— 这里有坑

**如果 WAN 是 `proto dhcp` 或 PPPoE，写 `network.wan.mtu` 不生效**，
必须写到 `device` 段。先查有没有现成的：

```bash
uci show network | grep -E "^network\.@?device" | grep -B1 -A2 "name='wan'"
```

- **已有** `name='wan'` 的 device 段（通常带 macaddr）→ 直接在那段上加 mtu：
  ```bash
  uci set network.@device[7].mtu='1480'    # 把 7 换成实际序号
  ```
- **没有** → 新建一个：
  ```bash
  IDX=$(uci add network device)
  uci set network.$IDX.name='wan'
  uci set network.$IDX.mtu='1480'
  ```

> ⚠️ 别在已有 `name='wan'` 段的情况下再新建一个同名段，会冲突。

### 提交并重载

```bash
uci commit network
# 放后台执行，避免 reload 把自己的 SSH 打断导致命令只跑一半
nohup sh -c "sleep 2; /etc/init.d/network reload" >/tmp/mtu-reload.log 2>&1 &
```

全屋断网约 5-15 秒，等网络恢复。

### 验证（必须逐个接口看，别只看 uci）

```bash
ip link show wan | grep -o "mtu [0-9]*"      # 应为 1480
ip link show br-lan | grep -o "mtu [0-9]*"   # 应为 1480
cat /tmp/mtu-reload.log                       # 应为空
```

常见半生效状态：**LAN 改成功了、WAN 还是 1500**，就是上面那个 device 段的坑。

---

## 常见疑问

**Q：本机网卡要不要也改成 1480？**
不用。路由器改好后会主动回 ICMP「需要分片，MTU=1480」，客户端自动降包重发。
本机锁 1480 反而会在去公司、用热点等支持 1500 的网络里白白损失效率。

**Q：改完后本机 `ping -D -s 1472` 还是 FAIL，是不是没修好？**
**正常的。** `-D` 强制禁止分片，本机网卡还是 1500 当然过不去。
判断标准是**实际发图能不能成**，不是这条诊断命令。

**Q：改完发图还是失败？**
说明 ICMP 也被中间设备拦了（PMTUD 依然黑洞）。先在本机临时验证：
```bash
sudo ifconfig en0 mtu 1480    # macOS，重启即恢复，零风险
```
有效的话再考虑持久化，或者把路由器降到 1460（PPPoE 常见值）。

**Q：怎么回滚？**
```bash
cp /etc/config/network.bak.YYYYMMDD /etc/config/network
/etc/init.d/network reload
```

---

## 别被这个假象带偏

用 curl 测 `short.weixin.qq.com` 会报 `SSL_ERROR_SYSCALL` 握手失败 —— **这是正常的**，
该域名跑微信私有 mmtls 协议，会拒绝标准 TLS Client Hello，不是故障，别顺着这条线追。

想验证微信链路通不通，测这两个标准 HTTPS 的：

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://mmsns.qpic.cn/                # 400 = 正常
curl -s -o /dev/null -w "%{http_code}\n" https://szminorshort.weixin.qq.com/   # 200 = 正常
```

## 如果同事在用 Passwall，怎么快速洗清嫌疑

```bash
# 1. 看日志有没有报错
tail -40 /tmp/log/passwall.log

# 2. 确认微信 IP 是直连而非走代理（命中 psw_chn_static / psw_white 即为直连放行）
nslookup mmsns.qpic.cn 127.0.0.1          # 先拿 IP
nft get element inet passwall psw_chn_static "{ 183.131.41.124 }"
nft get element inet passwall psw_white "{ 183.131.41.124 }"
```

两条都命中就说明微信流量根本没进代理，可以放心排除 Passwall。

---

*本手册来自 2026-09-16 的一次实际排查，完整过程见 `docs/operations/kwrt-router-192-168-6-1.md`。*

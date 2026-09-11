# km-landui 运维操作时间线

## 2026-09-11 14:00 CST - 把 kh-tizi 写成原生 VLESS outbound

- 服务器：`km-landui`
- 操作人：`Grok`
- 原因：Tun 已启动，但 `curl https://www.google.com` 仍 RST。`www.google.com` 被污染成 Facebook IP（`157.240.7.20`）。
- 影响：ShellCrash 短暂重启。SSH 保护规则仍在，会话未断。出国流量现走 `kh-tizi`（tizi `74.211.103.83`）。
- 备份：`/etc/ShellCrash/jsons/config.json.bak.20260911`

### 根因

`crashcore=singboxr`，实际二进制是官方 **sing-box 1.13.14**。它不把 `providers/uri_group` 里的 `vless://` 分享链接展开成节点。URLTest 组只剩占位 `Compatible`（Direct），DNS/443 都从昆明直出。

### 做了什么

从 `providers_uri.cfg` 生成原生 `vless` outbound `kh-tizi`（REALITY / vision），写入 `jsons/config.json`；selector / Uri_group 指向该节点。去掉无效的 `providers` 块。

### 验证

- API：`kh-tizi` type=VLESS，urltest delay **173ms**
- `getent www.google.com` → `142.251.151.119`（真 Google，不再是 Facebook）
- `curl https://www.google.com` → **http=200**（透明代理）
- Cloudflare trace：`ip=74.211.103.83` `loc=US`

回滚：`cp -a /etc/ShellCrash/jsons/config.json.bak.20260911 /etc/ShellCrash/jsons/config.json && systemctl restart shellcrash`

## 2026-09-11 13:14 CST - ShellCrash 本机 Tun 放行入站回程后启动

- 服务器：`km-landui`（`43.228.79.237:28285`）
- 操作人：`Grok`
- 原因：用户要继续用本机 Tun 透明代理，但不能再掐 SSH。
- 影响：`shellcrash.service` 现为 **active**（仍 **disabled**，开机不自启）。SSH / derper / RustDesk 入站回程不再进 `utun`；本机主动出站仍走 Tun。
- 备份：
  - `/etc/ShellCrash/starts/fw_nftables.sh.bak.20260911`
  - `/etc/ShellCrash/starts/afstart.sh.bak.20260911`
  - `/etc/ShellCrash/configs/task/afstart.bak.20260911`
- 回滚：把两个 `.bak.20260911` 拷回后 `systemctl stop shellcrash`。

### 做了什么

1. 新增 `/etc/ShellCrash/configs/fw_protect_inbound.sh`：`ct direction reply return` + `tcp sport 28285 return`
2. 在 `fw_nftables.sh` 的 OUTPUT 建链、JUMP 之前 `add` 这两条（无窗口）
3. `afstart.sh` 在 `fw_start.sh` 之后再 `insert` 一次；`configs/task/afstart` 作第三备份
4. `systemd-run` 180s 看门狗：没有 `/tmp/shellcrash-ssh-ok` 就停服务。新 SSH 通了之后已停掉看门狗

### 验证

- 原 SSH 会话未断；`ssh -o ControlMaster=no km-landui` 新建也通
- nft OUTPUT 顺序：dns / mark / skgid → **reply + sport 28285** → 保留地址 → `mark set 0x1ed4`
- `CrashCore` 听 `7890` / `9999`，`utun` UP
- 节点组当前落到 Direct，出国流量还没走代理（另案）

升级 `starts/*.sh` 后必须重打补丁。详见 `docs/solutions/km-landui/runtime-errors/shellcrash-tun-kills-ssh-2026-09-11.md`。

## 2026-09-11 12:51 CST - 排查 ShellCrash 启动后 SSH 断连（只读）

- 服务器：`km-landui`（`43.228.79.237:28285`）
- 操作人：`Grok`（只读；未改配置、未启停服务）
- 原因：用户在本机装了 [ShellCrash](https://github.com/juewuy/ShellCrash)；`crash` 菜单选启动服务后 SSH 立刻断开，必须重启机器才能再连上。
- 影响：无配置变更。当前 `shellcrash.service` 为 `disabled` + `inactive`，`.dis_startup` 存在，重启后不会自启，所以现在 SSH 是通的。
- 备份：无（只读）。
- 回滚：无变更。

### 现场状态

| 项 | 值 |
| --- | --- |
| OS | Ubuntu 22.04，内核 `6.8.0-1065-azure`，主机名 `ldclouda31514` |
| 当前 uptime | 约 14 分钟（用户重启后恢复 SSH） |
| ShellCrash | `/etc/ShellCrash`，版本 `1.9.5beta3`，内核 `singboxr 1.13.14` |
| systemd | `disabled` / `inactive` |
| 透明代理 | `firewall_area=2`（仅本机）+ `redir_mod=Tun` + `common_ports=OFF` + `firewall_mod=nftables` |
| 面板端口 | `9999`；mixed-port `7890` |

### 复现时间线（上一次启动，journal `-b -1`）

全部 UTC：

1. `04:29:58` — `root` 从 `112.117.55.212` SSH 登录 `:28285`
2. `04:30:28` — `systemd` `Starting ShellCrash Core...`
3. `04:30:30` — 内核 `utun` 起来；CrashCore 调 `resolvectl domain utun ~.` / `default-route utun true` / `dns utun 198.18.0.2`（本机没有 systemd-resolved，这三步失败，但 TUN 已在）
4. `04:30:31` — `Started ShellCrash Core`（`afstart.sh` 下 nftables OUTPUT mark + `ip route add default dev utun table …`）
5. `04:30:32` — `sshd: Read error from remote host 112.117.55.212 port 14839: Connection reset by peer`

同一秒 `derper` 到同一客户端 IP 的已建连也被 RST。2026-09-10 08:21 UTC 是同一模式：启动后 1 秒 SSH + 多条 DERP 连接一起 RST。

### 根因

本机透明代理（仅本机 + Tun + 拦截全部端口）把 **sshd 回程包** mark 进 `utun`。SSH 源端口是 `28285`（不在默认 22），客户端回程是高位 ephemeral 端口；`common_ports=OFF` 时 nftables **不按目的端口放行**，已建立 SSH 和新建 SSH 的 SYN-ACK 都被劫持。sshd 本身没挂，所以只能重启清掉 TUN / nft / policy routing。

详解与推荐改法：`docs/solutions/km-landui/runtime-errors/shellcrash-tun-kills-ssh-2026-09-11.md`。

**未改 ShellCrash 配置。** 下次启动前需要先改模式，否则会再次锁死 SSH。

## 2026-09-03 14:41 CST - derper 首页改为 Coming soon

- 服务器：`km-landui`（`derp.nanyahui.com`）
- 操作人：`Grok`
- 原因：默认首页会写出 Tailscale / DERP / 文档链接；用户要求页面只显示大大的 `Coming soon`，源码里也不留其它信息。
- 影响：`derper` 短暂重启（数秒）。数据面随后 `debug derp 900` 仍成功。RustDesk 未动。
- 备份：`/root/backup/derper-home-20260903-063905/derper.bin`（改首页前的二进制）

### 做了什么

官方 `-home` 只支持默认页 / 空白 / 跳转 URL，没有自定义 HTML。按 v1.96.5 源码改首页模板后重编 `/root/go/bin/derper`（`-trimpath -ldflags=-s -w`），编译树随即删除，盘上不留补丁源码。

### 验证

`curl https://derp.nanyahui.com/` 仅：

```html
<!DOCTYPE html>
<meta charset="utf-8">
<title>Coming soon</title>
<center><h1><font size="7">Coming soon</font></h1></center>
```

无 Tailscale / DERP / 文档链接。`tailscale debug derp 900`：Successfully established a DERP connection。

### 回滚

```bash
cp -a /root/backup/derper-home-20260903-063905/derper.bin /root/go/bin/derper
systemctl restart derper
```

## 2026-09-03 13:02 CST - Tailscale ACL derpMap HostName 改为 derp.nanyahui.com

- 操作人：`Grok`（用户已登录 Tailscale console，ego-browser 改 JSON editor 并保存）
- 原因：derper 证书已换成 Let's Encrypt，但 ACL 仍指向 `derp.local`，客户端 SNI 被拒。
- 影响：仅改 cypresso.ai tailnet 的 derpMap 节点主机名；grants / SSH / 其它规则未动。

### 变更

Region 900 节点 `km1`：

- `HostName`: `derp.local` → **`derp.nanyahui.com`**
- 删除 `InsecureForTests: true`
- 保留 `IPv4: 43.228.79.237`、`DERPPort: 443`、`STUNPort: 3478`

控制面已确认：`GET login.tailscale.com/admin/api/acls` 中无 `derp.local`、无 `InsecureForTests`。

### 验证（本机）

```text
tailscale debug derp 900
Successfully established a DERP connection with node "derp.nanyahui.com"
Node "derp.nanyahui.com" returned IPv4 STUN response: ...
```

仅剩无害的 IPv6 失败（该域名没有 AAAA）。`netcheck` Nearest DERP 仍为 Kunming ~9ms，这次 TLS 数据面是真通的。

## 2026-09-03 12:47 CST - derper 换 Let's Encrypt（derp.nanyahui.com）

- 服务器：`km-landui`（`43.228.79.237`）
- 操作人：`Grok`（用户已把 `derp.nanyahui.com` A 到本机）
- 原因：自签 `derp.local` 不合格，自定义 DERP 数据面从未真正工作。
- 影响：derper 短暂重启（约数秒）。RustDesk `hbbs`/`hbbr` 未动，21115–21117 仍通。443 现由 Let's Encrypt 证书提供 HTTPS。80 端口现由 derper 监听（ACME 续期）。
- 备份：`/root/backup/derper-le-20260903-044657/`（旧 unit + `derp.local.crt/.key`）

### 做了什么

1. 核实 DNS：本机 / `1.1.1.1` / `8.8.8.8` / `223.5.5.5` 均为 `derp.nanyahui.com` → `43.228.79.237`；Cloudflare NS 且返回源站 IP（灰云）；无 CAA。
2. `derper.service` 改为  
   `-http-port 80 -certmode letsencrypt -hostname derp.nanyahui.com`（其余 STUN / `verify-clients=false` 不变）
3. `systemctl daemon-reload && restart derper`；autocert 签发成功。

### 验证

| 检查 | 结果 |
| --- | --- |
| Python `ssl` 校验 `derp.nanyahui.com:443` | **OK**，CN/SAN=`derp.nanyahui.com`，签发 Let's Encrypt YE2，有效至 **2026-12-02** |
| `curl -sI https://derp.nanyahui.com/` | HTTP/2 **200** |
| derper 监听 | TCP 80 + 443，UDP 3478 |
| RustDesk | `hbbs`/`hbbr` active；家宽 TCP 21115–21117 OPEN |
| `tailscale debug derp 900` | **仍失败**：ACL 还在用 `HostName=derp.local`，SNI 被 HostWhitelist 拒绝（`tls: internal error`） |

### 你还需要改 Tailscale ACL

把 region 900 节点的 `HostName` 改成 `derp.nanyahui.com`，并去掉 `InsecureForTests`（可保留 `IPv4: 43.228.79.237`）。保存后本机执行：

```bash
tailscale debug derp 900
```

不再报 TLS 错误才算 DERP 真正可用。

### 回滚

```bash
cp -a /root/backup/derper-le-20260903-044657/derper.service /etc/systemd/system/derper.service
systemctl daemon-reload && systemctl restart derper
```

## 2026-09-03 12:38 CST - 复核 derper 证书不合格（只读，未切证书）

- 服务器：`km-landui`（`43.228.79.237`）
- 操作人：`Grok`（只读；未改 derper / DNS / Tailscale ACL）
- 原因：RustDesk 已通，用户要顺手修自定义 DERP 证书。
- 影响：无配置变更。梯子客户端**不装**（GitHub 已通，Docker Hub/Google 目前用不上）。

### 证书为什么不合格

- 现证：自签 `CN/SAN=derp.local`，且 `Basic Constraints: CA:TRUE`（2026-04-15 ~ 2036-04-12）
- 本机 `tailscale debug derp 900` 仍报：  
  `x509: “derp.local” certificate is not standards compliant`
- STUN 是好的：`netcheck` Nearest DERP **Kunming 8.8ms**（UDP 3478），所以看起来「很近」，TLS 数据面其实没连上
- `InsecureForTests: true` 也救不了「standards compliant」这一关；`.local` 自签不是解

### 现场条件

| 项 | 结果 |
| --- | --- |
| TCP 80 从家宽 | **RST**（安全组已放行，本机无进程监听）→ HTTP-01 可用 |
| `derp.skysms.xyz` 等候选 | **无 A 记录**；`43.228.79.237` 无 PTR |
| derper | `-certmode manual -hostname derp.local -http-port -1`，占 443 |

### 下一步（等 DNS）

1. 用户把 `derp.skysms.xyz`（建议，与 `tz`/`cyp-tz`/`ddy-tizi.skysms.xyz` 同区）A 到 `43.228.79.237`
2. derper 改 `-certmode letsencrypt -hostname derp.skysms.xyz -http-port 80`（本机申请并续期）
3. Tailscale ACL derpMap `HostName` 改为该域名，去掉 `InsecureForTests`
4. `tailscale debug derp 900` 无 TLS 错误才算修好

## 2026-09-03 11:20 CST - 评估本机出站「开梯子」（只读）

- 服务器：`km-landui`（`43.228.79.237`）
- 操作人：`Grok`（只读；未装 clash/xray、未改路由、未动 tizi 族）
- 原因：用户想在本机开梯子，以便访问 Docker Hub / GitHub / Google。
- 影响：无配置变更。

### 出站实测

| 目标 | 结果 |
| --- | --- |
| `github.com` / `ghcr.io` | **已通**（200 / 405） |
| `google.com` / `hub.docker.com` / `registry-1.docker.io` | **超时**（被墙） |
| `tizi` `74.211.103.83:443` | OPEN，ping ~175ms |
| `tizi-ddy` `80.251.215.131:443` | OPEN，ping ~204ms |
| `nyh-prod` `47.239.167.8:443` | FAIL（与此前跨境结论一致） |

本机无 clash / xray / sing-box 客户端。443 仍由 `derper` 占用。

### 结论（未实施）

- **不要在昆明这台机上开代理服务端**（3x-ui / clash 入站）：出口仍在境内，Google / Docker Hub 一样过不了 GFW，还会和 derper 抢 443。
- **正确做法**：当现有 `tizi` / `tizi-ddy` 的**客户端**，本机只监听 `127.0.0.1` mixed/SOCKS，给 docker/git/curl 用。
- **不要 TUN / 改默认路由**：会伤 RustDesk `hbbs`/`hbbr` 与 derper。
- 给 tizi 族加客户端可能闪断代理数据面，需用户确认后再做。

## 2026-09-03 11:04 CST - 部署 RustDesk OSS（hbbs/hbbr 1.1.16）

- 服务器：`km-landui`（`43.228.79.237`）
- 操作人：`Grok`（用户已在云安全组放行 TCP 21115–21117、UDP 21116；被控端全在国内）
- 原因：方案 B，自托管 ID + 中继，替代公网 ToDesk 一类服务。
- 影响：新增 `rustdesk-hbbs` / `rustdesk-hbbr` 常驻进程（约 2–8 MB RSS）；**未**停 `derper`、**未**改 ufw/SSH、**未**开 21118/21119。
- 选型：GitHub 二进制 + systemd（本机 Docker Hub 出站超时，不装 Docker）。
- 客户端填法：`docs/runbooks/rustdesk-km-landui.md`

### 做了什么

1. 家宽复核安全组：未监听时 21115–21117 为 RST（已放行）；21118 仍 TIMEOUT（保持不开）。
2. 下载 `rustdesk-server-linux-amd64.zip` **1.1.16**，sha256 `0565c41affe6c3f409b0bddfaf5a24ccbf3f64f5f8e3fec250b69a0d5f6bdbcf` 校验通过。
3. 系统用户 `rustdesk`；二进制 `/usr/local/bin/{hbbs,hbbr,rustdesk-utils}`。
4. systemd：`hbbr -k _`；`hbbs -r 43.228.79.237:21117 -k _`；`WorkingDirectory=/var/lib/rustdesk-server`；enabled + running。
5. 私钥权限改为 `600`。安装临时目录已删。

### 验证

| 检查 | 结果 |
| --- | --- |
| `systemctl is-active rustdesk-hbbs rustdesk-hbbr derper` | 三个都 active |
| 本机监听 | TCP 21115/21116/21117；UDP 21116。21118/21119 进程在听但安全组未放行 |
| 家宽 TCP | **21115/21116/21117 OPEN**；21118/21119 TIMEOUT；443 仍是 derper |
| 内存 | hbbr ~2 MB、hbbs ~8 MB RSS |

公钥（客户端「密钥」栏）：

```
mLupdW95mI8GfMLicW0sJbHL6tR6IVgyk2HRN6sL+Gs=
```

### 回滚

```bash
systemctl disable --now rustdesk-hbbs rustdesk-hbbr
```

数据与密钥留在 `/var/lib/rustdesk-server/`，需要时可再拉起。云安全组端口由用户自行决定是否收回。

## 2026-09-03 10:45 CST - 评估作为 RustDesk 自托管中继（只读）

- 服务器：`km-landui`（`43.228.79.237`，昆明 / 电信云南 IDC `AS134765`，主机名 `ldclouda31514`）
- 操作人：`Grok`（只读；未改防火墙、未装包、未停 derper）
- 原因：方案 B（要控不在 Tailscale 上的公网/客户机器）。用户提议用这台「空闲」昆明 VPS，并担心 GFW。
- 影响：无配置变更。
- 回滚方式：无需回滚。

### 现场基线（不是空机）

| 项 | 实测 |
| --- | --- |
| 规格 | 2 vCPU / 1.8 GiB RAM / 39G 盘（剩 22G）/ swap 3.8G；Hyper-V（Azure 内核） |
| 负载 | up 138 天；load 0.01；内存 available 1.2 GiB |
| 已有服务 | **`derper.service` 仍在跑**：TCP 443 + UDP 3478（自签 `derp.local`，证书不合格，DERP 实际不可用） |
| Docker | **未安装** |
| OS 防火墙 | ufw inactive；iptables `INPUT ACCEPT` |
| 端口 21115–21119 | 本机未监听 |

本机访问：`github.com` / `rustdesk.com` / `ghcr.io` 通；`google.com`、`hub.docker.com`、`registry-1.docker.io` **超时**（出站被墙）。`1.1.1.1` ping 68ms。

### 路径实测（GFW / 跨境）

| 源 | 到 `43.228.79.237` | 结果 |
| --- | --- | --- |
| 家宽（滇，本机） | ICMP ~6.7ms；TCP 443 / SSH 28285 | **通** |
| `tizi-ddy`（境外 `80.251.215.131`） | ICMP ~178ms；TCP 443 / 28285 | **通** |
| `nyh-prod`（香港阿里云） | ICMP 100% 丢；TCP 443 / 28285 | **全不通** |

家宽对未监听的 TCP 21116 是 **SYN 超时**（不是 RST）→ 云前置/安全组在丢未放行端口，部署时必须在厂商控制台放行，不能只改 ufw。

### 结论（未部署）

- **控国内机器：适合。** 境内到昆明不走 GFW；家宽 RTT ~7ms。这比把中继放 `nyh-prod` 更合理。
- **控香港/部分境外云主机：不适合当唯一中继。** 香港阿里云现在完全打不到这台机。
- **不要用 Docker Hub 拉镜像**（出站超时）；若部署，用 GitHub release 二进制 + systemd，与现有 derper 共存（RustDesk 不抢 443）。
- 用户观感「空着」不准确：derper 仍 enabled 且占 443，只是 DERP 因证书未生效。本次未停。

部署属另开确认（装包、开安全组端口）。

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`km-landui`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：CLEAN。ioc=0。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

服务器：`km-landui`  
- SSH：`ssh km-landui`（`~/.ssh/config` → `root@43.228.79.237:28285`）  
- 用途：公网节点，曾作为 Tailscale 自定义 DERP（辅助打洞 / 中继）  
- 当前策略（2026-07-10）：**保留机器与 SSH，暂不关停**；derper 问题有空再修。日常 Tailscale / MSSQL 不依赖本机（家宽节点已靠独立 UDP 端口建立 direct）。

## 2026-07-10 11:36 CST - 记录：derpMap 已下发但证书不合格导致未生效

- 服务器：`km-landui`（`43.228.79.237`）
- 操作人：`Grok` + 用户确认（只记问题，不关停、不改机）
- 原因：排查内网 MSSQL 经 Tailscale 极慢时，用户说明本机为辅助打洞服务器；需沉淀「为何 ACL 里加了 derpMap 却像没生效」。
- 现状（只读确认）：
  - 进程：`derper.service` active  
    ` /root/go/bin/derper -a :443 -http-port -1 -certmode manual -certdir /etc/derper/certs -hostname derp.local -verify-clients=false -stun -stun-port 3478`
  - 证书：`/etc/derper/certs/derp.local.crt`（自签，CN/SAN = `derp.local`，有效期约至 2036）
  - 监听：TCP `443`（DERP）、UDP `3478`（STUN）；HTTP 关闭（`-http-port -1`）
  - Tailnet ACL **已下发**自定义区：RegionID `900`，RegionCode `km`，节点 `derp.local` / `43.228.79.237:443`，`InsecureForTests: true`
- **问题结论：derpMap 已下发，但因证书不合格而没生效。**
  - 客户端 `tailscale debug derp 900` / `tailscale debug derp km` 报错：  
    `tls: failed to verify certificate: x509: "derp.local" certificate is not standards compliant`
  - STUN 仍可能测出较低 RTT，netcheck 会显示 Nearest DERP 为 Kunming / `km`，造成「区域很近」的假象；**数据面 TLS 握手失败，自定义 DERP 实际不可用**
  - 状态里的 `relay "km"` 表示 home region 代号，**不代表流量成功经过 km-landui**
- 影响：本次未修改本机服务、未关停云主机、未改 ACL。Tailscale 主路径依赖官方 DERP + 家宽 direct（见 `docs/operations/mssql-ref.md` / `pve.md` 2026-07-10 条目）。
- 回滚：无配置变更。
- **下次若仍需要本机当自定义 DERP**（用户约定）：
  1. 给 `43.228.79.237` **解析一个真域名**（不要再用 `derp.local`）。
  2. 用该域名申请 **Let's Encrypt** 证书（derper 可用 `-certmode letsencrypt`，或 manual 指向 LE 证书路径）。
  3. 更新 derper `-hostname` / cert 路径，以及 ACL derpMap 中的 `HostName`（可保留 `IPv4: 43.228.79.237`）。
  4. 验证：`tailscale debug derp <RegionID>` 无 TLS 错误；再观察 direct 失败时中继是否走该节点。
  5. RegionCode 建议避免与官方混淆（例如用 `km-landui` / 高位 RegionID，不要 silently 覆盖认知上的官方 `km`）。
- 不建议：把 derper 迁到 `nyh-prod`（生产机、443 已被 nginx 占用、业务容器多）。

## 机器速查

| 项 | 值 |
|----|-----|
| 公网 IP | `43.228.79.237` |
| SSH | 端口 `28285`，用户 `root` |
| OS | Ubuntu 22.04 |
| derper 单元 | `/etc/systemd/system/derper.service`（`-certmode letsencrypt -hostname derp.nanyahui.com -http-port 80`） |
| DERP 域名 | `derp.nanyahui.com` → `43.228.79.237` |
| 证书目录 | `/etc/derper/certs/`（LE：`derp.nanyahui.com`；旧自签 `derp.local.crt/.key` 仍在） |
| RustDesk | OSS 1.1.16；`rustdesk-hbbs` / `rustdesk-hbbr`；数据 `/var/lib/rustdesk-server/`；客户端见 `docs/runbooks/rustdesk-km-landui.md` |
| 相关 tailnet | `cypresso.ai` / MagicDNS `taila93443.ts.net` |
| ACL 自定义区（截至记录时） | RegionID `900`，code `km`，`InsecureForTests: true` |

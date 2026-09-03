# km-landui 运维操作时间线

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
| derper 单元 | `/etc/systemd/system/derper.service` |
| 证书目录 | `/etc/derper/certs/`（当前 `derp.local.crt` / `.key`） |
| RustDesk | OSS 1.1.16；`rustdesk-hbbs` / `rustdesk-hbbr`；数据 `/var/lib/rustdesk-server/`；客户端见 `docs/runbooks/rustdesk-km-landui.md` |
| 相关 tailnet | `cypresso.ai` / MagicDNS `taila93443.ts.net` |
| ACL 自定义区（截至记录时） | RegionID `900`，code `km`，`InsecureForTests: true` |

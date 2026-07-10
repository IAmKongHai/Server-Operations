# km-landui 运维操作时间线

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
| 相关 tailnet | `cypresso.ai` / MagicDNS `taila93443.ts.net` |
| ACL 自定义区（截至记录时） | RegionID `900`，code `km`，`InsecureForTests: true` |

# home-router 运维操作时间线

## 2026-11-14 13:58 CST - 验证 PassWall 直连列表加入 `qingfan.app` 后的路径（只读）

- 服务器：`home-router`（用户在 Web 界面把 `qingfan.app` 加进 PassWall 直连列表），验证端 `mac-mini`，对端 `qingfan-prod`（`8.217.180.182`）
- 操作人：用户（改规则）；Claude Code（只读验证）
- 影响：Claude 只做了只读验证，路由器没改。
- 回滚方式：在 PassWall 直连列表删掉 `qingfan.app`。
- 验证：
  - 刚改完的前两次请求（`05:56:55`、`05:57:07` UTC）在 `qingfan-prod` nginx 里仍是 `89.208.242.203`（`tizi-cyp`）；TCP connect 只要 3–6 ms，是被本地透明代理接走的。
  - `05:57:41` 起变成直连：来源 IP `112.117.45.82`（昆明电信），connect 约 80 ms，总耗时从约 1.27 s 降到约 0.52 s，返回 `200`。说明云南电信目前能直连新 IP `8.217.180.182`。
- 遗留问题：经路由器 DNS（`192.168.2.1`、`:11400`、本地电信 `222.172.200.68`，从家里查 `223.5.5.5` 也一样）解析 `qingfan.app` 仍返回**旧 IP `8.210.153.241`**，而 Cloudflare 权威和境外查询都已是 `8.217.180.182`。旧 IP 从家里直连超时（`curl` 10 s 返回 `000`）。mac-mini 本机缓存里目前还是新 IP，所以暂时正常；缓存过期后可能拿到旧 IP 而打不开。

## 2026-11-14 13:55 CST - 本机 ssh 配置新增经 `mac-mini` 跳板访问 `home-router`

- 服务器：`home-router`（`192.168.2.1`），跳板 `mac-mini`（Tailscale `100.108.64.126`）
- 操作人：Claude Code
- 原因：用户在外要访问家里网关管理界面。
- 影响：只改本机 `~/.ssh/config`；路由器和 mac-mini 均无改动。
- 备份：`~/.ssh/config.bak.20261114-router`
- 回滚方式：删掉 `~/.ssh/config` 末尾 `Host home-router` / `Host home-router-web` 两段，或用备份覆盖回去。
- 做了什么：
  - `Host home-router`：`root@192.168.2.1:22`，`ProxyJump mac-mini`。
  - `Host home-router-web`：连 mac-mini，`LocalForward 127.0.0.1:18081 192.168.2.1:80`。
- 验证：
  - 从 mac-mini 探测 `192.168.2.1` 的 `22/80/443` 均可连。
  - `ssh -fN home-router-web` 后 `curl http://localhost:18081/` 返回 `200`。
  - `ssh home-router` 能通过跳板到达路由器，但路由器没有本机公钥，需要手动输入 root 密码（BatchMode 下报 `Permission denied (publickey,password)`，属预期）。

## 2026-09-18 12:17 CST - 清 Passwall/dnsmasq DNS 缓存（zzz.konghai.me）

- 服务器：`home-router`（Kwrt，LAN `192.168.2.1`）
- 操作人：`Grok`（用户要求清路由器 DNS 缓存）
- 原因：Cloudflare 上 `zzz.konghai.me` A 记录已指向 `32.192.186.193`，但家里 DNS 仍返回加记录前的 NODATA，本机 `ping` 报 `Unknown host`。
- 影响：
  - 对系统 dnsmasq（PID `9808`，`:53`）和 Passwall `dnsmasq_default`（PID `10075`，`:11400`）发送 `SIGHUP` 清缓存。进程未换 PID，**未**重启 Passwall / xray / 网络 / 防火墙。
  - 未改 UCI、nft、DHCP。
  - 本机 Wi-Fi DNS 从手工 `192.168.6.1`（办公室路由残留，家里不可达）改回 DHCP 空值，实际使用 `192.168.2.1`。
- 选型：`SIGHUP` 只清缓存、不重载配置文件，比 `/etc/init.d/dnsmasq restart` 或 `passwall restart` 更轻。
- 备份：无（只发信号，无配置改动）。路由器登录凭据未写入本仓库。
- 回滚方式：
  - 路由器侧无需回滚，缓存会按 TTL 重新填充。
  - 本机若回办公室且仍要走 `192.168.6.1`：`networksetup -setdnsservers Wi-Fi 192.168.6.1`
- 变更时序：
  1. 只读确认：Passwall `dns_redirect` 把 LAN UDP/53 转到 `:11400` → chinadns-ng `:15353`；系统 dnsmasq 上游是电信 `222.172.200.68` / `61.166.150.123`。
  2. `kill -HUP` 两个 dnsmasq。
  3. 本机 `networksetup -setdnsservers Wi-Fi Empty`。
- 验证：
  - 路由器 DoH 与 `nslookup zzz.konghai.me 1.1.1.1` 均为 `32.192.186.193`
  - 本机 `dig @192.168.2.1` 与 `@192.168.2.1 -p 11400` 均为 `32.192.186.193`
  - `ping zzz.konghai.me` 已能解析到该 IP；ICMP 无回包（dev-cypresso 未放行 ping，属预期）
  - `curl -sI http://zzz.konghai.me/` 已能连上，返回 nginx **404**（vhost / 证书尚未部署）
- 备注：`konghai.me` 有 HSTS preload，浏览器会强制 HTTPS；当前 443 证书是 `api-icare.cypress.sg`，站点仍打不开，与本次 DNS 无关。

## 2026-06-30 12:45 CST - 移除路由器 Tailscale

- 服务器：`home-router`
- 操作人：`Codex`
- 原因：最初尝试通过 Tailscale 从办公室直接访问家里路由器，后改用 `mac-mini` 作为 SSH 跳板转发路由器 Web 管理端口，路由器本机不再需要 Tailscale。
- 影响：
  - 停止并禁用路由器上的 Tailscale。
  - 卸载 `tailscale` 软件包。
  - 移除为 Tailscale SSH 访问临时新增的 `network.tailscale` 和 `dropbear.tailscale` 配置。
  - 重启 Dropbear，恢复为只监听 `192.168.2.1:22`。
  - 未修改、未重启 Passwall；透明代理配置未变更。
- 备份：
  - `/root/backup-tailscale/remove-20260630-124258/`
  - 包含清理前的 `/etc/config/network`、`/etc/config/dropbear`、`/etc/config/firewall`、`/etc/config/tailscale`、`/etc/init.d/tailscale`、`/etc/tailscale/tailscaled.state` 以及排查过程中产生的 Tailscale init 备份脚本。
- 回滚方式：
  1. 通过 `mac-mini` 跳板 SSH 登录路由器。
  2. 重新安装 `tailscale` 软件包。
  3. 按需从 `/root/backup-tailscale/remove-20260630-124258/` 恢复 Tailscale state、init 脚本、network/dropbear 配置。
  4. 执行 `/etc/init.d/tailscale enable && /etc/init.d/tailscale start`，必要时重新 `tailscale up`。
- 变更：
  1. 停止并禁用 `/etc/init.d/tailscale`。
  2. 删除 `dropbear.tailscale` UCI section。
  3. 删除 `network.tailscale` UCI section。
  4. 执行 `/etc/init.d/network reload` 与 `/etc/init.d/dropbear restart`。
  5. 执行 `opkg remove tailscale`。
  6. 清理卸载后残留的 `/etc/tailscale`、`/var/lib/tailscale`、`/tmp/run/tailscale`、`/tmp/lib/tailscale` 和 `/tmp/lock/procd_tailscale.lock`。
  7. 将 `/etc/init.d/tailscale.bak.*` 移入备份目录，避免 init 目录保留 Tailscale 脚本残留。
- 验证：
  - `opkg list-installed | grep -E '^(tailscale|tailscaled) '` 无输出。
  - `ps w | grep '[t]ailscale'` 无输出。
  - `/etc`、`/tmp`、`/var` 下未发现 Tailscale 残留文件。
  - Dropbear 只监听 `192.168.2.1:22`。
  - Passwall 的 `xray` 仍监听 `:::1080`。
  - 路由器 Web 管理端口 `http://192.168.2.1/` 返回 `HTTP/1.1 200 OK`。
  - 办公室本机通过 SSH 隧道 `http://127.0.0.1:18080/` 返回 `HTTP/1.1 200 OK`。
- 后续：
  - 从办公室访问家里路由器 Web 管理界面时，使用 `ssh -N -L 18080:192.168.2.1:80 mac-mini` 建立本地端口转发。

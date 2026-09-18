# home-router 运维操作时间线

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

# nyh-prod 运维时间线

## 2026-08-20 22:55-23:10 CST - TLS 协议与加密套件收敛（TLSv1.1 下线、3DES 清除）+ preload 范围收敛

- 服务器：`nyh-prod`（`47.239.167.8`）
- 操作人：`Claude`（用户明确要求「ssl_protocols TLSv1.1 都收敛到 1.2/1.3」）
- 原因：接上一条加固。宝塔默认模板给每个 vhost 写死了 `TLSv1.1` 与含 3DES 的套件，
  属已废弃且不安全的配置。

### 影响

- 25 处 `ssl_protocols` 统一为 `TLSv1.2 TLSv1.3`（原 22 处含 `TLSv1.1`）。
- `ssl_ciphers` 统一为纯 ECDHE 套件
  `ECDHE+CHACHA20:ECDHE+AESGCM:ECDHE+AES256:ECDHE+AES128:!aNULL:!eNULL:!MD5:!DSS:!3DES`，
  清除宝塔默认里的 **`EECDH+3DES:RSA+3DES`（Sweet32 CVE-2016-2183）** 与
  **`RSA+AES` 非前向保密套件**。
- 影响面：仅 TLS 1.0/1.1 客户端（Android 4.x、IE10-、老 Java 7）无法握手。
  当前业务无此类客户端，实测全站正常。

### 备份

- `/root/backup/tls-20260820_225544/`（32 个文件：全部 vhost `.conf` + `nginx.conf`）

### 回滚方式

`cp /root/backup/tls-20260820_225544/*.conf /www/server/panel/vhost/nginx/`
→ `nginx -t && nginx -s reload`

### 验证

- TLS 1.1 握手：**被拒绝**（`curl --tlsv1.1 --tls-max 1.1` 失败）
- TLS 1.2 / TLS 1.3：均 200
- 全站 15 个站点 smoke 通过，与变更前逐一对齐，无回归

---

## preload 最终结论（本轮收敛，未提交任何域名）

服务器侧配置已含 `preload` 关键字并就绪，但**未向 hstspreload.org 提交**。
提交需浏览器 + Google 账号，属用户侧动作。实测四项预检结果：

| 注册域 | apex | HTTP 301 | HSTS 头 | www | 结论 |
|---|---|---|---|---|---|
| `ddricher.ai` | 200 | ✅ | ✅ 2 年 | 200 | **可提交，无副作用** |
| `konghai.me` | 200 | ✅ | ✅ 2 年 | **证书不匹配** | 可提交，但 www 会打不开 |
| `acquilangai.com` | **502** | ✅ | ✅ | 502 | 校验会挂，暂不提交 |
| `nanyahui.com` / `.cn` | **NXDOMAIN** | — | — | 证书不匹配 | **用户决定放弃处理** |

### 关键发现：三条 www 记录都指向备案服务商

`www.konghai.me`、`www.nanyahui.com`、`www.nanyahui.cn` 均 CNAME 到
**`dnsbgp.idc-icp.com` → `103.47.81.71`**，该主机返回 `*.lifekey.top` 证书。
早先误判为「悬空 DNS / 子域接管风险」，实为**用户的 ICP 备案服务商记录**，因备案需要不能删。

- 后果：这些 `www.*` 目前 **HTTP 可访问、HTTPS 握手失败**。
- 一旦对应注册域提交 preload，浏览器会强制改写为 HTTPS →
  证书不匹配 → **彻底打不开且不可绕过**（preload 的 HSTS 错误无「继续访问」选项）。
- 因此 `konghai.me` 提交前需权衡；`nanyahui.com/.cn` 因 apex 无 A 记录，
  **技术上根本提交不进去**（校验器读不到 apex 的 HSTS 头），非「接受后果」即可绕过。

### 放弃处理 nanyahui.com / nanyahui.cn（用户决定）

曾评估把两域的 `www`（乃至 apex）指向 `km-landui`（`43.228.79.237`）自建站点配证书。
勘察结论：该机 Ubuntu 22.04，**`:443` 被 `derper` 占用**，无 nginx/docker，需从零搭建；
且只配 `www` 并不能解除 preload 阻塞（阻塞点在 apex）。
成本与收益不匹配，**用户决定放弃这两个域的 preload**。`km-landui` 全程只读勘察，未做任何改动。

### 重要澄清：preload 不解决本次的移动网络证书告警

用户最初的诉求是修复移动网络下 `bnsg.konghai.me` 的证书告警。已确认该告警是
**TLS 层劫持**（证书 SAN 为运营商 IP `117.55.193.146`），**preload 对此无效**。
可用手段仍是 Tailscale Exit Node + 向 10086 / 工信部投诉。
不要为「修复该告警」而牺牲 `www.konghai.me` 去提交 preload。

## 2026-08-20 22:13-22:30 CST - 安全加固：全站 HSTS 规范化 + 93 个安全补丁 + 内核 6.12.48→6.12.101 + 重启

- 服务器：`nyh-prod`（公网 `47.239.167.8`，Debian 13.1）
- 操作人：`Claude`（用户确认执行：HSTS preload、内核升级、其他加固、可随时重启）
- 起因：用户在移动网络访问 `https://bnsg.konghai.me/` 间歇性出现「此连接非私人连接」证书告警。
- **诊断修正（重要）**：证书详情显示 SAN 为 **IP `117.55.193.146`**（国内运营商网段）、签发者 Let's Encrypt
  —— 是**一张合法签发但属于他人的证书**被塞入连接。说明劫持发生在 **TLS 层**，
  而非上一会话推测的「HTTP 首跳明文被劫」。**结论：HSTS preload 挡不住该劫持**
  （浏览器证书校验本就已生效并报警）。真正可用的规避手段是已部署的 Tailscale Exit Node，
  以及向移动/工信部投诉。preload 仍做，但目标是防首跳明文，不是解决本次告警。

### 影响

- 24 个 vhost 的 HSTS 头统一为 `max-age=63072000; includeSubDomains; preload` + `always`
  （原 23/26 缺 `always`，错误响应会丢 HSTS 头；`max-age` 由 1 年提到 2 年）。
- `0.default.conf`（未匹配主机名的兜底 server）**刻意不改**：加 `includeSubDomains; preload`
  会对任何解析到本机 IP 的域名下发 HSTS，波及非自有域名。
- 4 个缺 HTTP→HTTPS 跳转的 vhost 补上 301：`admin.ddricher.ai`、`api.acquilangai.com`、
  `duowei.konghai.me`、`smith.konghai.me`（preload 的强制前置条件）。
- 93 个 Debian-Security 补丁全部安装（libpng / freetype / libheif / libde265 / libaom / openssh 等）。
- 内核 `6.12.48+deb13` → `6.12.101+deb13`，重启生效（此前 257 天未重启）。
- 修复 `grub-pc` 半配置故障（见下），否则会阻塞后续所有 apt 操作。
- apt 镜像由 `mirrors.cloud.aliyuncs.com` 改为 `https://mirrors.aliyun.com`（见下）。

### 备份

- `/root/backup/hsts-20260820_221318/`：全部 vhost `.conf`、`nginx.conf`、
  `dpkg-list-before.txt`、`kernel-before.txt`、`docker-before.txt`、
  `security-updates-pending.txt`、`debian.sources.bak`
- 旧内核 `6.12.48` 与 `6.12.43` 均保留在 `/boot`，GRUB 菜单可回退

### 回滚方式

1. Nginx：`cp /root/backup/hsts-20260820_221318/*.conf /www/server/panel/vhost/nginx/`
   → `nginx -t && nginx -s reload`
2. 内核：重启时在 GRUB 菜单选 `6.12.48+deb13-amd64`（未删除）
3. apt 源：`cp /root/backup/hsts-20260820_221318/debian.sources.bak /etc/apt/sources.list.d/debian.sources`
4. **注意**：HSTS `max-age=2年` 已下发到访问过的浏览器，回滚配置不会撤销客户端已缓存的策略；
   如需撤销必须下发 `max-age=0` 并等待客户端刷新。**但 `preload` 关键字仅是声明，
   未向 hstspreload.org 提交前不产生浏览器内置效果。**

### 变更时序

1. 只读勘察：确认 24 个 vhost 全部已有 SSL+HSTS；DNS 与 HTTPS 可达性普查。
2. 备份 vhost / 包列表 / 内核 / 容器状态到 `/root/backup/hsts-20260820_221318/`。
3. `perl -i -pe` 批量规范化 24 个文件的 HSTS 头；`0.default.conf` 排除。
4. 给 4 个 vhost 插入 `#HTTP-TO-HTTPS-START` 301 跳转块。
   `api.acquilangai.com` 因系人工改过、无 `#SSL-END` 锚点，改锚定 `error_page 497` 单独插入。
5. `nginx -t` 通过 → `nginx -s reload`（平滑，无断连）→ 全站 smoke 通过。
6. **踩坑 1**：`apt-get update` 失败，`mirrors.cloud.aliyuncs.com` 解析到 **`100.100.2.148`**，
   落在 Tailscale CGNAT `100.64/10`，被 `ts-input` 规则 5 `DROP`（与 2026-08-11 记录的
   `100.100.2.136/138` DNS 事故同源，当时的 host route 兜底只覆盖了 DNS，没覆盖镜像）。
   处理：改用 `https://mirrors.aliyun.com`（非 CGNAT 段），**不动 Tailscale 托管的 iptables 链**
   —— 后者会在 tailscaled 重启时被重写，改了也活不过重启。
7. **踩坑 2**：`apt upgrade` 末尾 `grub-pc` 配置失败 —— debconf 里 `install_devices` 记录着
   已不存在的 `/dev/vda`。核实本机实为 **UEFI 启动**（`/sys/firmware/efi` 存在，
   `BootCurrent: 0006`，`grub-efi-amd64-signed` 已装，EFI 分区引导链完整），
   `grub-pc` 属遗留包、不参与实际引导。处理：`debconf-set-selections` 清空 `install_devices`
   → `dpkg --configure -a` 通过，`grub-pc` 恢复 `ii`。
   **若不修，该半配置状态会阻塞内核安装。**
8. `apt install linux-image-amd64` → `6.12.101-1`，initramfs 生成、GRUB 更新、旧内核保留。
9. 重启前核对：docker/nginx/fail2ban/tailscaled/bt/supervisor/ssh 全部 `enabled`；
   9 个容器均有 restart policy；`fix-aliyun-dns-vs-tailscale.service` `enabled`；ufw active。
10. `systemctl reboot`，**30 秒**恢复 SSH。

### 验证

- `uname -r` = **`6.12.101+deb13-amd64`**；`apt-get -s upgrade` 待更新安全包 = **0**，总待更新 = **0**
- 9 个容器全部自动拉起且 `healthy`，与重启前列表**逐一对齐**（无遗漏）
- 服务：docker / nginx / fail2ban / tailscaled / bt / supervisor / ssh / ufw 全部 `active`
- Tailscale：`nyh-prod` `100.78.12.107` 仍 `offers exit node`（用户规避劫持的手段未受影响）
- HSTS 实测：`bnsg.konghai.me`、`konghai.me`、`ddricher.ai`、`load.nanyahui.com`、
  `vip.nanyahui.cn` 均返回 `max-age=63072000; includeSubDomains; preload`
- 301 跳转实测：4 个新增 vhost + 原有域名全部 `http → https` 301
- 站点 smoke（重启后）：`bnsg` / `konghai.me` / `ddricher.ai` / `admin.ddricher.ai` /
  `load.nanyahui.com` / `vip.nanyahui.com` / `vip.nanyahui.cn` / `fa` / `yysg` / `nyh-2025` = 200；
  `load.nanyahui.cn` 301、`center` 302、`smith` 302、`numbers`(Cloudflare) 403 —— 均为应用层原有行为
- **`api.ddricher.ai` 502 系既有故障，非本次引入**：上游 `127.0.0.1:7800` 无监听，
  错误日志自 **2026-02-18** 起累计 32705 条，且重启前 21:33 已是 502（早于本次动手的 22:13）

### 未完成 / 待用户决策：preload 尚未提交

服务器侧已就绪（配置含 `preload` 关键字），但**未向 hstspreload.org 提交任何域名**。
用户选择「5 个域全部立即提交」，实测后发现 **4 个域现在提交会造成生产故障**，故暂停待确认：

| 注册域 | apex | www | 可提交 |
|---|---|---|---|
| `konghai.me` | 200 | **TLS 失败**（`www` 悬空指向 `103.47.81.71`，返回 `*.lifekey.top` 证书） | 否 |
| `nanyahui.com` | **NXDOMAIN** | **TLS 失败**（`103.47.81.71`） | 否 |
| `nanyahui.cn` | **NXDOMAIN** | **TLS 失败**（`103.47.81.71`） | 否 |
| `acquilangai.com` | **502** | **502** | 否 |
| `ddricher.ai` | 200 | 200 | **是** |

- preload 按**注册域**提交且强制 `includeSubDomains`，会波及该域下所有子域（含不在本机的）。
- `nanyahui.com` / `nanyahui.cn` apex 无 DNS 记录，提交会被拒；若强行补 apex 再提交，
  `load.` / `vip.` / `center.` / `fa.` / `yysg.` 等**在产子域**将被连带绑定，
  而 `www.*` 当前 TLS 失败 → 提交通过当天即不可访问，**移出列表需数月**。
- `www.konghai.me` / `www.nanyahui.com` / `www.nanyahui.cn` 同时指向 `103.47.81.71`
  （非本机、非自有证书）—— 属**悬空 DNS 记录 / 子域接管风险**，建议直接在 DNS 侧删除。
  用户已选择「删除该 DNS 记录」，但 DNS 面板操作需用户本人执行。

### 其他待办（本次未做）

- **TLS 协议**：多个 vhost 仍启用 `ssl_protocols TLSv1.1`（已废弃且不安全），
  仅 `api.acquilangai.com` 已收敛为 `TLSv1.2 TLSv1.3`。建议全站统一去掉 TLSv1.1/1.0。
- **CI 部署密钥具备 root**：`/root/.ssh/authorized_keys` 中 3 把 GitHub Actions 部署密钥
  拥有 root 权限，任一仓库 Secrets 泄露即等同 root。属结构性改动，需单独排期。
- **服务监听 `0.0.0.0`**：宝塔面板 10463、Redis 7480 等仅靠云防火墙隔离，缺纵深防御。
- `duowei.konghai.me` 返回 502（既有故障，与本次无关）。

## 2026-08-11 14:23 CST - 部署 Tailscale Exit Node（个人手机固定出口 IP）

- 服务器：`nyh-prod`（公网 `47.239.167.8`）
- 操作人：`Grok`（用户确认执行 plan + 浏览器登录 tailnet + Admin 批准 Exit）
- 计划：`docs/plans/2026-08-11-001-ops-nyh-prod-tailscale-exit-plan.md`
- 原因：单人极小流量，目标 App 需要稳定以本机香港 IP 出网；优先 Exit Node，不稳再考虑 3x-ui。
- 影响：
  - 宿主机安装 Tailscale `1.102.2`，节点名 `nyh-prod`，Tailscale IPv4 `100.78.12.107`，宣告 Exit（`0.0.0.0/0` / `::/0`）。
  - ufw 入站 **UDP 41641**；用户侧阿里云安全组同步已开。
  - 曾短暂导致本机解析失败（见下「踩坑」），已用公网 DNS 修复；业务 `load.nanyahui.com` / `vip.nanyahui.cn` 恢复 200。
  - **未**改 Nginx 80/443、未装 3x-ui、未用 host 网络 Docker。
- 选型：
  - 宿主机 Exit，非 Docker；`--accept-dns=false --accept-routes=false`。
  - 本机不选用任何 exit（服务器只提供出口）。
- 备份：
  - ufw：`/root/backup/ufw-status-20260811_141431.txt`（600）
- 回滚方式：
  1. 客户端取消 Exit Node。
  2. 服务器：`tailscale set --advertise-exit-node=false` 或 `systemctl stop tailscaled`。
  3. 可选：`ufw delete allow 41641/udp`；卸载 tailscale 包（一般不必）。
  4. DNS 相关：`/etc/systemd/resolved.conf.d/99-aliyun-public-dns.conf` 与 `fix-aliyun-dns-vs-tailscale.service` 可按需保留（有 Tailscale 时建议保留）。
- 变更时序：
  1. 只读基线：无 tailscale；`ip_forward=1`；ufw active；公网 `47.239.167.8`；`load` HTTPS 200（`acquilangai.com` 装前即为 502，非本次引入）。
  2. `ufw allow 41641/udp comment 'Tailscale'`（含 v6）。
  3. 官方脚本安装 `tailscale`；`tailscaled` enable+active。
  4. `tailscale up --advertise-exit-node --accept-dns=false --accept-routes=false --hostname=nyh-prod`；用户浏览器登录。
  5. `/etc/sysctl.d/99-tailscale-exit.conf`：`ip_forward=1` + `ipv6 forwarding=1`。
  6. **踩坑修复**：登录后阿里云 VPC DNS `100.100.2.136/138` 落在 Tailscale CGNAT `100.64/10`，`ts-input` 丢弃非 `tailscale0` 的该段回包 → 本机 dig/curl 域名超时。处理：`resolvectl` 与 `/etc/systemd/resolved.conf.d/99-aliyun-public-dns.conf` 改为 `223.5.5.5` / `223.6.6.6`（fallback `8.8.8.8`）；`/usr/local/sbin/fix-aliyun-dns-vs-tailscale.sh` + systemd oneshot + `tailscaled` ExecStartPost 复挂；另加 `100.100.2.x/32` 走 eth0 的 host route 兜底。
  7. 用户 Admin **Approve exit node**。
  8. 本机 Mac 验收：`tailscale set --exit-node=nyh-prod` → `ifconfig.me` = `47.239.167.8`；路径 **`direct 47.239.167.8:41641`**（非仅 DERP）；随后 `tailscale set --exit-node=` 清掉，本地出口恢复。
- 验证：
  - `tailscale status`：`offers exit node`；peer 侧 `ExitNodeOption=true`，AllowedIPs 含 `0.0.0.0/0`。
  - 默认路由仍 `eth0`；CorpDNS/accept-routes 关闭。
  - `ss -ulnp`：`0.0.0.0:41641` / `[::]:41641` = tailscaled。
  - HTTPS：`load.nanyahui.com` / `vip.nanyahui.cn` → 200。
- 后续：
  - **手机验收（2026-08-11，用户确认通过）**：iOS Tailscale Exit Node 选 `nyh-prod` 后，`https://ip.me` 显示 **`47.239.167.8`（香港）**；目标 App 可正常使用。Exit 入口在 **App 主界面**（不在 Settings）。
  - 建议 Admin ACL 限制仅本人可使用该 Exit（若尚未收紧）。
  - 日常观察：大陆网络下若长期仅 DERP / 抖动，再按 plan R11 考虑 3x-ui 冷门端口备选。
  - `acquilangai.com` 502 与本次无关，需另查。

## 2026-08-08 13:15 CST - 全站排查 site path 与 Nginx root 是否同类错位

- 服务器：`nyh-prod`
- 操作人：`Grok`
- 原因：vip 三站修复后，确认是否还有其它站点存在 site.db path / GetRunPath 与 Nginx root 不一致导致 HTTP-01 续期失败。
- 影响：只读扫描（site.db、GetRunPath、nginx conf、证书天数、renew_v2 近期失败域名）；未改配置。
- 结论：
  - 宝塔网站表 16 站用 `panelSite.GetRunPath` 计算 `auth_to` 后，与 Nginx `root` **全部一致**（含已修复的 vip 三站）。
  - 近几日 `renew_v2` 的 HTTP-01 `Invalid response` **仅出现在** 已修复的 `vip.nanyahui.cn` / `vip.nanyahui.com` / `vip-dev.nanyahui.com`。
  - Docker/反代 vhost 证书剩余约 65–82 天，由自定义续期脚本覆盖，当前无过期。
  - 另有废弃域名 `pgadmin.konghai.me` 证书已过期约 181 天（脚本排除清单内，非本次同类问题）。
  - `nyh-2025.konghai.me` 证书约 30 天后到期，path 对齐正常，可走默认续期。
- 备份：无（只读）。
- 回滚：无变更。

## 2026-08-08 13:08 CST - 修复 vip 三站点 SSL 证书 path 错位并续签

- 服务器：`nyh-prod`
- 操作人：`Grok`
- 原因：`vip.nanyahui.cn` / `vip.nanyahui.com` 证书已过期；`vip-dev.nanyahui.com` 站点 path 同样错位，用户确认一并修复。
- 影响：更新宝塔 `site.db` 站点 path 与 `open_basedir`；替换 3 个域名 Let’s Encrypt 证书；`nginx reload`。未重启业务进程/容器/数据库。
- 备份：
  - `site.db`：`/www/backup/site-db/site.db.bak.20260808_130517`
  - 旧证书：`/www/backup/ssl-cert/<domain>/20260808_130517/`
  - Nginx/open_basedir：`/www/backup/nginx-conf/*bak.20260808_130517`
- 回滚：
  1. 恢复证书：`cp -a /www/backup/ssl-cert/<domain>/20260808_130517/* /www/server/panel/vhost/cert/<domain>/`
  2. 恢复 `site.db`：`cp -a /www/backup/site-db/site.db.bak.20260808_130517 /www/server/panel/data/db/site.db`
  3. `nginx -t && service nginx reload`
- 变更：
  1. `site.db` 三站 `path` 统一改为 `/www/wwwroot/nyh-agent-pc-old`，`project_config.php_run_path` 设为 `/public`（与 Nginx root 一致）。
  2. open_basedir 改为 `/www/wwwroot/nyh-agent-pc-old/:/tmp/`。
  3. 用正确 webroot 显式 HTTP-01 续签（需 `PYTHONPATH=/www/server/panel`，否则 `panelSite` 导入 `mod` 失败）：
     - `vip.nanyahui.cn` → 到期 `2026-11-06 04:08:48 GMT`
     - `vip.nanyahui.com` → 到期 `2026-11-06 04:09:10 GMT`
     - `vip-dev.nanyahui.com` → 到期 `2026-11-06 04:09:24 GMT`
  4. `nginx -t && service nginx reload`。
- 验证：
  - 三域名 443 端口证书均为新证，issuer Let’s Encrypt。
  - `https://<domain>/index.html` 均 `http_code=200`、`ssl_verify=0`。
  - `letsencrypt_v2.json` 新 valid 订单 `auth_to=/www/wwwroot/nyh-agent-pc-old/public`。
- 后续：观察次日 `renew_v2` 日志；若再次出现 path 漂移，先对 `site.db` 与 Nginx root 做 diff。

## 2026-08-08 12:58 CST - 排查 vip.nanyahui.cn SSL 证书过期未自动续期

- 服务器：`nyh-prod`
- 操作人：`Grok`
- 原因：`https://vip.nanyahui.cn/index.html` 证书过期，排查为何宝塔自动续期未生效。
- 影响：只读排查（openssl / curl / 读 crontab、site.db、letsencrypt 配置与 renew 日志）；未改配置、未续签、未 reload。
- 结论（根因）：
  - 证书已于 `2026-08-07 16:59:53 GMT`（约 `2026-08-08 00:59 CST`）过期；磁盘与 443 端口证书一致，均为 Let’s Encrypt `R13`，签发于 5/10。
  - 自动续期**有在跑**：root crontab `58 1 * * *` 执行 `acme_v2.py --renew_v2=1`，近几日日志均尝试续签 hash `0e0e4cb7a4cfdc92d383dfc71ad7cf4b`。
  - 失败点是 **HTTP-01 验证 404**：token 写到错误目录 `/www/wwwroot/load.nanyahui.com/.well-known/acme-challenge`，而 Nginx 实际 `root` 为 `/www/wwwroot/nyh-agent-pc-old/public`。
  - 错位来源：`/www/server/panel/data/db/site.db` 中站点路径仍是创建时的 `/www/wwwroot/load.nanyahui.com`（2025-11-11），2026-05-26 前后 Nginx 根已迁到 `nyh-agent-pc-old/public`，但宝塔站点 path 未同步。
  - 自定义 Docker 续期脚本会正确跳过该域名（`managed by bt site/domain table`），因此不会兜底。
  - 连带：`vip.nanyahui.com` 同样 path 错位且证书已过期；`vip-dev.nanyahui.com` path 也不一致，证书仍有效至 2026-08-24。
- 本地验证：将探测 token 写入正确 document root 后，`http://vip.nanyahui.cn/.well-known/acme-challenge/<token>` 返回 200；写在 `load.nanyahui.com` 则 301/找不到。
- 备份：无（只读）。
- 回滚：无变更。
- 待修复（需用户确认后再做）：
  1. 将 `site.db` 中 `vip.nanyahui.cn` / `vip.nanyahui.com`（及可选 `vip-dev`）的 `path` 对齐到实际站点根，或显式用正确 `--path` 续签。
  2. 手动 HTTP-01 续签并 `nginx -t && service nginx reload`。
  3. 观察次日 `renew_v2` 日志是否不再 404。

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`nyh-prod`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：CLEAN。扫 /home /opt /root /var /www /www/wwwroot 等；ioc=0 preinstall=0 lock=0 hook=0。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

## 2026-07-30 15:20 CST - 清理 load.nanyahui.com 站点目录下的两个陈旧备份文件

- 服务器：`nyh-prod`
- 操作人：`Claude`
- 原因：同日 15:05 那次 git 修复后，站点目录仍留着 2026-05-26 的两个临时备份文件。虽已被新 `.gitignore` 规则忽略、不再影响 `git status`，但放在生产站点根目录下无用途，经用户确认后清理。
- 影响：仅删除/移动两个非跟踪的备份文件，未动任何在用代码、配置或证书；站点服务无中断。
- 备份：
  - `_pc_frontend_backup_20260526_161925.tar.gz`（2.3MB，228 项前端页面快照）**未直接删除**，移入 `/www/backup/wwwroot-stale/load.nanyahui.com/`，与 5/20 证书操作沿用同一备份区惯例。
  - `application/middleware.php.bak.20260526_143413` 直接 `rm`：删除前用 `diff` 确认与当前 `application/middleware.php` **逐字节相同**，且当前文件已被 git 跟踪（有版本历史兜底），无信息损失。
- 回滚方式：
  - tar 包：`mv /www/backup/wwwroot-stale/load.nanyahui.com/_pc_frontend_backup_20260526_161925.tar.gz /www/wwwroot/load.nanyahui.com/`
  - middleware 备份：内容与在用文件相同，需要时 `cp application/middleware.php application/middleware.php.bak.<日期>` 即可重建，或从 git 历史取回。
- 变更时序：
  1. `ls -l` + `tar -tzf` + `cat` 逐个查看待删文件的实际内容，确认是 5/26 改前端时打的快照与 middleware 备份。
  2. `diff application/middleware.php application/middleware.php.bak.20260526_143413` → 无差异；`git ls-files application/middleware.php` → 已跟踪。
  3. `mkdir -p /www/backup/wwwroot-stale/load.nanyahui.com` 并 `mv` 移入 tar 包。
  4. `rm application/middleware.php.bak.20260526_143413`。
- 验证：
  - `git status --porcelain` 仍为空。
  - `application/middleware.php` 完好（141 字节，与备份内容一致）。
  - tar 包在备份区可见（2423505 字节，与移动前一致）。
- 后续：`/www/backup/wwwroot-stale/` 是本次新建的目录，用于存放从站点目录清出但暂不敢删的陈旧产物；后续清理同类文件可沿用，长期无用再统一删除。

## 2026-07-30 15:05 CST - 解决 load.nanyahui.com 因 ACME 验证文件被跟踪导致 git pull 失败

- 服务器：`nyh-prod`
- 操作人：`Claude`
- 原因：`/www/wwwroot/load.nanyahui.com` 执行 `git pull` 报 `cannot pull with rebase: You have unstaged changes.`。排查发现根因是 `public/.well-known/acme-challenge/C-T2aLYKg52DrfdkV-ojqpfQsxC0xXt0bfyNX-2_CAE` 这个一次性 ACME 验证文件在仓库初始化提交 `e9777584` 时被误提交为**已跟踪**文件；`.gitignore` 第 23 行虽已写 `public/.well-known/`，但忽略规则对已跟踪文件无效，所以每次 Let's Encrypt 续签清理 `acme-challenge/` 目录后 git 都报一条删除变更。该站点 `pull.rebase=true`，rebase 要求工作区干净，于是 pull 被彻底阻塞。另发现 `.gitignore` 只忽略了 `public/.well-known/`，而宝塔也会往站点根目录 `.well-known/` 写验证文件（`2026-07-30 01:58` 刚生成过），这一路径一直未被忽略。
- 影响：仅动 nyhAgent 仓库的版本控制元数据与生产工作目录的代码更新；未重启 Nginx / PHP / 数据库，未改动证书续签脚本或 crontab。生产代码从 `e0faaf9e` 前进到 `40cef7f1`，随修复一并上线了业务提交 `9bf928ca`（OpenAPI 折扣页按客户导出启用套餐报价 xlsx），已事先向用户列出待上线提交与文件清单并获确认。
- 备份：改动前记录生产 HEAD 为 `e0faaf9e`，工作区仅一条 ACME 文件删除、无任何业务代码改动（`git diff --stat` 确认）。
- 回滚方式：`cd /www/wwwroot/load.nanyahui.com && git reset --hard e0faaf9e` 可退回 pull 前的生产代码；`.gitignore` 侧的修复回滚为在本地仓库 `git revert 40cef7f1` 后重新 pull。
- 变更时序：
  1. 本地仓库 `/Users/konghai/Code/Project/nyh/nyhAgent`（`main`，与 `origin/main` 同步）执行 `git rm -r --cached public/.well-known/`，取消跟踪误提交的 ACME 文件，磁盘文件保留。
  2. 改 `.gitignore`：把原 `public/.well-known/` 一行扩为 `/.well-known/` 与 `/public/.well-known/` 两条，覆盖宝塔两种 webroot 布局；另新增 `*.tar.gz`、`*.bak`、`*.bak.*` 忽略服务器上临时打的备份产物。
  3. 提交 `40cef7f1` 并推送 `origin/main`。
  4. 生产端首次 `git pull --ff-only` 复现原报错；执行 `git checkout -- <ACME 文件>` 恢复该删除让工作区干净（不用 stash、不在生产产生提交，pull 时新提交自会移除它，净效果一致）。
  5. 再次 `git pull --ff-only origin main`，fast-forward 成功，无 merge 提交。
- 验证：
  - 提交前用 `git check-ignore --no-index` 逐条验证生产上 4 个文件全部命中新规则：`public/.well-known/acme-challenge/9_siw...`、`.well-known/acme-challenge/YOjd5...`、`_pc_frontend_backup_20260526_161925.tar.gz`、`application/middleware.php.bak.20260526_143413`。
  - 确认仓库内无任何已跟踪的 `.tar.gz` / `.bak`，新增的全局忽略规则不会误伤既有文件。
  - pull 后 `git status --porcelain` 输出为空（此前的 1 条删除 + 3 条未跟踪全部消失）；`git rev-list --left-right --count HEAD...origin/main` 为 `0 0`；`git ls-files | grep well-known` 已无结果。
  - 证书续签不受影响：`.well-known/acme-challenge/` 与 `public/.well-known/acme-challenge/` 两个目录及其中现存验证文件均完好；两个备份文件仍在磁盘（仅不再被 git 看见）。
- 后续：
  - 两个 2026-05-26 的备份文件已在同日 15:20 经用户确认后清理，见下一条记录。
  - `.gitignore` 中 `#s 升级 php8.4 之前` 是内容为空的历史注释块，本次未动。
  - 同类症状的通用判据：`git status` 里 ACME/证书类路径出现 `D` 且 `.gitignore` 明明已覆盖该路径时，一律先查该文件是否被跟踪（`git ls-files`），而不是反复补忽略规则。
  - 复盘文档：`docs/solutions/nyh-prod/workflow-issues/acme-file-tracked-by-git-blocks-pull-2026-07-30.md`

## 2026-05-20 00:22 CST - 修复 Docker 功能面板域名 SSL 续期

- 服务器：`nyh-prod`
- 操作人：`Codex`
- 原因：Docker 功能面板反代域名的 Let’s Encrypt 证书过期，宝塔 `renew_v2` 默认续期流程没有覆盖这些域名；`admin.acquilangai.com` 的 `renew_v2 --index` 测试显示域名不在宝塔 `domain` 表映射内。
- 影响：更新 7 个在用域名的证书文件，并在每个成功续期后执行 Nginx reload；未重启 Docker 容器、数据库或业务进程。
- 回滚：证书备份位于 `/www/backup/ssl-cert/<domain>/<timestamp>/`；crontab 备份位于 `/www/backup/cron/root-crontab-20260520003927.bak`。可恢复证书后执行 `nginx -t && service nginx reload`，或用 crontab 备份恢复定时任务。
- 变更：
  - 恢复 7 个目标域名的 `well-known` include 内容，使 HTTP-01 token 能直接返回。
  - 使用显式 HTTP-01 申请验证 `admin.acquilangai.com`，证书从 2026-05-18 更新到 2026-08-17。
  - 新增 `/www/server/cron/custom/docker-panel-letsencrypt-renew.py`，每次运行动态扫描 Nginx vhost，发现 Docker/反代候选域名后按证书剩余天数续期。
  - 新增 root crontab：每天 02:20 CST 用 `flock` 执行动态续期脚本，日志写入 `/www/server/cron/custom/docker-panel-letsencrypt-renew.log`。
  - 对剩余过期域名执行脚本真实续期，成功续期 6 个，失败 0 个；`admin.acquilangai.com` 因已续期而跳过阈值。
- 验证：
  - dry-run 输出 7 个候选域名，普通宝塔站点与废弃域名被排除。
  - 真实执行输出 `complete renewed=6 failed=0 dry_run=False`。
  - 二次 dry-run 输出 7 个候选均为 `skip-threshold`，不会重复申请。
  - 7 个目标域名 443 端口证书均更新到 2026-08-17：
    - `acquilangai.com`
    - `admin.acquilangai.com`
    - `admin.ddricher.ai`
    - `api.acquilangai.com`
    - `api.ddricher.ai`
    - `duowei.konghai.me`
    - `m.acquilangai.com`
- 后续：
  - 新增 Docker 功能面板反代站点后，先用脚本 dry-run 确认能被动态发现。
  - 明确废弃的 Docker/反代域名需要加入脚本排除清单。
  - 复盘文档：`docs/solutions/nyh-prod/integration-issues/baota-ssl-acme-challenge-routing-fix-2026-05-19.md`


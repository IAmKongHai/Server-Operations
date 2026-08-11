# nyh-prod 运维时间线

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


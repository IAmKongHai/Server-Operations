# nyh-prod 运维时间线

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


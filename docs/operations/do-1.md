# do-1 运维操作时间线

## 2026-11-12 00:00–00:25 CST - 在 Nginx 新增 Anthropic、Gemini、OpenAI 三条美区无状态透明反代通道

- 服务器：`do-1`（`137.184.127.196` / Tailscale `100.86.92.103`）
- 操作人：`Antigravity`（经用户确认执行）
- 原因：`nyh-prod-2026` 香港公网出口直连 `api.anthropic.com`、`generativelanguage.googleapis.com`、`api.openai.com` 均返回 `403`；沿用 `/groq/` 模式，在 `do-1` Nginx `:443`（`sub.tovo.sh` IP 白名单）与 `:8080`（Tailscale 内网备入口）新增三条零状态美区透明反代，供 `nyh-prod-2026` `new-api` 主备双渠道调用。
- 影响：`nginx -t` 校验通过后执行 `systemctl reload nginx` 平滑重载，零断连；既有 `sub2api`、`/groq/` 与 Let's Encrypt ACME 自动续期不受影响。
- 备份：`/root/sub2api-tovo-20261111/sub2api.conf.before-3providers.bak`
- 回滚方式：将 `/root/sub2api-tovo-20261111/sub2api.conf.before-3providers.bak` 还原回 `/etc/nginx/sites-available/sub2api.conf`，删除 `/etc/nginx/upstreams/{anthropic,gemini,openai}-upstream.conf`，执行 `nginx -t && systemctl reload nginx`。
- 做了什么：
  1. 新增 `/etc/nginx/upstreams/anthropic-upstream.conf`（`api.anthropic.com:443`）、`gemini-upstream.conf`（`generativelanguage.googleapis.com:443`）、`openai-upstream.conf`（`api.openai.com:443`），均开启 `max_fails=0; keepalive 16; keepalive_timeout 55s;`。
  2. 在 `/etc/nginx/sites-available/sub2api.conf` 顶层增加 `map $http_upgrade $connection_upgrade`（常规 HTTP 保持 `Connection: ""` 复用上游 Keep-Alive，WebSocket 请求自动升级以支持 `/openai/v1/realtime` 等实时流），并在 `:8080` 与 `:443` 同步新增 `location ^~ /anthropic/`、`location ^~ /gemini/`、`location ^~ /openai/` 反代块（清空 `X-Real-IP` / `X-Forwarded-For`、开启 TLS SNI 与无缓冲流式透传）。
- 验证：
  - `nginx -t` 通过，`systemctl is-active nginx` 为 `active`。
  - `certbot renew --cert-name sub.tovo.sh --dry-run --no-random-sleep-on-renew` 模拟续期成功。
  - 从 `nyh-prod-2026` 分别经 `https://sub.tovo.sh/{anthropic,gemini,openai}` 与 `http://100.86.92.103:8080/{anthropic,gemini,openai}` 请求上游模型列表与推理接口全部返回 `200 OK`；公网非白名单扫描流量仍被 `:443` 顶层规则拦截为 `403`。

## 2026-11-11 22:55–23:15 CST - 彻底移除 qingfan、tk-flywheel 和旧域名 qingfan.konghai.me / tk.konghai.me

- 服务器：`do-1`（`137.184.127.196` / Tailscale `100.86.92.103`）
- 操作人：Claude（用户确认：全部删除，旧客户端反代一起删）
- 原因：qingfan、tk-flywheel 11-10 已切到 `qingfan-prod`（`qingfan.app`、`flywheel.qingfan.app`），用户确认不再需要 DO-1 这边的回滚路径（原计划保留到 11-24）。删除前 `tk-flywheel.service` 还 enabled、在运行，48 小时内没有请求。
- 影响：
  - `qingfan.konghai.me` 反代下线。这个反代之前把 0.1.47 以前的旧桌面端转发到 `qingfan.app`，删除前两天还有 Go 客户端在调 `/v1/releases`、`/v1/compass/products`；这些没升级的客户端现在连不上，用户已接受。
  - `tk.konghai.me` 下线。
  - nginx 平滑 reload 1 次，`sub2api` 和 `sub.tovo.sh` 不受影响。
  - 释放约 34 GB 磁盘（`/` 现在用了 4.1G）。
- 备份：服务器 `/root/qingfan-flywheel-removal-20261111/`，本机 `_backups/do-1-qingfan-flywheel-removal-20261111/`（不入库，sha256 已和服务器核对）：
  - `qingfan-final.dump`：33 张表，32M
  - `tk_flywheel-final.dump`：43 张表，3.9M
  - `files.tgz`：`/etc/{qingfan,tk-flywheel}`、unit、nginx、脚本、sudoers、`qingfan-deploy` 和 root 的 `.ssh`、`/root` 下的 qingfan 临时脚本、两张证书
  - `tk-pro-backups`：改之前的 cron 文件
  - 还有 `/root/.ssh/authorized_keys.bak.20261111`
  - 没有备份的：21G 旧发布包和 12G `/var/lib/qingfan`。这些在 11-10 已经同步到 `qingfan-prod` 并校验过
  - 传输方式：DO-1 直连本机只有十几 KB/s，所以先用转发的 agent 从 DO-1 `scp` 推到 `qingfan-prod`（15 秒），再从香港拉回本机（42 秒），中转目录用完就删了。注意 `qingfan-prod` 连不上 DO-1 的 22 端口（DO Cloud Firewall 没放行），只能 DO-1 往外推；heredoc 脚本里的内层 `ssh` 要加 `-n`，否则它会把后面的命令当 stdin 读走
- 回滚方式：用 `/root/do-pg-admin.env` 重建角色和库，然后 `pg_restore --no-owner`；从 `files.tgz` 恢复配置；发布包要从 `qingfan-prod` 拷回来，或者重新发布。实际上没有需要回滚的场景，生产在 `qingfan-prod`。
- 做了什么：
  1. `/etc/tk-flywheel/admin.env`（DO PG `doadmin`）挪到 `/root/do-pg-admin.env`（600），留给 sub2api 库的管理用
  2. 停掉并 disable `tk-flywheel`、`tk-flywheel-tune.timer`、`qingfan@{blue,green}`，删除 4 个 unit 文件，执行 `daemon-reload`
  3. 托管 PG：`DROP DATABASE qingfan / tk_flywheel`，`DROP ROLE qingfan / tk_flywheel`（现在只剩 `sub2api`）
  4. 删除 nginx 的 `qingfan.konghai.me.conf`（含 `.pre-gzip`）、`tk.konghai.me.conf`、`upstreams/qingfan-upstream.conf`，`nginx -t` 通过后 reload；`certbot delete` 删掉两张证书
  5. cron `/etc/cron.d/tk-pro-backups` 只留 `sub2api-backup`
  6. root `authorized_keys` 删掉 `tk-flywheel-deploy` 强制命令密钥；删除 `/root/.ssh/hk-migrate{,.pub}`、`/etc/sudoers.d/qingfan-deploy`（`visudo -c` 通过）
  7. 删除 `/opt/{qingfan,tk-flywheel}`、`/var/lib/{qingfan,tk-flywheel}`、`/etc/{qingfan,tk-flywheel}`、`/var/backups/{qingfan,tk-flywheel}`、`/var/log/{qingfan,tk-flywheel}`、`/var/www/{qingfan,tk-flywheel}-acme`；`/usr/local/bin` 下的 `qingfan-deploy*`、`whisper-cli`、`sherpa-onnx-offline*`；`/usr/local/sbin` 下的 `qingfan-*`、`tk-flywheel-*`、`hk-migrate-db`；`/root` 下的 `calls.py`、`costs.json`、`setimage.py`、`.qingfan_*` 和旧 nginx 备份
  8. `userdel -r qingfan-deploy`，`userdel qingfan tk-flywheel`
  9. 仓库：`do-1/` 只保留 sub2api、nginx 全局配置、sshd 和 sysctl
- 验证：
  - 没有 qingfan / flywheel 的 unit、端口、用户，`find` 查不到残留，nginx / cron / systemd / sudoers 里都搜不到
  - `sites-enabled` 只剩 `sub2api.conf`，证书只剩 `sub.tovo.sh`，`certbot renew --dry-run` 成功
  - `nginx`、`sub2api`、`redis-server` 都 active；`:8080/health` 返回 200，`sub.tovo.sh/health` 本机和从 `nyh-prod-2026` 访问都返回 200
  - `qingfan.app`、`flywheel.qingfan.app` 的 `/healthz` 都返回 200

## 2026-11-11 22:37–22:45 CST - 彻底移除已停用的 new-api（tovo.sh 旧部署）

- 服务器：`do-1`（`137.184.127.196` / Tailscale `100.86.92.103`）
- 操作人：Claude（用户确认「全部删除」，含托管库）
- 原因：`tovo.sh` 已迁到 `nyh-prod-2026`（公网 DNS 已指向 `8.217.145.133`），DO-1 上的 `new-api@blue` 还在空跑，监听 `*:3001`（所有网卡），并且还在续期 `tovo.sh` 证书。
- 影响：去掉 `tovo.sh` 在 DO-1 上的入口（未知 Host 默认 444）；nginx 平滑 reload 1 次，`sub2api` 和 `sub.tovo.sh` 不受影响。删除前库里最后一条请求日志在 11-11 当天，应该是还缓存着旧 DNS 的客户端。
- 备份：服务器 `/root/new-api-removal-20261111/`，本机 `_backups/do-1-new-api-removal-20261111/`（不入库）：
  - `new_api-final.dump`：`pg_dump -Fc`，38 张表
  - `redis-db1.txt`：Redis DB 1 全部 10 个 key 的明文导出
  - `new-api-files.tgz`：`/etc/new-api`、unit、nginx 站点 / upstream、3 个脚本、`/var/backups/new-api` 历史 dump、`/var/log/new-api`、`tovo.sh` 证书
  - `tk-pro-backups`：改之前的 cron 文件
- 回滚方式：在托管 PG 用 `doadmin` 重建 `new_api` 角色和库，`pg_restore --no-owner` 导入 dump；解开 tgz 还原文件，`useradd -r -s /usr/sbin/nologin new-api`，`daemon-reload` 后 `enable --now new-api@blue`；nginx 站点恢复后签发 `tovo.sh` 证书。
- 做了什么：
  1. `systemctl disable --now new-api@blue`，删除 `new-api@.service`，执行 `daemon-reload`
  2. 删除 nginx `sites-{available,enabled}/new-api.conf` 和 `upstreams/new-api-upstream.conf`，`nginx -t` 通过后 reload
  3. `certbot delete --cert-name tovo.sh`
  4. 从 `/etc/cron.d/tk-pro-backups` 删掉 `new-api-backup` 那一行
  5. Redis DB 1 `FLUSHDB`（`sub2api` 的 DB 0 共 359 个 key，没动）
  6. 托管 PG：`DROP DATABASE new_api; DROP ROLE new_api;`（剩下 `qingfan`、`sub2api`、`tk_flywheel`）
  7. 删除 `/opt/new-api`、`/etc/new-api`、`/var/lib/new-api`、`/var/log/new-api`、`/var/backups/new-api`，以及 `/usr/local/sbin/new-api-{deploy,rollback,backup}`
  8. `userdel new-api`
  9. 仓库：删除 `do-1/` 下所有 new-api 配置和 `ci-templates/new-api-package.sh`，同步 cron 文件
- 验证：没有 `new-api*` unit，3001 / 3002 无监听，`find` 查不到残留，`new-api` 用户已删除；`sub2api` 和 nginx 都 active，`:8080/health` 返回 200，`sub.tovo.sh/health` 本机和从 `nyh-prod-2026` 访问都返回 200；`certbot renew --cert-name sub.tovo.sh --dry-run` 成功。

## 2026-11-11 16:39–16:43 CST - 在 sub.tovo.sh 与 :8080 增加 /groq/ 无状态美区透明反代供 nyh-prod-2026 new-api 接入 Groq 官方 API

- 服务器：`do-1`（`137.184.127.196` / Tailscale `100.86.92.103`）
- 操作人：`Antigravity`（用户选定方案 3「`do-1` Nginx 透明反代」替代 `sub2api` 转发或双 `new-api` 串联，并确认同意执行）
- 原因：`nyh-prod-2026`（香港 IP `8.217.145.133`）直连 `api.groq.com` 被锁区返回 `403`，而下游业务同时需要 Groq LLM、Responses、Orpheus TTS（`/v1/audio/speech`）与 Whisper STT（`/v1/audio/transcriptions`）；`sub2api` 不支持 `/v1/audio/*`，在 `do-1` 现有白名单 Nginx 上增加无状态反代可零维护成本透传全部官方接口。
- 影响：Nginx 平滑 reload 1 次（零连接中断），不影响既有 `sub2api` 流量与 `sub2api-deploy` 蓝绿切换。
- 备份：`/root/sub2api-tovo-20261111/sub2api.conf.before-groq.bak`
- 回滚方式：
  ```bash
  cp -p /root/sub2api-tovo-20261111/sub2api.conf.before-groq.bak /etc/nginx/sites-available/sub2api.conf
  rm -f /etc/nginx/upstreams/groq-upstream.conf
  nginx -t && systemctl reload nginx
  ```
- 做了什么：
  1. 新增 `/etc/nginx/upstreams/groq-upstream.conf`（仓库 `do-1/etc/nginx/upstreams/groq-upstream.conf`）：定义 `upstream groq_api` 指向 `api.groq.com:443`（`max_fails=0; keepalive 16; keepalive_timeout 55s;`），复用 `do-1` 至 Cloudflare 边缘节点的 TLS 长连接。
  2. 更新 `/etc/nginx/sites-available/sub2api.conf`（仓库 `do-1/etc/nginx/sites-available/sub2api.conf`）：在 `:443`（`sub.tovo.sh`）与 `:8080`（Tailscale 备份）两个 `server` 块中增加 `location ^~ /groq/`，反代至 `https://groq_api/openai/`，显式设置 `Host api.groq.com`、`proxy_ssl_server_name on`、`proxy_ssl_name api.groq.com`，清空 `X-Real-IP` / `X-Forwarded-For` 防止泄露上游香港 IP，并关闭请求/响应缓冲。
  3. 执行 `nginx -t && systemctl reload nginx`。
- 验证：
  - `nyh-prod-2026` 访问主通道 `https://sub.tovo.sh/groq/v1/models` 与备通道 `http://100.86.92.103:8080/groq/v1/models` 均返回 `200 OK`（12 个模型）。
  - 非授权公网节点 `tizi-kh` 访问 `https://sub.tovo.sh/groq/v1/models` 返回 `403`（IP 白名单保护有效）。

## 2026-11-11 10:45–11:00 CST - 配置 sub.tovo.sh 白名单 HTTPS 入口（含自动续期验证）及 BBR/Nginx 调优

- 服务器：`do-1`（`137.184.127.196` / Tailscale `100.86.92.103`）
- 操作人：`Antigravity`（用户选定方案 B 打通 `nyh-prod-2026` `new-api` → `do-1` `sub2api`，并同意修复 4 项跨洋性能与稳定性隐患）
- 原因：为 `nyh-prod-2026` 提供高稳定公网 TCP 443 + TLS 1.3 + HTTP/2 主通道（`https://sub.tovo.sh`），保留 Tailscale `:8080` 作为备通道，同时解决粘性会话请求头丢弃、慢启动退化与空闲连接超时倒挂风险。
- 影响：`sysctl` 在线生效（无重启）；Nginx 平滑 reload 2 次（零中断）。
- 备份：`/root/sub2api-tovo-20261111/`（`sysctl.before`、`nginx.conf.bak`、`sub2api.conf.bak`）。
- 回滚方式：
  ```bash
  cp /root/sub2api-tovo-20261111/nginx.conf.bak /etc/nginx/nginx.conf
  cp /root/sub2api-tovo-20261111/sub2api.conf.bak /etc/nginx/sites-available/sub2api.conf
  nginx -t && systemctl reload nginx
  rm -f /etc/sysctl.d/98-cross-ocean-tcp.conf /etc/modules-load.d/bbr.conf && sysctl --system
  certbot delete --cert-name sub.tovo.sh
  ```
- 做了什么：
  1. **开启 BBR 与跨洋 TCP 调优**：写入 `/etc/modules-load.d/bbr.conf` 与 `/etc/sysctl.d/98-cross-ocean-tcp.conf`（仓库 `do-1/etc/sysctl.d/98-cross-ocean-tcp.conf`），启用 `fq` + `bbr`、`tcp_slow_start_after_idle=0` 及 32MiB socket 缓冲区上限。
  2. **全局保留下划线请求头**：`/etc/nginx/nginx.conf` 的 `http` 块增加 `underscores_in_headers on;`（仓库 `do-1/etc/nginx/nginx.conf`），防止丢弃 `sub2api` 粘性会话依赖的 `session_id` 请求头。
  3. **签发 `sub.tovo.sh` 证书并配置 IP 白名单与无缓冲透传**：
     - 创建 `/var/www/sub2api-acme`，签发 Let's Encrypt ECDSA 证书 `sub.tovo.sh`（有效期至 `2027-02-09`）。
     - 更新 `/etc/nginx/sites-available/sub2api.conf`（仓库 `do-1/etc/nginx/sites-available/sub2api.conf`）：新增 `sub.tovo.sh` `:80` 与 `:443` server 块（共享 `sub2api_backend` upstream，兼容 `sub2api-deploy` 蓝绿切换），`:443` 仅放行 `8.217.145.133`、`100.64.0.0/10` 及回环地址，而 `/.well-known/acme-challenge/` 独立 `allow all;` 确保自动续期不受白名单影响。
     - `:443` 与 `:8080` 统一配置 `keepalive_timeout 120s; keepalive_requests 10000; client_max_body_size 128m; proxy_request_buffering off; proxy_buffering off; proxy_read_timeout 900s; proxy_send_timeout 900s;`。
- 验证：
  - `certbot renew --cert-name sub.tovo.sh --dry-run --no-random-sleep-on-renew` 模拟续期成功。
  - 非白名单公网节点 `tizi-kh` 访问 `https://sub.tovo.sh/health` 返回 `403`，ACME 验证路径正常返回 `404`。
  - `nyh-prod-2026` `new-api` 容器访问 `https://sub.tovo.sh/v1/models` 返回 `200 OK`（HTTP/2）。

# do-1 运维操作时间线

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

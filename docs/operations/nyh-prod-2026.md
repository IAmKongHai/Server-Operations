# nyh-prod-2026 运维操作时间线

## 2026-11-11 12:42–13:00 CST - 在 new-api 配置 DO-1 Sub2API 主备双渠道与 28 个模型人民币对齐计费并通过端到端验收

- 服务器：`nyh-prod-2026`（`tovo.sh`）、`do-1`（`sub.tovo.sh` / `100.86.92.103:8080`）
- 操作人：`Antigravity`（按用户确认的渠道配置与「官方美元原价 × 7.3 折算人民币」计费方案执行）
- 原因：完成 `new-api` 对接上游 `do-1` `sub2api` 的生产渠道落地与统一人民币钱包计费对齐，使下游生产 App 仅凭单个 `default` 分组令牌即可同时调用 Seedance 视频模型与 OpenAI 系列模型。
- 影响：在线修改 `new-api` `options` 定价倍率并新增渠道 `#2`、`#3`，无服务中断；既有渠道 `#1`（通天云 Seedance）及客户账号 `aozhuo-test`（余额 `¥50.00`，消费 `0`）完全未触碰。
- 备份：`/root/sub2api-tovo-20261111/new-api-billing-options.before.json`（变更前完整 `options` 与 `channels` 快照，权限 `600`）
- 回滚方式：在 `new-api` 后台删除渠道 `#2`、`#3`，并用 `/root/sub2api-tovo-20261111/new-api-billing-options.before.json` 中的 `ModelRatio`、`CompletionRatio`、`CacheRatio`、`CreateCacheRatio`、`ImageRatio` 原值通过 `PUT /api/option/` 恢复。
- 做了什么：
  1. **对齐 28 个 OpenAI 模型的人民币计费倍率（`1 内部单位 = ¥1.00`，`USDExchangeRate=1`）**：
     - 合并更新 `ModelRatio`（公式：`官方输入 $/1M × 7.3 / 2.0 = USD_in × 3.65`）、`CompletionRatio`、`CacheRatio`、`CreateCacheRatio`、`ImageRatio`（含 `gpt-image-1.5` 补全倍率 `6.4`、`gpt-image-2/2.5-*` 补全倍率 `6` 与图片输入倍率 `1.6`）。
     - 核心模型折算结果：`gpt-6-luna` 输入 `¥0.73/1M`（`ModelRatio=0.365, CompletionRatio=5`）、`codex-auto-review` / `gpt-5.6-luna` 输入 `¥1.46/1M`（`0.73, ×6`）、`gpt-5.4-mini` 输入 `¥5.475/1M`（`2.7375, ×6`）、`gpt-6.1-terra` 输入 `¥7.30/1M`（`3.65, ×5`）、`gpt-5.2*` / `gpt-5.3-codex-spark` 输入 `¥12.775/1M`（`6.3875, ×8`）、`gpt-5.6-terra` / `gpt-6-sol` / `gpt-6.1-sol` 输入 `¥14.60/1M`（`7.3`）、`gpt-5.4*` 输入 `¥18.25/1M`（`9.125, ×6`）、`gpt-5.6` / `gpt-5.6-sol` / `gpt-reserve` / `gpt-image-*` 输入 `¥36.50/1M`（`18.25`）、`gpt-6` / `gpt-6-astra` 输入 `¥73.00/1M`（`36.5, ×5`）、`gpt-5.2-pro*` 输入 `¥153.30/1M`（`76.65, ×8`）。
  2. **创建主备双渠道（复用 `do-1` `sub2api` `for-tovo.sh` 专用 API Key，归入 `default` 组）**：
     - 渠道 `#2` `DO1-Sub2API-Primary (sub.tovo.sh)`：类型 `OpenAI(1)`，Base URL `https://sub.tovo.sh`，优先级 `10`（主力流量走公网 HTTPS HTTP/2 常驻长连接 + IP 白名单），标签 `sub2api-do1`。
     - 渠道 `#3` `DO1-Sub2API-Backup (Tailscale)`：类型 `OpenAI(1)`，Base URL `http://100.86.92.103:8080`，优先级 `0`（主通道异常时自动无缝回退 Tailscale WireGuard P2P 直连），标签 `sub2api-do1`。
     - 将两渠道 `test_model` 设为 ChatGPT Codex OAuth 原生支持且单价最低的 `gpt-6-luna`（注：Codex OAuth 账号不支持 `gpt-5.4-mini`，若用其测活会返回 `400 model_not_found`）。
- 验证：
  - **内置渠道测活**：渠道 `#2`（主 `sub.tovo.sh`）测活成功（`1.491s`，`do-1` Nginx 记录 `8.217.145.133` `HTTP/2.0 200`）；渠道 `#3`（备 Tailscale）测活成功（`2.84s`，`do-1` Nginx 记录 `100.113.16.89` `HTTP/1.1 200`）。
  - **端到端公网流式调用与路由验证**（使用临时 `root` 测试令牌，测完已删除）：
    - `GET https://tovo.sh/v1/models` 返回 `200 OK`（完整列出 28 个模型）。
    - `POST https://tovo.sh/v1/chat/completions`（`gpt-6-luna`，SSE 流式 + `session_id` 头）返回 `200 OK`，`TTFT=1.23s`、`Total=1.28s`，命中主渠道 `ch=2`。
    - `POST https://tovo.sh/v1/responses`（`gpt-6-luna`，SSE 流式 + `session_id` 头）返回 `200 OK`，`TTFT=1.17s`、`Total=1.41s`，命中主渠道 `ch=2` 且成功触发上游粘性会话 Prompt Cache（`cache_tokens=4224`）。
  - **精确计费对账**：
    - `logs.id=4`（`/v1/chat/completions`，`in=16, out=6, cache=0`）：扣费 `quota=17`（`¥0.000034`，理论值 `(16 + 6×5)×0.365 = 16.79` 向上取整 `17`）。
    - `logs.id=5`（`/v1/responses`，`in=4395, cache=4224, out=5`）：扣费 `quota=226`（`¥0.000452`，理论值 `(171 + 4224×0.1 + 5×5)×0.365 = 225.716` 向上取整 `226`）。

## 2026-11-11 12:22 CST - 重建 new-api 容器使跨洋连接池与 H2 保活参数生效

- 服务器：`nyh-prod-2026`
- 操作人：`Antigravity`（用户确认同意重启）
- 原因：加载 `/opt/stacks/new-api/.env` 新增的 `RELAY_IDLE_CONN_TIMEOUT=60` 与 `RELAY_HTTP2_PING_IDLE_TIMEOUT=30`。
- 影响：执行前核实 `tasks` 表在途异步任务为 `0`；`new-api` 容器重建耗时约 6 秒恢复 `healthy`。
- 备份：`/root/sub2api-tovo-20261111/new-api.env.bak`
- 回滚方式：`cp /root/sub2api-tovo-20261111/new-api.env.bak /opt/stacks/new-api/.env && cd /opt/stacks/new-api && docker compose up -d`
- 做了什么：`cd /opt/stacks/new-api && docker compose up -d` 重建 `new-api` 容器。
- 验证：容器状态 `healthy`，容器内 `env` 确认 `RELAY_IDLE_CONN_TIMEOUT=60`、`RELAY_HTTP2_PING_IDLE_TIMEOUT=30` 已生效，`https://tovo.sh/api/status` 返回 `200 OK`。

## 2026-11-11 11:24 CST - root 的 authorized_keys 加入同事公钥 `hon-2026`

- 服务器：`nyh-prod-2026`
- 操作人：Claude（用户要求把同事 hon 的公钥加到这台服务器）
- 原因：同事需要 SSH 登录 `nyh-prod-2026`；旧机 `nyh-prod` 上就有这把 `hon-2026`，迁移时没带过来。
- 影响：`hon-2026` 对应私钥可以 root 身份登录本机；sshd 配置未改，不需要 reload。
- 备份：`/root/.ssh/authorized_keys.bak.20261111`（追加前的 4 把密钥）
- 回滚方式：`cp -p /root/.ssh/authorized_keys.bak.20261111 /root/.ssh/authorized_keys`，或删掉注释为 `hon-2026` 的那一行。
- 做了什么：备份后把 `ssh-ed25519 …HZfjPj hon-2026` 追加到 `/root/.ssh/authorized_keys`（先 grep 判重）；权限保持 `600 root:root`。
- 验证：文件现有 5 把密钥（`konghai@konghai.me`、3 把 CI、`hon-2026`），`ssh-keygen -lf` 解析出 `256 SHA256:t5JxvwYZEe9z6KOnXyd08lYm/3rRTIrfzSM8J1k3e+0 hon-2026 (ED25519)`。同事侧实际登录待对方自测。

## 2026-11-11 10:45–11:00 CST - 打通 nyh-prod-2026 (new-api) 与 do-1 (sub2api) 主备双通道（sub.tovo.sh + BBR/Nginx 4 项调优）

- 服务器：`nyh-prod-2026`、`do-1`（`137.184.127.196` / `100.86.92.103`）
- 操作人：`Antigravity`（用户选定方案 B「公网 HTTPS IP 白名单主通道 + Tailscale 备通道」，提供已解析域名 `sub.tovo.sh`，并同意一并修复 4 项性能与稳定性隐患）
- 影响：两机 `sysctl` 在线生效（无重启）；`do-1` Nginx 平滑 reload 2 次（无连接中断）；`nyh-prod-2026` `/opt/stacks/new-api/.env` 已写入连接池保活参数（待用户确认窗口后再重建 `new-api` 容器生效）。
- 备份：
  - `nyh-prod-2026`：`/root/sub2api-tovo-20261111/`（`sysctl.before`、`new-api.env.bak`）
  - `do-1`：`/root/sub2api-tovo-20261111/`（`sysctl.before`、`nginx.conf.bak`、`sub2api.conf.bak`）
- 回滚方式：
  - `do-1`：`cp /root/sub2api-tovo-20261111/nginx.conf.bak /etc/nginx/nginx.conf && cp /root/sub2api-tovo-20261111/sub2api.conf.bak /etc/nginx/sites-available/sub2api.conf && nginx -t && systemctl reload nginx`；`rm -f /etc/sysctl.d/98-cross-ocean-tcp.conf /etc/modules-load.d/bbr.conf && sysctl --system`；`certbot delete --cert-name sub.tovo.sh`。
  - `nyh-prod-2026`：`cp /root/sub2api-tovo-20261111/new-api.env.bak /opt/stacks/new-api/.env`；`rm -f /etc/sysctl.d/98-cross-ocean-tcp.conf /etc/modules-load.d/bbr.conf` 并按 `sysctl.before` 恢复 `cubic` / `fq_codel` / `tcp_slow_start_after_idle=1`。
- 做了什么：
  1. **两机对称开启 BBR 与跨洋 TCP 调优**：在 `nyh-prod-2026` 与 `do-1` 写入 `/etc/modules-load.d/bbr.conf`（`tcp_bbr`）和 `/etc/sysctl.d/98-cross-ocean-tcp.conf`（仓库 `nyh-prod-2026/sysctl/98-cross-ocean-tcp.conf`），在线启用 `net.core.default_qdisc=fq`、`net.ipv4.tcp_congestion_control=bbr`、`net.ipv4.tcp_slow_start_after_idle=0` 及 32MiB `rmem_max/wmem_max/tcp_rmem/tcp_wmem`。
  2. **`do-1` 签发 `sub.tovo.sh` 证书并保障自动续期**：
     - 建 `/var/www/sub2api-acme`；在 `/etc/nginx/sites-available/sub2api.conf` 新增 `sub.tovo.sh` 的 `:80` 与 `:443` server 块（与 `:8080` 共享 `sub2api_backend` upstream，兼容 `sub2api-deploy` 蓝绿发布且避免重复定义 upstream）。
     - `:80` 与 `:443` 的 `location ^~ /.well-known/acme-challenge/` 均独立显式配置 `allow all;`，不受 API IP 白名单影响；续期由 `do-1` 既有 `certbot.timer` + `/etc/letsencrypt/renewal-hooks/deploy/reload-nginx` 自动平滑重载。
     - `certbot certonly --webroot -w /var/www/sub2api-acme --cert-name sub.tovo.sh -d sub.tovo.sh --key-type ecdsa` 签发成功（到期 `2027-02-09`）。
  3. **`do-1` Nginx 安全白名单与流式/保活修复**：
     - `/etc/nginx/nginx.conf` 启用 `underscores_in_headers on;`（保留 `sub2api` 粘性会话所需的 `session_id` 请求头）。
     - `sub.tovo.sh` `:443` 严格限制 `allow 8.217.145.133; allow 100.64.0.0/10; allow 127.0.0.1; allow ::1; deny all;`。
     - `:443` 与 `:8080` 同步配置 `keepalive_timeout 120s; keepalive_requests 10000; client_max_body_size 128m; proxy_request_buffering off; proxy_buffering off; proxy_read_timeout 900s; proxy_send_timeout 900s;`（`120s` 已大于 `new-api` 当前运行中的默认 `90s`，提前消除空闲断连竞态）。
  4. **`nyh-prod-2026` `new-api` 保活参数预写入**：`/opt/stacks/new-api/.env`（及仓库 `env.example`）追加 `RELAY_IDLE_CONN_TIMEOUT=60` 与 `RELAY_HTTP2_PING_IDLE_TIMEOUT=30`（保持 `600` 权限）。
- 验证：
  - **自动续期演练**：`certbot renew --cert-name sub.tovo.sh --dry-run --no-random-sleep-on-renew` 通过（`Congratulations, all simulated renewals succeeded`）。
  - **IP 白名单拦截**：从非授权公网 `tizi-kh` 访问 `https://sub.tovo.sh/health` 与 `http://sub.tovo.sh/` 均返回 `403`，而 `http://sub.tovo.sh/.well-known/acme-challenge/test-probe` 正常穿透白名单返回 `404`。
  - **容器双通道与提速复测**：`nyh-prod-2026` `new-api` 容器内访问主通道 `https://sub.tovo.sh/v1/models`（携带 `for-tovo.sh` key 与 `session_id` 头）返回 `200 OK`（HTTP/2，TLS 校验 `0`，热连接 p50 `160.7 ms`），备通道 `http://100.86.92.103:8080/health` 返回 `200 OK`；开启 BBR + `tcp_slow_start_after_idle=0` 后，热连接单次 `4.92 MiB` 下载速度由 `11.11 MiB/s` 提升至 `14.93 MiB/s`（`0.33s` 完成）。

## 2026-11-11 09:25–09:50 CST - 排查：nyh-prod-2026 (new-api) 与 do-1 (sub2api) 跨洋访问通道延迟与吞吐基准实测（只读）

- 服务器：`nyh-prod-2026`（阿里云香港轻量，峰值带宽 200 Mbps）、`do-1`（DigitalOcean SFO3 `137.184.127.196` / Tailscale `100.86.92.103`）
- 操作人：`Antigravity`（用户要求评估 `new-api` 接入 `do-1` `sub2api` 作为上游供应商的最稳最快连接方式）
- 原因：对比 Tailscale WireGuard P2P 直连、本机 Nginx `do1-relay` 二次反代、公网 HTTPS `:443`（TLS 1.3 + HTTP/2 / HTTP/1.1）及美西代理跳板中转的网络延迟、抖动、重传率与上下行吞吐量。
- 影响：纯网络探测与短时内存流测速，未修改两台服务器任何配置文件、防火墙、内核参数或运行中服务（临时测试端口测完已自动退出并确认清理）。
- 回滚方式：无配置变更，无需回滚。
- 做了什么与实测结论：
  1. **底层物理路由**：往返对称走阿里云香港 ↔ NTT 国际骨干网（`129.250.*`）↔ DigitalOcean SFO3，物理 RTT `154.8–156.2 ms`，0% 丢包，回程 StDev `0.3 ms`；经 `tizi-kh`（avg `174.2 ms`，sd `18.3 ms`）、`tizi-rao`（avg `193.9 ms`，sd `23.7 ms`）、`tizi-cyp`（avg `172.3 ms`）跳板均更慢且抖动显著增大，排除中转。
  2. **容器网络直通验证**：`new-api` 容器内经 Docker 网桥 MASQUERADE SNAT 可直接访问 `http://100.86.92.103:8080/health`（返回 `200 OK`，PMTUD 在 `tailscale0` MTU 1280 下工作正常）；而访问宿主机 `172.17.0.1:8080`（`do1-relay`）因仅放行 `127.0.0.1` 和 `100.64.0.0/10` 返回 `403`，且实测绕 `do1-relay` 比直连多 `3–12 ms` 延迟与 5 倍抖动（p95 `167.8 ms` vs `157.6 ms`）。
  3. **连接延迟与突发对比（`new-api` 容器 netns 实测）**：
     - 热连接复用：公网 HTTPS H2（p50 `155.42 ms`，p95 `156.45 ms`，sd `0.48 ms`）与 Tailscale HTTP Keep-Alive（p50 `148.4–155.68 ms`，p95 `157.60 ms`，sd `0.67 ms`）同处物理光速极限。
     - 冷连接与 20 并发突发：Tailscale HTTP 省 1 个 TLS 1.3 RTT（冷建连 p50 `312.3 ms` vs 公网 HTTPS `477.7 ms`；20 并发冷突发墙钟 `439.4 ms` vs 公网 HTTPS `921.6 ms`，单次 WireGuard rekey 偶发 `474.6 ms`）；公网 HTTPS 若保持 H2 常驻连接（`RELAY_HTTP2_PING_IDLE_TIMEOUT`）则并发流无需重复握手。
  4. **双向吞吐实测（`new-api` 容器 netns）**：
     - 下行（DO-1 → NYH）：单次 `4.92 MiB` Tailscale `27.1 Mbps` vs 公网 H2 `24.0 Mbps`；单连接连续流 Tailscale `114.2 Mbps`、公网 H1.1 `93.2 Mbps`、公网 H2 `70.1 Mbps`（受单流 H2 窗口限制）；4 并发 `118.1 MiB` Tailscale `169.2 Mbps`（`tailscaled` 占单核约 31% CPU，0 重传）、公网 H1.1 `165.3 Mbps`，均跑满阿里云 200 Mbps 出口上限。
     - 上行（NYH → DO-1 POST）：单连接 `40 MiB` Tailscale `81.9 Mbps` vs 公网 H1.1 `69.4 Mbps`；4 并发 `100 MiB` 公网 HTTPS H2 最快达 `153.8 Mbps`（MTU 1500 优势），公网 H1.1 `117.3 Mbps`，Tailscale `116.9 Mbps`。
  5. **发现的待确认调优点（未改动）**：
     - 两机均为 `cubic` + `tcp_slow_start_after_idle=1`（空闲 >1s 后大请求退回慢启动），改 `bbr` + `tcp_slow_start_after_idle=0` 可显著提速单次多模态大包；
     - `new-api` 默认 `RELAY_IDLE_CONN_TIMEOUT=90` 大于 `do-1` Nginx 默认 `keepalive_timeout 75s`，存在 75s 边界跨洋空闲连接复用 EOF/502 竞态风险；
     - `do-1` `/etc/nginx/nginx.conf` 未开启 `underscores_in_headers on;`，会丢弃 `sub2api` 粘性会话所需的 `session_id` 请求头；`sub2api.conf` 未关 `proxy_request_buffering`。

## 2026-11-10 23:35–23:45 CST - 修复全站 HTTP/3（QUIC reuseport + 反代 Host 头）

- 服务器：`nyh-prod-2026`
- 操作人：`Claude`（用户选择先修 HTTP/3，修不好再全站关闭；已同意重启 nginx）
- 影响：23:36:22 **重启 nginx 一次**（改 listen 参数 reload 不生效），全部站点断开约 1 秒；之后 reload 2 次。
- 备份：`/root/h3-20261110/`（`0.default.conf.bak`、`udp443.before`、`vhost-before-host-fix.tar.gz` 为改 Host 前的整个 vhost 目录）。
- 回滚方式：`tar -xzf /root/h3-20261110/vhost-before-host-fix.tar.gz -C /etc/nginx/nyh`，`0.default.conf.bak` 拷回，`nginx -t && systemctl restart nginx`。
- 做了什么：
  1. `0.default.conf` 增加 `listen 443 quic reuseport;`。`reuseport` 对同一 address:port 只能声明一次，放在默认站点，其它 vhost 仍写不带参数的 `listen 443 quic`。重启后 UDP 443 由 1 个共享 socket 变成 4 个（每个 worker 一个）。
  2. 重启后 `kanova.app`、`load.nanyahui.com` 的 h3 恢复正常，但 `ddricher.ai`、`admin.kanova.app` 的 h3 稳定返回 400。原因：这些反代 vhost 用 `proxy_set_header Host $http_host;`，HTTP/3 没有 `Host` 请求头（用 `:authority`），`$http_host` 为空，上游容器（nginx 1.31.6）对空 Host 回 400。11 个 vhost 共 13 处全部改为 `$host`（443 上的 h1/h2 取值不变）。
  3. `tovo.sh` 恢复 `listen 443 quic`、`http3 on`、`Alt-Svc`。
- 验证（大陆本机 `curl --http3-only` 对照 `--http2`）：
  - 解析到本机的全部站点首页 h2 与 h3 状态码一致：`admin.kanova.app`、`api.kanova.app`、`kanova.app`、`ddricher.ai`、`www.ddricher.ai`、`api.ddricher.ai`(502，与 h2 一致，上游 7800 本来就没进程)、`gateway.ddricher.ai`(404，同 h2)、`konghai.me`、`load.nanyahui.com`、`api.nanyahui.com`、`load.nanyahui.cn`、`vip.nanyahui.com`、`vip-dev.nanyahui.com`、`numbers.konghai.me`(Cloudflare 橙云)。
  - 静态文件 h3：`kanova.app` 230KB 0.48–0.51s，`load.nanyahui.com` 134KB 0.36–0.44s，都比 h2 快；`tovo.sh` 主包 1.48MB h3 2.3–2.6s，h2 2.1–5.4s。
- 仍指向旧机 `47.239.167.8`（11-11 00:00 到期）的域名，权威 DNS 23:39 复查：`center.nanyahui.com`、`mp.nanyahui.com`、`vip.nanyahui.cn`、`smith.konghai.me`、`admin-al.konghai.me`、`api-al.konghai.me`。已告知用户。
  - **更正（11-11 01:25 复查）**：Cloudflare 权威 NS 与 1.1.1.1 上，前 4 个均已解析到 `8.217.145.133`，`admin-al` / `api-al` 已无 A 记录；用户本机 ping 结果一致（`mp.nanyahui.com` 在用户本机解析为 Tailscale `100.113.16.89`）。23:39 那次的结论有误或当时记录尚未更新，以本次为准。

## 2026-11-10 22:40 CST - 排查：全部站点 HTTP/3 不可用，原因在服务器侧（只读）

- 服务器：`nyh-prod-2026`
- 操作人：`Claude`（用户问其它站点是否也有 HTTP/3 问题）
- 结论：**修正上一条的判断**。tovo.sh 的 h3 失败不只是大陆出境 UDP 的问题，本机 nginx 的 QUIC 本身就不可用。
- 证据（同一静态文件，`curl --http3-only` 各 3 次，HTTP/2 同时对照，h2 全部 200）：
  - 大陆本机：`kanova.app`、`ddricher.ai`、`load.nanyahui.com`、`admin.kanova.app` 共 12 次 h3，全部失败（rc 55/56，`admin.kanova.app` 有 2 次返回 h3 `400`）。
  - 阿里云香港 `qingfan-prod`（不经跨境线路）：3 次全部失败（rc 56 / 超时）。
  - 美国 `tizi-kh`：1 次超时，2 次成功但慢（2.2s / 5.6s）。
- 疑似原因：21 个 vhost 都有 `listen 443 quic`，但没有任何一个带 `reuseport`。`ss -ulpn` 显示 UDP 443 只有一个 socket，被 master 和全部 worker 共享；nginx 多 worker 跑 QUIC 时，同一连接的包可能被不同 worker 收到，连接就会中断。`bnsg.konghai.me` 的 vhost 里早就注释掉了 h3（"Chrome H3/JS cancel white-screen mitigation"），症状一致。
- 影响：这些站点都在发 `Alt-Svc: h3=...`，Chrome / Safari 会先试 h3，失败后才回退 h2，所以会出现偶发的卡顿或白屏。
- DNS 补充：22:40 复查 `tovo.sh`，Cloudflare 两台权威服务器和 1.1.1.1 / 8.8.8.8 / 223.5.5.5 都返回 `8.217.145.133`，用户控制台截图也是这个值；22:25 前后权威服务器返回的是 `137.184.127.196`，中间被改过。
- 未改动任何配置。

## 2026-11-10 22:20–22:30 CST - nginx 全局启用 Brotli；tovo.sh 关闭 HTTP/3

- 服务器：`nyh-prod-2026`
- 操作人：`Claude`（用户要求：大陆访问本机所有站点都慢，装 Brotli 让所有项目受益；tovo.sh 关 HTTP/3。用户已同意必要时重启 nginx，实际只 reload）
- 排查结论（tovo.sh 首屏慢）：
  - new-api 自带 gzip，主包 `index.*.js` 原始 5.2MB / gzip 1.48MB。同一文件下载：阿里云香港 `qingfan-prod` 26MB/s，美国 `tizi-kh` 750KB/s，大陆本机 150–520KB/s 且波动大。服务器出口不是瓶颈，瓶颈是大陆到香港的跨境线路。
  - HTTP/3：本机用 `curl --http3-only` 下 3 次，3 次都中途失败（其中一次握手成功后传输中断），大陆出境 UDP 443 不稳定，浏览器优先用 h3 时会卡住再回退。
- 影响：nginx 平滑 reload 3 次，主进程没有重启（启动时间仍为 17:04:26）；全部 vhost 的文本类静态资源对支持 br 的浏览器改为 Brotli。
- 备份：`/root/brotli-20261110/`（`http.conf.bak`、`tovo.sh.conf.bak`、`modules-enabled.before`、两个 deb 包）。
- 回滚方式：备份拷回 `/etc/nginx/nyh/`；`apt-get remove libnginx-mod-http-brotli-filter`（会删掉 `modules-enabled/50-mod-http-brotli-filter.conf`）；`nginx -t && systemctl reload nginx`。
- 做了什么：
  1. 检查包脚本：`libnginx-mod-http-brotli-filter` 1.0.0~rc-6 的 postinst 只触发 `nginx-reload`，不重启；ABI 与 nginx 1.26.3 一致。安装后 `nginx -t` 通过。没有装 `brotli-static`（本机没有预压缩的 .br 文件）。
  2. `http.conf` 在 gzip 段后追加 `brotli on`、`brotli_comp_level 5`、`brotli_min_length 1k`，`brotli_types` 只含文本类静态资源，**不含** `application/json`、`text/event-stream`，避免影响 API 流式输出；图片不压。
  3. `tovo.sh.conf`：去掉 `listen 443 quic`、`http3 on` 和 `Alt-Svc` 头。其它 vhost 仍有 `listen 443 quic`，但 tovo.sh 不再发 Alt-Svc，浏览器不会对它用 h3。
  4. 试过让 tovo.sh 由 nginx 做 Brotli（`proxy_set_header Accept-Encoding ""` + `gzip_proxied any`），看起来像是静态文件返回了首页 HTML，立即回滚；后来查明那次测试打到了 DNS 指向的旧机（见下），但这条路本身也不通：上游一直回 gzip，nginx 不会对已压缩的响应再做 Brotli。**tovo.sh 目前仍是 new-api 自带的 gzip**，要 Brotli 需另做（nginx 托管预压缩的静态文件）。
- 验证：`kanova.app` 返回 `content-encoding: br`；`api.kanova.app`、`ddricher.ai` 200；tovo.sh（`--resolve` 到新机）静态 JS 200 gzip、无 Alt-Svc；`/api/status` JSON 正常。
- **发现的问题（未处理，已告知用户）**：
  - 22:25 前后，Cloudflare 权威 DNS 上 `tovo.sh` 的 A 记录是 `137.184.127.196`（DigitalOcean，疑似旧部署 DO-1），不是 `8.217.145.133`。当时访问 tovo.sh 的人会到旧机，新机上的账号和令牌在那里都不能用。
  - `bnsg.konghai.me` 仍解析到旧机 `47.239.167.8`（11-11 00:00 到期）。

## 2026-11-10 21:45 CST - new-api 开第一个客户账号 aozhuo-test 并充值 ¥50

- 服务器：`nyh-prod-2026`（只改 new-api 后台数据，RDS `new_api` 库）
- 操作人：`Claude`（用户要求）
- 做了什么：
  1. 管理员 `POST /api/user/` 建用户 id 2 `aozhuo-test`，显示名「奥卓测试账号」，分组 `default`；`PUT /api/user/` 补备注（创建接口不保存 `remark`）。
  2. `POST /api/user/manage` `add_quota` / `add` 25000000 额度 = ¥50（站内 1 单位 = ¥1，`QuotaPerUnit=500000`）。
  3. 以该用户登录建 API 令牌 `default`（不限额度、不过期，受账户余额约束）。初始密码与令牌只在 gitignore 的 `nyh-prod-2026/secrets.local.md`。
- 验证：`GET /api/user/2` 余额 ¥50.0；客户令牌访问 `/v1/models` 200；`/api/pricing` 中两个 Seedance 模型对 `default` 分组可用。`/v1/models` 返回空列表（推测任务类模型不进这个列表，未核实源码；root 用同分组提交任务已验证可用）。
- 回滚：后台禁用 / 删除用户 2，或 `add_quota` `subtract` 扣回额度。

## 2026-11-10 21:25–21:40 CST - new-api 接入 Seedance 渠道、配置计费，端到端出片验证

- 服务器：`nyh-prod-2026`（只改 new-api 后台配置，存在 RDS `new_api` 库）
- 操作人：`Claude`（用户提供供应商测试 key 与计费口径）
- 供应商：北京通天云计算有限公司，方舟项目 `liao-1110`，key 直连火山方舟官方 `https://ark.cn-beijing.volces.com`（`GET /api/v3/contents/generations/tasks` 200）。key / AK / SK 只在 gitignore 的 `nyh-prod-2026/secrets.local.md`；new-api 只用 API key，AK/SK 不需要。
- 计费口径：售价 = 官方价 ×1（客户折扣走线下充值返点）；成本 fast 4 折、mini 3 折。
- 做了什么：
  1. 渠道 id 1「通天云-Seedance（liao-1110）」：类型 Doubao(54)，模型 `doubao-seedance-2-0-fast-260128`、`doubao-seedance-2-0-mini-260615`，分组 `default`。
  2. 币种：`general_setting.quota_display_type=CNY`、`USDExchangeRate=1`，即站内 **1 计费单位 = ¥1**（`QuotaPerUnit=500000` 额度 = ¥1）。客户充值时按人民币金额加额度。
  3. 计费表达式（`billing_setting.plugin_billing_expr`，按官方价页面，元/百万 token）：
     - `doubao::doubao-seedance-2-0-fast-260128`：不含视频输入 37，含参考视频 22
     - `doubao::doubao-seedance-2-0-mini-260615`：不含视频输入 23，含参考视频 14
     - 写法：`u("video_input") == "video" ? tier("video", u("tokens") * 22 / 1000000) : tier("base", u("tokens") * 37 / 1000000)`。两个模型都只有 480p / 720p，同价。
  4. 用 root 临时令牌提交 mini 480p 4 秒文生视频（原生路径 `POST /api/v3/contents/generations/tasks`），约 94 秒成功；验证完删除令牌。
- 验证：
  - 计费：预扣按估算 38430 token = 441945 额度，完成按实际 40594 token 补扣 24886，合计 466831 = 40594 × 23 / 1e6 × 500000（¥0.9337），与官方价 ×1 一致。
  - 下载：`GET /v1/videos/<task_id>/content` 经网关代理返回 200 `video/mp4` 1.15MB。
  - 注意：原生查询接口返回的 `content.video_url` 是方舟 TOS 签名链接，**24 小时过期**；网关代理下载也是去取这个链接，所以客户必须 24 小时内下载转存。
- 回滚：后台删除渠道 1、清空 `billing_setting.plugin_billing_expr`，币种改回 USD / 7.3。

## 2026-11-10 21:00–21:15 CST - 部署 new-api（tovo.sh），用于对外转售 Seedance

- 服务器：`nyh-prod-2026`、RDS `pgm-j6cf5kaej216sx0z`
- 操作人：`Claude`（用户要求：重新部署 QuantumNous/new-api，首要支持 Seedance，对外给下游客户用并计费；旧部署数据不要；库用 RDS PG）
- 选型：
  - 镜像固定 `calciumion/new-api:v1.0.0-rc.49`（11-08 发布，= 当时的 latest）。Seedance 由内置任务插件 `plugins/tasks/doubao`（v1.4.0）提供：1.0 pro/lite、1.5 pro、2.0 / 2.0-fast / 2.0-mini、2.5，外加 Seedream 生图。渠道类型选「Doubao」(54)。
  - 库：RDS 新建库 `new_api`（UTF8 / en_US.utf8）+ 普通账号 `new_api_user`（DBOwner）。`SQL_MAX_OPEN_CONNS=40`（默认 1000，RDS 2C4G、max_connections 400 多项目共用）。
  - Redis：专用容器 `new-api-redis`（`redis:8.0.5`，不发布端口，AOF，maxmemory 192mb），新建宿主机系统用户 `newapi-redis`（991:988）运行；密码在 `redis.conf` 而不是命令行（宿主机 `ps` 看不到）。不接 `shared-redis`：new-api 不支持 key 前缀。
  - 入口：`127.0.0.1:3200` → nginx vhost `tovo.sh.conf`。全局 `http.conf` 开着 `proxy_cache` 和 `proxy_next_upstream … http_500 http_503 http_404`，vhost 里显式 `proxy_cache off`、`proxy_next_upstream off`（防止缓存接口、重放提交导致重复计费），另 `proxy_buffering off`、读超时 900s、`client_max_body_size 128m`。
- 影响：新增独立 compose 栈和 vhost；nginx 平滑 reload 2 次；没有重启任何现有服务。
- 备份：新增项，无需备份。
- 回滚方式：`cd /opt/stacks/new-api && docker compose down`；删 `/etc/nginx/nyh/vhost/tovo.sh.conf` 后 `nginx -t && systemctl reload nginx`；`certbot delete --cert-name tovo.sh`；RDS `DeleteDatabase new_api`、`DeleteAccount new_api_user`；`userdel newapi-redis`。
- 做了什么：
  1. `aliyun rds CreateAccount new_api_user`、`CreateDatabase new_api`、`GrantAccountPrivilege … DBOwner`。
  2. 服务器 `/opt/stacks/new-api/`（root 700）：`compose.yaml`（仓库 `nyh-prod-2026/docker/new-api/`），`.env`（600）与 `redis.conf`（`newapi-redis` 600）按仓库 `env.example` / `redis.conf.example` 生成，真实值备份在 gitignore 的 `nyh-prod-2026/secrets.local.md`。`SESSION_SECRET` / `CRYPTO_SECRET` 已固定，**不要轮换**（会让渠道密钥解不开、已发出的视频下载链接失效）。
  3. 临时 80 端口 vhost → `certbot certonly --webroot … --cert-name tovo.sh`（到期 2027-02-08，deploy-hook reload nginx）→ 换正式 vhost。
  4. `docker compose up -d`；容器 healthy 后、正式 vhost 上线前，在本机 `127.0.0.1:3200` 调 `POST /api/setup` 初始化 root，防止公网抢先初始化。
  5. 后台设置：`ServerAddress` / `TaskPublicAddress` = `https://tovo.sh`（视频结果签名下载链接用）；`RegisterEnabled=false`（先关闭公开注册，客户账号由管理员开，要开放自助注册时再改）。
- 验证：启动日志「数据库使用 PostgreSQL」「Redis 已启用」「New API v1.0.0-rc.49 已启动」，两个容器 healthy；`http://tovo.sh` 301 到 HTTPS，`https://tovo.sh/api/status` 200，证书 CN=tovo.sh；服务器到 `ark.cn-beijing.volces.com` 建连 67ms、`ark.ap-southeast.bytepluses.com` 230ms。
- 未做（等用户提供）：供应商的 Seedance 渠道（API key、Base URL）、模型定价与分组倍率、端到端出片验证。

## 2026-11-10 19:20 CST - Kanova 部署目录改为与 CI 一致（python/acquilang → python/kanova）

- 服务器：`nyh-prod-2026`
- 操作人：`Claude`（用户要求：acquilang 是旧项目名，服务器路径改成和 CI 统一；换代码 / 容器另开 session）
- 原因：Kanova 的 CI workflow 部署到 `/www/wwwroot/python/kanova`（`kanova-admin`、`kanova-mobile-web/out`、`app_build`），服务器上是 `/www/wwwroot/python/acquilang/acquilang-*`。
- 影响：**没有重启容器**（`acquilang-backend` / `acquilang-admin` 启动时间改名前后一致）；nginx 平滑 reload 一次。
- 备份：`/root/kanova-path-20261110/`（原 `docker-compose.prod.yml`、`kanova.app.conf`、`m.acquilangai.com.conf`、容器启动时间）。
- 回滚方式：`rm /www/wwwroot/python/acquilang && mv /www/wwwroot/python/kanova /www/wwwroot/python/acquilang`，子目录改回 `acquilang-*`，备份文件拷回原位，`nginx -t && systemctl reload nginx`。
- 做了什么：
  1. `mv /www/wwwroot/python/acquilang /www/wwwroot/python/kanova`，并 `ln -s kanova /www/wwwroot/python/acquilang`：运行中的 `acquilang-backend` 绑定挂载的是旧路径（`static`、`uploads`），符号链接保证以后容器重启也能解析。
  2. 子目录 `acquilang-{admin,backend,mobile-native,mobile-web,pc-web}` 改为 `kanova-*`。目录里没有指向旧路径的绝对符号链接。
  3. `docker-compose.prod.yml`：挂载路径改到 `/www/wwwroot/python/kanova/…`，顶部加 `name: acquilang`（容器、网络仍叫 `acquilang-*`；不固定的话从新目录执行 compose 会按目录名另起一个 `kanova` 项目，和现有容器名冲突）。`docker compose config` 通过，`compose ps` 能看到现有两个容器。
  4. `kanova.app.conf`、`m.acquilangai.com.conf` 的移动端静态目录改为 `/www/wwwroot/python/kanova/kanova-mobile-web/out`；nginx 里不再有旧路径。
- 验证：`kanova.app/`、`/download/`、`/build-Latest.apk`、`admin.kanova.app/`、`api.kanova.app/api/v1/health` 均 200；容器内 `/app/uploads` 可读写；CI 用到的 `kanova-admin`、`kanova-mobile-web/out`、`app_build`、`docker-compose.prod.yml`、`scripts/deploy-backend-full.sh` 都存在。
- 未做（用户另开 session）：服务器代码换成 GitHub main（现为旧版 `cdcffd45`，remote 仍是 `AcquiLangAI.git`），容器 / 镜像 / 网络换成 `kanova-*`，`backup-rds.sh` 容器名，之后删除 `acquilang` 符号链接和 `name: acquilang`。

## 2026-11-10 19:00–19:10 CST - 上线快照；CI 部署切到新机；删除两个废弃站点

- 服务器：`nyh-prod-2026`（GitHub 仓库 Secret 也有改动）
- 操作人：`Claude`（用户要求：用 gh 改各仓库部署 Secret、打快照、删除废弃站点的配置和文件）
- 影响：root `authorized_keys` 增加 3 把 CI 部署公钥；nginx 平滑 reload 1 次；删除 `zen-design-hualu.konghai.me`、`nyh-2025.konghai.me` 两个站点。
- 备份：快照 `s-j6cct8y5ay0igrzzwuhb`（`nyh-prod-2026-live-20261110`，删除之前打）；`/root/cutover-20261110/authorized_keys.bak-before-ci`；`/root/cutover-20261110/abandoned-sites-20261110.tar.gz`（两个站点的 vhost、rewrite、证书、网站文件，14M）。
- 回滚方式：authorized_keys 拷回备份；站点 `tar -xzf … -C /` 后 `nginx -t && systemctl reload nginx`；GitHub Secret 改回 `47.239.167.8`（旧机 11-11 00:00 起不可用，实际无回滚意义）。
- 做了什么：
  1. 快照 `nyh-prod-2026-live-20261110`，19:03 创建，完成后才做第 4 步。
  2. 旧机 root `authorized_keys` 里 `github-actions@acquilangai`、`github-actions@yunshu-bnsg`、`github-actions-deploy-key-ddricher` 三行原样追加到新机（都是无选项限制的 ed25519）。旧机另外的 `hon-2025`、`hon-2026`、`konghai-recovery-2025`、`deploy_key_for_nyh_2025` 没有迁。
  3. 扫描用户 / `konghai-friends-lab` / `caimiamiao` 下 49 个仓库，只有 3 个部署到 nyh：`gh secret set` 改了 `IAmKongHai/Kanova` 的 `SERVER_HOST`、`konghai-friends-lab/YPF-YunShu` 的 `SSH_HOST` 和 `SSH_KNOWN_HOSTS`（新机 `ssh-keyscan` 结果，指纹与服务器本机 host key 一致）、`konghai-friends-lab/ddricherAi` 的 `HOST`，都改为 `8.217.145.133`。端口、用户（22 / root）新旧一致，没改。qingfan、tk-flywheel、cmm 的部署 Secret 指向其它服务器，没动。
  4. 删除 `zen-design-hualu.konghai.me`（用户确认已废弃、DNS 已删）、`nyh-2025.konghai.me`（原宝塔面板入口，不再使用）：vhost、rewrite、`/etc/nginx/nyh/cert/` 证书目录、`/www/wwwroot/` 网站目录、`/www/wwwlogs/` 日志（含旧名 `zen.design.hualu`）。删前确认没有其它 nginx / cron / supervisor / systemd 配置引用、没有打开的文件、没有 `chattr +i`。仓库里对应 vhost / rewrite 一并删除。
  5. `-al.konghai.me` 三个 vhost 保留：它们和 kanova.app 三个 vhost 共用网站目录与 extension 目录，且 Kanova 发版前可能需要临时恢复 DNS。
- 验证：
  - YunShu `ops-readonly`（只读查询）workflow run `42804438571` 成功，新机 sshd 记录到 CI 公钥登录。Kanova、ddricherAi 没有只读 workflow，等下次正常部署验证。
  - 删除后 `nginx -t` 通过，load / konghai.me / ddricher.ai / kanova.app 均 200。
- 本机 `/etc/hosts`：用户手动把 `mp.nanyahui.com` 改为 `100.113.16.89`、注释掉 `fa.nanyahui.com`。19:09 验证：经 Tailscale（来源 `100.92.181.15`）访问 `/admin/` → 303 到 `/admin/login` → 200，白名单放行正常。

## 2026-11-10 18:38–19:10 CST - 迁移收尾（计划 U6）：证书改 certbot、修 apt 源、删迁移密钥、档案

- 服务器：`nyh-prod-2026`
- 操作人：`Claude`（用户确认开始 U6）
- 影响：nginx 平滑 reload 3 次；apt 源地址变更；root `authorized_keys` 少一行。业务进程没有重启。
- 备份（都在 `/root/cutover-20261110/`）：`vhost.bak/`（改证书路径前的全部 vhost）、`acme.conf.bak`、`sources.list.bak`、`docker.list.bak`、`authorized_keys.bak`。
- 回滚方式：把对应备份拷回原位；nginx 相关的再 `nginx -t && systemctl reload nginx`。
- 做了什么：
  1. **证书**：16 张新证书 `certbot certonly --webroot -w /var/www/letsencrypt --deploy-hook "systemctl reload nginx"`（证书名沿用 `/etc/nginx/nyh/cert/` 下的目录名；`ddricher.ai` 含 www，`load.nanyahui.com` 含 `api.nanyahui.com`），全部到期 2027-02-08。vhost 证书路径改到 `/etc/letsencrypt/live/<名>/`。`guagua.honc.fun` 原本就是 certbot 管理（webroot `/www/wwwroot/guagua/acme`，vhost 一致），没改；我误跑的 `certbot reconfigure` 改 webroot 因验证失败没有生效。
     - `mp.nanyahui.com` 第一次 403：站点级 `deny all` 白名单把 ACME 验证也挡了。`snippets/acme.conf` 的 location 里加 `allow all`（location 写了访问规则就不继承 server 级），只放开 `/.well-known/acme-challenge/`；之后从 tizi-kh / 旧机访问 `/admin/` 仍是 403，白名单正常。
     - 没换的：`-al.konghai.me` 三个（DNS 已删）、`zen-design-hualu`、`nyh-2025`（废弃）、默认站点（自签）。
  2. **apt**：`/etc/apt/sources.list`、`sources.list.d/docker.list` 从 `http://mirrors.cloud.aliyuncs.com` 改成 `https://mirrors.aliyun.com`（内网镜像 `100.100.2.148` 被 Tailscale 丢包），`apt-get update` 无错误。
  3. 删除 root `authorized_keys` 里旧机迁移临时密钥（`from="47.239.167.8"` 那行），确认本机仍可登录。
  4. 仓库同步服务器现状：`cron/nyh-tasks` 去掉 `#OFF#`（服务器上只差两行头注释，未推送）、`supervisor/*.conf` 改 `autostart=true`。
  5. 文档：`nyh-prod-2026/README.md` 重写为完整档案（服务、操作、cron、证书、nginx、shared-redis 登记表、坑、已知问题）；`nyh-prod/README.md` 标注退役；`AGENTS.md` 服务器表与生产守则改为 nyh-prod-2026。
- 验证：20 个域名从公网握手，证书都是新签的且与主机名匹配；业务健康检查（容器、9 个队列、11 个 supervisor 程序、jobs:monitor）全部正常。`certbot renew --dry-run`（全量，日志 `/root/cutover-20261110/certbot-dryrun.log`）staging 很慢（约 45 分钟），**18 张全部 success**（含 guagua.honc.fun，说明它原有的 webroot 配置可用）。

## 2026-11-10 18:27–18:35 CST - 上线 Kanova 正式域名 kanova.app / admin.kanova.app / api.kanova.app

- 服务器：`nyh-prod-2026`
- 操作人：`Claude`（用户已把三个域名 A 记录指向新机；`m.kanova.app` 不用，移动端直接用 `kanova.app`）
- 原因：用户删除了 `admin-al` / `api-al` / `m-al.konghai.me`，Kanova 改用正式域名。
- 影响：新增 3 个 vhost，`api.acquilangai.com.conf`（api-al）的 CORS 白名单加了新域名，`systemctl reload nginx` 两次（平滑）。
- 备份：`/root/cutover-20261110/api.acquilangai.com.conf.bak.20261110`。
- 回滚方式：删除 `/etc/nginx/nyh/vhost/{kanova.app,admin.kanova.app,api.kanova.app}.conf`，还原 api 备份，`nginx -t && systemctl reload nginx`。
- 做了什么：
  1. 临时 80 端口 vhost（只放 ACME 目录）→ `certbot certonly --webroot -w /var/www/letsencrypt --cert-name kanova.app -d kanova.app -d admin.kanova.app -d api.kanova.app --deploy-hook "systemctl reload nginx"`（已有 LE 账号）→ 删临时 vhost。证书到期 2027-02-08。
  2. `nyh-prod-2026/nginx/nyh/vhost/` 新增 `kanova.app.conf`（复制自 m-al）、`admin.kanova.app.conf`（admin-al）、`api.kanova.app.conf`（api-al），只改 `server_name`、证书路径和日志文件名，去掉重复的 `proxy_cache_path`；旧 `-al` vhost 保留。
  3. 两个 API vhost 的 CORS 白名单都加上 `https://admin.kanova.app`、`https://kanova.app`。
- 验证：`kanova.app/`、`/download/`、`admin.kanova.app/`、`api.kanova.app/api/v1/health` 均 200，HTTP 301 到 HTTPS；证书 SAN 含三个域名；CORS 预检对新旧前端域名返回对应 `Access-Control-Allow-Origin`，对其它来源不返回；`/build-Latest.apk` 200（35.6MB）。
- 未完成：应用里仍写死旧域名（admin 前端 JS、APK 的 `EXPO_PUBLIC_API_URL`、后端 `PUBLIC_APP_URL=https://m-al.konghai.me`、CI workflow），需要改代码重新发布；`-al` DNS 已删，旧 App 目前连不上。

## 2026-11-10 18:05–18:30 CST - DNS 切换后验证；修复 Cloudflare 回源 525（TLS HelloRetryRequest）

- 服务器：`nyh-prod-2026`
- 操作人：用户改 DNS；`Claude` 验证、排查、改 nginx
- 原因：用户 18:05 前后把 DNS 改到 `8.217.145.133`，开始公网验证。
- 影响：`/etc/nginx/nginx.conf` 加了一行 `ssl_ecdh_curve`（见下），`systemctl reload nginx`（平滑，不断连接）；装了 `tcpdump`。
- 备份：`/etc/nginx/nginx.conf.bak.20261110`。
- 回滚方式：`cp /etc/nginx/nginx.conf.bak.20261110 /etc/nginx/nginx.conf && nginx -t && systemctl reload nginx`。
- 验证与发现：
  1. 公网经新 IP 访问 18 个站点，状态码与旧机基准一致。
  2. **`numbers.konghai.me`（Cloudflare 橙云）回源 525**。tcpdump 看到：Cloudflare 第一个 ClientHello（517 字节，SNI 正确）→ 新机回 99 字节 HelloRetryRequest（random 以 `cf21ad74…` 开头）→ Cloudflare 第二个 ClientHello（1471 字节，带 X25519MLKEM768）→ 新机回 alert `fatal illegal_parameter(47)` 并断开。原因是 Debian 13 的 OpenSSL 3.5 默认按 `X25519MLKEM768 / X25519…` 分组，客户端只带 X25519 key share 时也会要求改用抗量子组；旧机宝塔的 OpenSSL 不支持 ML-KEM，不会走 HRR。OpenSSL 客户端（s_client 3.5）走 HRR 能成功，只有 Cloudflare 回源失败。
     修复：`nyh-prod-2026/nginx/nginx.conf` 的 http 块加 `ssl_ecdh_curve X25519MLKEM768:X25519:prime256v1:secp384r1;`（单个优先级组，客户端带了哪个组的 key share 就直接用，不发 HRR）。之后 numbers 返回 403，与旧机基准相同（站点根目录无首页）；tizi-kh 用 X25519MLKEM768 / X25519 / P-256 分别握手都成功。
  3. 新机 apt 不能用：源 `mirrors.cloud.aliyuncs.com` 解析为 `100.100.2.148`，与 VPC DNS 一样被 Tailscale `ts-input` 丢弃。这次临时用 `deb.debian.org` 单独装了 tcpdump，系统源配置没改，待修。
  4. jobs 监控（`/var/log/nyh-cron/*-jobs-monitor.log`）每 5 分钟一次，均为"异常 0 组"；微信回调已经打到新机。
  5. 旧机 18:20 后只剩 `nyh-2025`（宝塔，弃用）、`load.nanyahui.com` 上合作方 `119.23.185.225`（Java 客户端，只读的 `/openapi/v1/orders`、`balance`）仍走旧 IP，旧机到 RDS 只剩 1 条连接。17:52 后旧机只收到两个 POST（17:55 微信支付回调、17:56 新机发来的订单回调，都在改 DNS 前，返回 200；队列在 RDS `jobs` 表，新机 worker 照常处理）。
  6. 权威 DNS 仍是旧 IP：`load.nanyahui.cn`、`guagua.honc.fun`、`kanova.app` / `admin.kanova.app` / `api.kanova.app`；`zen-design-hualu.konghai.me`、`m.kanova.app` 没有记录；用户已删 `admin-al` / `api-al` / `m-al`。

## 2026-11-10 17:51–18:00 CST - 切换（计划 U5）：后台任务从旧机交接到新机

- 服务器：`nyh-prod-2026`（旧机一侧见 `docs/operations/nyh-prod.md` 同一时间的条目）
- 操作人：`Claude`（用户确认开始切换）
- 原因：旧 ECS 将于 11-11 00:00 CST 到期，不续费。
- 影响：17:51–17:52 旧机后台任务停止后，约 1 分钟内新机接手；网站请求两台机器都能处理（共用 RDS），DNS 改完前旧机 nginx / php-fpm 继续接流量。
- 备份 / 回滚（22:30 前）：新机 `bash /root/cutover-20261110/rollback-new.sh` → 旧机 `bash /root/cutover-20261110/rollback-old.sh` → DNS 改回 `47.239.167.8`。
- 做了什么：执行 `/root/cutover-new.sh`（源码 `nyh-prod-2026/cutover/cutover-new.sh`，与服务器副本 md5 一致），日志 `/root/cutover-20261110/cutover-new.log`：
  1. 导入旧机 17:51 的宝塔 Redis 快照（2.9M，4 个库）到 `redis-7480`。
  2. 重启 `archery`；启动 `php74-worker`（9 个队列）、宿主机 supervisor（10 个 line-* + nyh-notify）、`yunshu-api`、`acquilang-backend`、`richer-engine-1` / `richer-gateway-1` / `richer-web-1`。
  3. 启用 `guagua-api`、`nyh-wechat-mp`、`nyh-wechat-mp-watchdog.timer`；`/etc/cron.d/nyh-tasks` 去掉 `#OFF#`，启用 10 行。
- 验证：
  - 所有容器 Up，php74-worker 内 9 个队列、宿主机 11 个 supervisor 程序全部 RUNNING，guagua-api / nyh-wechat-mp active。
  - 切换后在新机 `--resolve 127.0.0.1` 重跑 25 域名 × 3 路径基准（`_backups/nyh-prod-migration-20261110/baseline-new-2-postcutover.txt`），与旧机基准 `baseline-old.txt` diff：除计划内不建站的 `fa.nanyahui.com` 外**全部一致**，之前 502 的 ddricher.ai、api-al、bnsg、guagua 已恢复（gateway / guagua 根路径 404 与旧机相同）。
  - `richer-gateway-1` 日志的 Telegram `401 Unauthorized`、Tiger 美股行情 `permission denied` 在旧机过去 24 小时各有 4 万余条，属于原有问题，不是迁移引入。
  - 待做：用户改 DNS 后公网逐站验证、观察队列 / cron 日志、确认旧机 RDS 连接归零。

## 2026-11-10 16:30–17:35 CST - 迁移准备（计划 U2–U4）：搭环境、首轮同步、起无状态服务

- 服务器：`nyh-prod-2026`（只读访问 `nyh-prod`，在旧机 `/www/backup/migrate-images/` 写了镜像导出文件、`/root/.ssh/migrate_nyh2026` 临时迁移密钥）
- 操作人：`Claude`（用户确认按计划执行；新机不装宝塔，PHP、Redis 用 Docker）
- 计划：`docs/plans/2026-11-10-1545-ops-nyh-prod-to-nyh-prod-2026-migration-plan.md`
- 影响：新机还没有线上流量（DNS 仍指向旧机）；旧机业务不受影响。
- 备份：旧机系统盘快照 `s-j6c9be0n6eh1zjh04l8w`（`nyh-prod-system-final-20261110`）；数据盘快照见 16:10 条目。
- 回滚方式：新机上的东西都可以直接停掉 / 删除，旧机没动。
- 做了什么：
  1. 用户：删除镜像自带的 `admin`；新建 `www`(1000)、`nyh-notify`(999)、`nyh-wechat-mp`(994)、`shared-redis`(993)、`redis7480`(992)。
  2. apt 装 nginx 1.26.3、supervisor、certbot、fail2ban、logrotate 等；Docker CE 29.7.2（阿里云内网源，GPG 公钥从 download.docker.com 取，指纹 `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`）；Tailscale 1.104.5。
  3. Docker `daemon.json`：`bip 172.17.0.1/16`（应用里写死了 172.17.0.1），`default-address-pools 10.210.0.0/16 /24`。**原因**：新机内网是 `172.21.0.0/18`、RDS 在 `172.31.x`，docker 默认池会挑 172.18–31 的 /16，撞上就会把网关或 RDS 的路由劫持掉。
  4. Tailscale：节点 `nyh-prod-2026`（`100.113.16.89`），`--advertise-exit-node --accept-dns=false`，IP 转发已开。用户已授权登录。
  5. **DNS 被 Tailscale 搞坏（已修）**：`tailscale up` 之后阿里云 VPC DNS `100.100.2.136/138` 的应答被 Tailscale 的 `ts-input` 链丢弃（源地址在 100.64/10），所有域名解析卡死。照搬旧机的 `fix-aliyun-dns-vs-tailscale.service`（DNS 改用 223.5.5.5 / 223.6.6.6 / 8.8.8.8），在它之前创建的容器全部重建以拿到新的 resolv.conf。
  6. PHP：自建镜像 `nyh/php74:7.4.33`、`nyh/php82:8.2.35`（debian:trixie + Sury），`/opt/stacks/php/`，`php74-fpm` :9074、`php82-fpm` :9082，host 网络；`php74-worker`（9 个队列进程）在 compose profile `worker` 里，未启动。php.ini / FPM 池参数按旧机导出值；模块与旧机对比无缺失。
     - 旧机 `date.timezone = PRC` 在 Debian 13 无效（会退回 UTC），改成 `Asia/Shanghai`，镜像另装 `tzdata-legacy`。
     - **Sury 的 PHP-FPM 构建内置 "Secure DNS Telemetry"**（`/usr/lib/php/php-common.mk`：`TELEMETRY_HOST=telemetry.sury.org`、端口 53），启动时会联系 `telemetry.sury.org`，没有关闭开关；CLI 二进制里没有。容器 `extra_hosts` 把它指向 `127.0.0.1`，数据不会出去。
     - `/usr/local/bin/php74`、`php82` 是包装脚本（`docker exec -u www -w $PWD`），cron 和 CI 的 `php74 think …` 不用改。
  7. Redis 7480：容器 `redis-7480`（`redis:8.0.5`，`/opt/stacks/redis-7480/`），配置来自旧机（密码不变），以 `redis7480` 用户运行，端口发布 `127.0.0.1:7480` 与 `172.17.0.1:7480`。数据目录放 `/opt/stacks/redis-7480/data`，不放 `/www/docker`（迁移 rsync 带 `--delete`）。
  8. nginx：`scripts/convert-baota-nginx.py` 把宝塔 26 个站点转写到 `/etc/nginx/nyh/`（仓库 `nyh-prod-2026/nginx/`），去掉 lua well-known、site_total、WAF，ACME 统一走 `/var/www/letsencrypt`；证书 27 套 + `/etc/letsencrypt` 由旧机直接推送。`nginx -t` 通过并启动。
  9. 首轮 rsync（旧机经临时密钥推送，`from="47.239.167.8"` 限制）：`/www/wwwroot` 9.1G 等，镜像 3.5G；16:38–16:56。
  10. 起了：`php74-fpm`、`php82-fpm`、`redis-7480`、`shared-redis`（新 UID 重建）、`acquilang-admin`、`richer-web` + `richer-nginx`（先建外部网络 `richer_strategy_plus_network` 177.10.0.0/16）、`archery`、`nyh-wechat-mp`。
     **没起（有定时逻辑，U5 再起）**：`php74-worker`、宿主机 supervisor（10 个 line-* + nyh-notify）、`yunshu-api`（reminder.scheduler）、`acquilang-backend`（`ENABLE_METRICS_SCHEDULER=true`）、`richer-engine` / `richer-gateway`（策略 / 行情告警）、`richer-web-1`（反代依赖 engine）、`guagua-api`（每分钟轮询 push_jobs）、`/etc/cron.d/nyh-tasks`（全部 `#OFF#`）、nyh-wechat-mp watchdog timer。
  11. 轻量服务器防火墙加 443/udp（HTTP/3）、41641/udp（Tailscale）；8080（do1-relay 只允许 tailnet）、7480 不对公网开放。
- 验证：
  - 25 个域名在新机 `--resolve 127.0.0.1` 下与旧机基准逐行对比：全部 PHP 站点及 smith、duowei、admin-al、m-al 的状态码、关键响应头、证书**完全一致**；ddricher.ai / gateway / api-al / bnsg API / guagua 为 502（后端按计划未起）；fa.nanyahui.com 不再建站（403）。
  - PHP 容器经 ThinkPHP 只读查询 RDS：`wq_url`、`jobs` 积压 0 正常；FPM 启动 1.6s。
  - nyh-wechat-mp `/healthz`：pg / redis 正常，rules=6。
  - Python venv（3.13.5）可导入 `nyh_line`；nyh-notify、guagua-api 二进制可运行。
  - Tailscale：到 do-1 直连，sub2api 返回 200。mas-sit 不通，旧机也不通；菜苗苗 SIT 反代早已不在，`cmm-sit-healthz` 不再迁移。

## 2026-11-10 15:55 CST - 内网互通后打通 RDS PostgreSQL

- 服务器：`nyh-prod-2026`、RDS `pgm-j6cf5kaej216sx0z`
- 操作人：用户在控制台开通轻量服务器「内网互通」（关联 `vpc-j6cy0gudplcfwatq8i43f`）；`Claude` 加白名单并验证
- 原因：迁移计划 U1-2，新机要连 nyh-prod 各业务共用的 RDS PG。
- 影响：RDS 新增白名单分组 `swas_nyh2026` = `172.21.63.219`（新机内网 IP），现有分组没动；新机装了 `postgresql-client`（17.11）。
- 回滚方式：`aliyun rds ModifySecurityIps --profile default --DBInstanceId pgm-j6cf5kaej216sx0z --DBInstanceIPArrayName swas_nyh2026 --SecurityIps 172.21.63.219 --ModifyMode Delete`。
- 验证：
  - 只开内网互通、没加白名单时，`nc 172.31.138.209 5432` 仍然超时（RDS 对不在白名单的来源直接丢包，不是拒绝）。
  - 加白名单后 `nc` 成功；用不存在的账号 `conn_probe` 登录返回 `password authentication failed`，说明已经走到 PG 认证这一步。域名 `pgm-j6cf5kaej216sx0z.pg.cnhk.rds.aliyuncs.com` 在新机解析为 `172.31.138.209`，和旧机一致，应用配置不用改。

## 2026-11-10 14:30–14:45 CST - 核对内存；重装适配 6.12 内核的云盾 Aegis

- 服务器：`nyh-prod-2026`
- 操作人：`Claude`（用户要求）
- 原因：用户指出套餐是 16G 内存，档案里写的 14G 不对；并要求 Debian 13 升级完成后把云盾装回去，装适配当前内核的版本。
- 影响：空机器；为验证开机自启重启 1 次。
- 备份 / 回滚：快照 `s-j6ch07g86tunb409g1tf`（`debian13-baseline-20261110`，装云盾前，已 `accomplished`）。
- 内存核对：套餐 `swas.s.c4m16s80b1.linux` 就是 16G。`lsmem` 在线内存 15.5G，`MemTotal` 15569516 kB；`crashkernel` 按 `4G-16G:256M` 预留了 256M，再扣掉固件 / PCI 地址空间，`free -h` 按 GiB 显示成 `14Gi`。内存没有少，是之前档案写错了，已改正。
- 做了什么：
  1. 下载并读过官方脚本 `http://update2.aegis.aliyun.com/download/install.sh`（阿里云实例内免安装密钥，自动绑定所属账号）和 `AliAqsInstall_64.sh`（需要控制台密钥，没用），存到 `/root/aegis-install/`。
  2. 执行 `bash install.sh`（日志 `/root/aegis-install/install.log`），退出码 0，`Aegis successfully installed`。客户端自更新到 `aegis_11_37`，自己写了 `/etc/systemd/system/aegis.service` 并 enable，删掉了安装脚本放的 `/etc/init.d/aegis`。
  3. `systemctl daemon-reload` 后重启，验证开机自启。
- 内核适配：`AliYunDunUpdate` 会按运行中的内核下发组件。6.12.116 上没有 `.ko`，**不加载 `AliSecGuard` 内核模块**，改用 eBPF（`AliYunDunMonitor` 持有 89 个 bpf fd），`/proc/sys/kernel/tainted` = 0。不需要我们手动挑版本。
- 验证（重启后）：
  - `systemctl is-system-running` = `running`，无失败 unit；`aegis` / `aliyun` 都是 `active`；`AliYunDunUpdate`、`AliYunDun`、`AliYunDunMonitor` 三个进程开机即起。
  - `journalctl -b -p err` 除已知可忽略项外无新报错。
  - `aliyun sas DescribeCloudCenterInstances`：`InternetIp 8.217.145.133`、`ClientStatus online`、`Kernel 6.12.116+deb13-amd64`。

## 2026-11-10 14:05–14:25 CST - 纳入仓库，卸载云盾，Debian 12 原地升级到 13

- 服务器：`nyh-prod-2026`（`root@8.217.145.133`，阿里云香港轻量服务器，实例 `a9670f44600c4671a95c2a46a795657a`）
- 操作人：`Claude`（用户要求）
- 原因：用户新购这台机器替代 `nyh-prod`，要求先能用公钥登录，再升级到 Debian 13。
- 影响：空机器，没有业务；共重启 2 次。
- 备份：
  - 快照 `s-j6cf8ldl9p1wznd46hrm`（`debian12-before-upgrade`，升级前）
  - 服务器：`/root/.ssh/authorized_keys.bak.20261110`（原为空）、`/root/grub.default.bak`、`/root/grub.default.pre-efi.bak`、`/root/sources.list.bookworm.bak`
  - 本机：`~/.ssh/config.bak.20261110`
- 回滚方式：`aliyun swas-open stop-instance` → `reset-disk --disk-id d-j6c31h3s5ffawxajzmpq --snapshot-id s-j6cf8ldl9p1wznd46hrm` → `start-instance`（`--profile default --biz-region-id cn-hongkong`），回滚后 `ssh-keygen -R 8.217.145.133`。回滚后云盾会回来。
- 做了什么：
  1. 本机公钥（`id_ed25519` / root / `ecs-user` / `admin` 等组合）全部 `Permission denied`：镜像里 root 的 `authorized_keys` 是空的。在 aliyun `default` profile 下找到这台实例，云助手在线，用 `swas-open run-command` 把 `~/.ssh/id_ed25519.pub` 写入 `/root/.ssh/authorized_keys`。
  2. 本机 `~/.ssh/config` 追加 `Host nyh-prod-2026`。
  3. 按手册 2.2 节核对，镜像特征完全一致：`grub-pc` + `grub-efi-amd64-bin/signed`，无 `grub-efi-amd64`；`cloud-init` 被 hold；`GRUB_SERIAL_COMMAND="serial --speed=115200n8"`；云盾 `AliSecGuard` 模块已加载。
  4. 打快照 `debian12-before-upgrade`。
  5. 卸载云盾（用户确认）：加开机参数 `systemd.mask=aegis.service module_blacklist=AliSecGuard` 重启 → 跑官方 `uninstall.sh` / `quartz_uninstall.sh` → 删残留 → 还原 `/etc/default/grub`。
  6. `systemd-run --unit=upgrade-trixie` 后台跑 `/root/upgrade-trixie.sh`（日志 `/root/upgrade-trixie.log`），`Result=success`，无 `E:` / `dpkg: error`。
  7. 修 grub：预设 debconf（ESP `/dev/disk/by-id/virtio-j6c31h3s5ffawxajzmpq-part2`、`force_efi_extra_removable`），修正 `GRUB_SERIAL_COMMAND`，`grub-pc` 换成 `grub-efi-amd64`，`grub-install --target=x86_64-efi --uefi-secure-boot --force-extra-removable`，`update-grub`。
  8. 重启前检查全部通过后重启。
  9. 打基线快照 `s-j6ch07g86tunb409g1tf`（`debian13-baseline-20261110`）。
- 验证：
  - 重启前：模块 `2.12-9+deb13u2`、`bli.mod` 存在；ESP 两处 shim 哈希 `e103c5d02657`、grub 哈希 `425ffb5b84e8` 均与包内签名文件一致；只缺允许的 `ieee1275_fb` / `vbe` / `vga`；只装 `grub-efi-amd64`，无 hold、无半安装包；`sshd -t` 通过；cloud-init `25.1.4` 能 import。
  - 重启后一次开机成功：`13.7`、`6.12.116+deb13-amd64`、`systemctl is-system-running` = `running`、无失败 unit、`cloud-init status: done`、`eth0 routable`、时钟已同步、云助手 `active`、无 `AliYunDun` 进程。`journalctl -p err` 只有手册列出的可忽略项（RETBleed、AF_VSOCK、dhclient `/bin/true`）。
- 待办：
  - 确认稳定后删除快照 `debian12-before-upgrade`。
  - 上线业务前：关 LLMNR（5355 对公网监听）、配防火墙、决定是否保留 root 直登。

# do-1

**生产服务器**（DigitalOcean SFO3 旧金山，`ubuntu-s-4vcpu-8gb-sfo3`）。主要承载 `sub2api` 订阅配额分发网关（作为 `nyh-prod-2026` `new-api` 的上游供应商），2026-11-11 起本机**只跑 sub2api**：原 `new-api`（`tovo.sh`，现在在 `nyh-prod-2026`）、qingfan 与 tk-flywheel（现在在 `qingfan-prod`），以及旧域名 `qingfan.konghai.me` / `tk.konghai.me`，都已从本机彻底移除（服务、配置、证书、DO 托管库），见 [`docs/operations/do-1.md`](../docs/operations/do-1.md)。DO 托管 PG 现在只剩 `sub2api` 库；`doadmin` 凭据在 `/root/do-pg-admin.env`（600）。

> 原 `DigitalOcean` 仓库已于 2026-11-11 合并进本仓库后废弃（最后提交 `d0e8b49`，其中 `hosts/tk-pro` 即本机）。配置源码在 `do-1/` 下按服务器绝对路径镜像存放（`etc/`、`usr/local/`），外部打包脚本在 `ci-templates/`。旧手册见 [`docs/runbooks/do-1-ops-manual.md`](../docs/runbooks/do-1-ops-manual.md)，运维时间线见 [`docs/operations/do-1.md`](../docs/operations/do-1.md)。

## 连接与实例

```bash
# 大陆本机直连公网 IP 137.184.127.196 易超时，优先走 Tailscale 内网 IP：
ssh -i ~/.ssh/id_ed25519 root@100.86.92.103
```

| 项目 | 值 |
| --- | --- |
| 公网 IP | `137.184.127.196`（Cloud Firewall 禁公网 ICMP 与 `:8080`，放行 TCP `22` / `80` / `443`、UDP `41641`） |
| Tailscale | `100.86.92.103`，节点名 `do-1` |
| 云厂商 / 地域 | DigitalOcean，`sfo3`（旧金山） |
| 系统 | Ubuntu 24.04.4 LTS，内核 `6.8.0-147-generic` |
| 规格 | 4 vCPU / 8 GiB RAM / 160 GB SSD |
| TCP 调优 | `bbr` + `fq`、`tcp_slow_start_after_idle=0`、32MiB TCP buffer（`/etc/sysctl.d/98-cross-ocean-tcp.conf`，源码 `etc/sysctl.d/`） |

## 核心服务（`sub2api`）

| 组件 | 位置 / 说明 |
| --- | --- |
| 蓝绿服务 | `sub2api@blue.service`（`:8081`）/ `sub2api@green.service`（`:8082`），当前活跃槽记录于 `/opt/sub2api/active_slot` |
| 发布与回滚 | `/usr/local/sbin/sub2api-deploy`、`/usr/local/sbin/sub2api-rollback`、`/usr/local/sbin/sub2api-backup` |
| Upstream | `/etc/nginx/upstreams/sub2api-upstream.conf`（由 `sub2api-deploy` 自动切换端口并 reload nginx） |
| 主入口（公网 HTTPS 白名单） | `https://sub.tovo.sh`（`:443`，`/etc/nginx/sites-available/sub2api.conf`），**仅放行 `8.217.145.133`（`nyh-prod-2026`）+ `100.64.0.0/10` + 回环** |
| 备入口（Tailscale 内网） | `http://100.86.92.103:8080`（`:8080`，同上配置文件，仅放行 `100.64.0.0/10` + 回环） |
| 官方 LLM 美区透明出口 | `:443` 与 `:8080` 下的 4 条无状态路径反代（均剥离 `X-Real-IP`/`X-Forwarded-For`、开启 TLS SNI 与上游 Keep-Alive 连接池），供香港 `nyh-prod-2026` `new-api` 绕过海外供应商对香港 IP 的 `403` 锁区：<br>• `location ^~ /groq/` → `https://api.groq.com/openai/`（`groq-upstream.conf`）<br>• `location ^~ /anthropic/` → `https://api.anthropic.com/`（`anthropic-upstream.conf`）<br>• `location ^~ /gemini/` → `https://generativelanguage.googleapis.com/`（`gemini-upstream.conf`，支持 WebSocket Upgrade）<br>• `location ^~ /openai/` → `https://api.openai.com/`（`openai-upstream.conf`，支持 `/v1/realtime` WebSocket Upgrade） |
| Nginx 注意事项 | `/etc/nginx/nginx.conf` 已开启 `underscores_in_headers on;`（保留 `session_id` 粘性会话头）；`sub2api.conf` 开启 `proxy_request_buffering off;`、`proxy_buffering off;`、`keepalive_timeout 120s;` |

## 证书与自动续期

- 由 `certbot.timer` 每日两次自动检查续期，续期成功后触发 `/etc/letsencrypt/renewal-hooks/deploy/reload-nginx`（`nginx -t && systemctl reload nginx`）。
- `sub.tovo.sh` 使用独立 webroot `/var/www/sub2api-acme`。由于 `:443` 开启了严格 IP 白名单，`:80` 与 `:443` 的 `location ^~ /.well-known/acme-challenge/` **必须保留独立的 `allow all;`**，切勿删除，否则会导致 Let's Encrypt 自动续期 `403` 失败。
- 续期演练命令：
  ```bash
  certbot renew --cert-name sub.tovo.sh --dry-run --no-random-sleep-on-renew
  ```

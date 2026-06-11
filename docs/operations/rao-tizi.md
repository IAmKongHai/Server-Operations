# rao-tizi 运维时间线

## 2026-06-11 12:25 CST - 调整 S-UI 用户流量月度重置时间

- 服务器：`rao-tizi`
- 操作人：`Codex`
- 原因：服务商对该服务器的流量重置时间为每月 11 日，原 S-UI 用量重置定时任务在每月 1 日执行，和服务商周期不一致。
- 影响：root crontab 中 S-UI 用户用量归零任务从每月 1 日 23:59 改为每月 11 日 23:59；未重启服务，未修改当前数据库用量数据。
- 回滚：
  - 恢复修改前 root crontab：`crontab /root/crontab.bak.20260611-122514`
  - 或将任务日期改回每月 1 日：`59 23 1 * * /usr/bin/sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE clients SET up = 0, down = 0;"`
- 变更：
  - 修改前备份 root crontab 到 `/root/crontab.bak.20260611-122514`
  - 将原任务 `59 23 1 * * /usr/bin/sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE clients SET up = 0, down = 0;"` 改为 `59 23 11 * * /usr/bin/sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE clients SET up = 0, down = 0;"`
- 验证：
  - `crontab -l` 已显示新任务：`59 23 11 * * /usr/bin/sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE clients SET up = 0, down = 0;"`

## 2026-05-20 10:29 CST - 接管 litellm-us DNS 流量并签发正式证书

- 服务器：`rao-tizi`
- 操作人：`Codex`
- 原因：用户已在 Cloudflare 将 `litellm-us.konghai.me` 改为 A 记录 `64.64.253.141`，生产服务器 `nyh-prod` 解析和访问已切到 `rao-tizi`。
- 影响：`litellm-us.konghai.me:8443` 正式由 `rao-tizi` 上的 Nginx 承载；`s-ui` 仍占用 `443/tcp`，未修改或重启。
- 回滚：
  - DNS 回滚到旧值 `tz.skysms.xyz` 或 `74.211.103.83`
  - 如需回滚证书路径，可恢复 `/etc/nginx/conf.d/llm-proxy.conf.bak.202605201029` 后执行 `nginx -t && systemctl reload nginx`
- 变更：
  - 使用 certbot 为 `litellm-us.konghai.me` 正式签发新证书，lineage 为 `litellm-us-konghai-me-20260520`
  - 将 Nginx 证书路径从复制证书切换到 `/etc/letsencrypt/live/litellm-us-konghai-me-20260520/`
  - 备份切换前 Nginx 配置到 `/etc/nginx/conf.d/llm-proxy.conf.bak.202605201029`
  - 移走第一次同名签发失败留下的无效 renewal 配置：`/etc/letsencrypt/renewal/litellm-us.konghai.me.conf.invalid.202605201032`
- 验证：
  - `nyh-prod` 解析 `litellm-us.konghai.me` 为 `64.64.253.141`
  - `nyh-prod` 访问 `https://litellm-us.konghai.me:8443/openai/` 返回上游 `421`
  - `nyh-prod` 访问 `/anthropic/`、`/cerebras/`、`/xai/`、`/groq/` 分别返回上游 `404`、`405`、`421`、`404`
  - 端口证书 issuer 为 Let's Encrypt `E7`，有效期为 `2026-05-20 09:31:17 CST` 到 `2026-08-18 09:31:16 CST`
  - `certbot certificates` 仅列出有效 lineage `litellm-us-konghai-me-20260520`
  - `certbot renew --dry-run --cert-name litellm-us-konghai-me-20260520 --no-random-sleep-on-renew` 成功
  - `nginx -t` 通过，Nginx 仍只监听 `80/tcp` 和 `8443/tcp`，`443/tcp` 仍由 `sui` 监听
- 后续：
  - 继续观察 Nginx access/error log 和 `certbot-renew.timer`。
  - 切换稳定后如需停用 `tizi` 上 Nginx，需要另行确认。

## 2026-05-20 09:51 CST - 预置 litellm-us 反向代理备用入口

- 服务器：`rao-tizi`
- 操作人：`Codex`
- 原因：准备接管 `tizi` 上的 `litellm-us.konghai.me` Nginx 反向代理，降低主代理服务器流量超额关机风险。
- 影响：安装 Nginx / certbot，新增 Nginx 服务监听 `80/tcp` 和 `8443/tcp`，firewalld 新增放行 `80/tcp` 和 `8443/tcp`；未修改 DNS，未停止或重启 `s-ui`。
- 回滚：
  - 停止并禁用 Nginx：`systemctl disable --now nginx`
  - 移除新增防火墙端口：`firewall-cmd --permanent --remove-port=80/tcp`、`firewall-cmd --permanent --remove-port=8443/tcp` 后 reload
  - 如需恢复执行前状态，参考备份目录 `/root/backup/litellm-migration-20260520095153/`
- 变更：
  - 创建迁移前备份目录：`/root/backup/litellm-migration-20260520095153/`
  - 安装 `nginx-1.20.1`、`certbot-3.1.0`、`python3-certbot-nginx-3.1.0`
  - certbot 来自 EPEL；服务器已安装 `epel-release`，本次安装用 `--enablerepo=epel`
  - 从 `tizi` 通过 SSH 管道迁移 `/etc/nginx/conf.d/llm-proxy.conf` 和 `litellm-us.konghai.me` 当前证书文件；私钥未落到本地仓库
  - firewalld 新增放行 `80/tcp` 和 `8443/tcp`
  - 启用并启动 Nginx
  - 启用并启动 `certbot-renew.timer`
  - 新增 certbot deploy hook：`/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh`
- 验证：
  - `nginx -t` 通过
  - Nginx 为 `active` / `enabled`
  - `certbot-renew.timer` 为 `active` / `enabled`
  - Nginx 只监听 `80/tcp` 和 `8443/tcp`
  - `443/tcp` 仍由 `sui` 监听
  - firewalld 当前放行 `443/tcp 80/tcp 8443/tcp`
  - `64.64.253.141:8443` 使用 SNI `litellm-us.konghai.me` 返回复制证书，证书有效期为 `2026-02-24 09:59:46 CST` 到 `2026-05-25 09:59:45 CST`
  - 使用指定解析到 `64.64.253.141` 的预切验证结果：
    - `/openai/` 返回上游 `421`
    - `/anthropic/` 返回上游 `404`
    - `/cerebras/` 返回上游 `405`
    - `/xai/` 返回上游 `421`
    - `/groq/` 返回上游 `404`
- 后续：
  - DNS 尚未切换，正式流量仍在 `tizi`。
  - 复制证书即将在 `2026-05-25 09:59:45 CST` 到期；DNS 切到 `rao-tizi` 后必须立即用 certbot 为 `litellm-us.konghai.me` 正式签发/接管续期。
  - 当前 `certbot certificates` 尚不会列出该复制证书；正式签发后才会形成可自动续期的 certbot lineage。

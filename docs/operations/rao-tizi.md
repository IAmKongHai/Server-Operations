# rao-tizi 运维时间线

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

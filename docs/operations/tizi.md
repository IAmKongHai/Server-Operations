# tizi 运维时间线

## 2026-05-20 09:51 CST - 为 litellm-us 反向代理迁移创建回滚备份

- 服务器：`tizi`
- 操作人：`Codex`
- 原因：`tizi` 流量接近限额并存在关机风险，准备将 `litellm-us.konghai.me` 的 Nginx 反向代理迁移到备用代理 `rao-tizi`。
- 影响：只创建备份并读取状态；未修改 Nginx、firewalld、crontab、DNS 或 `s-ui`。
- 回滚：本次未改运行状态，不需要服务级回滚。若后续迁移步骤需要恢复 `tizi` 原配置，可使用 `/root/backup/litellm-migration-20260520095153/` 中的备份。
- 变更：
  - 创建迁移前备份目录：`/root/backup/litellm-migration-20260520095153/`
  - 备份 `/etc/nginx` 到 `etc-nginx.tgz`
  - 备份 `litellm-us.konghai.me` 的 Let's Encrypt live/archive 证书与 SSL 参数到 `etc-letsencrypt-litellm.tgz`
  - 记录 firewalld、root crontab、监听端口和 `nginx -T` 输出
- 验证：
  - `nginx` 仍为 `active` / `enabled`
  - `nginx -t` 通过
  - `80/tcp` 和 `8443/tcp` 仍由 Nginx 监听
  - `443/tcp` 仍由 `sui` 监听
  - 当前证书有效期仍为 `2026-02-24 09:59:46 CST` 到 `2026-05-25 09:59:45 CST`
- 后续：
  - DNS 切换前保留 `tizi` 上现有 Nginx 服务作为回滚目标。
  - 切换稳定前不删除 `tizi` 上的配置、证书或日志。

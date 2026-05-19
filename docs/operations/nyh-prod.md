# nyh-prod 运维时间线

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


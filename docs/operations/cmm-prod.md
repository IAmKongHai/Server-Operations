# cmm-prod 运维时间线

## 2026-10-31 10:20 CST - 重启生效 6.12.113 内核（CVE-2026-98432）；重启后 api 因 COS 451 起不来

- 服务器：`cmm-prod`（Debian 13，主机名 `VM-0-12-debian`，Tailscale `100.94.204.38`；公网入口是 caddy `:80` / `:443`）
- 操作人：`Claude`（用户已确认；用户说当时没有订单）
- 原因：运行内核 `6.12.95` 受 CVE-2026-98432 影响。修复内核 `6.12.113-1` 已由 `unattended-upgrades` 装好，只差重启。排查见 `docs/reviews/2026-10-31-cve-2026-98432-kernel-exposure.md`。
- 影响：整机重启一次，约 30 秒（10:20:04 → 10:20:33）。
- 备份：旧内核 `6.12.95` 还在 GRUB 的 Advanced options 里。重启前记录了现状：4 个容器 `cmm-production-{admin,api,worker}-1`、`redis`，restart 策略都是 `unless-stopped`；compose 目录 `/data/apps/cmm`。
- 回滚方式：控制台开机时在 GRUB 里选 `6.12.95`。注意：回滚内核解决不了下面的 COS 问题。
- 做了什么：`systemctl reboot`。
- 验证：
  - `uname -r` = `6.12.113+deb13-amd64`，没有 failed 的单元。caddy、redis、admin（healthy）、worker 都正常。
  - **`cmm-production-api-1` 一直处于 `Restarting (1)`。** 日志反复出现 `COS request failed: code=UnavailableForLegalReasons`（HTTP 451），之后进程退出。api 启动时要访问 `COS_BUCKET_URL=https://cmm-prod-uploads-1469943699.cos.ap-guangzhou.myqcloud.com`。
  - 匿名 `curl` 这个 bucket 返回的是正常的 `403 AccessDenied`，只有 api 带签名的请求返回 451，说明是腾讯云在账号或 bucket 层拦截（腾讯云文档对 451 的说明是「因法律原因不可用，请提工单」），跟内核无关。
  - 重启前 api 从 10-21 起已连续运行 9 天，日志里那段时间没有 COS 报错。COS 只在启动时校验，所以 451 是什么时候开始的，现在判断不了。
- 待处理：用户到腾讯云控制台查这个 bucket 和账号（欠费、封禁、违规通知），或者提工单。COS 恢复后 api 会被 restart 策略自动拉起，不需要手工操作。


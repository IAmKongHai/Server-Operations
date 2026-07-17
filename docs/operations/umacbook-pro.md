# umacbook-pro 运维操作时间线

## 2026-07-17 20:16 CST - 纳管新机：SSH 密钥登录 + 快捷别名

- 服务器：`umacbook-pro`（Tailscale `100.113.23.49`，主机名 `UdeMacBook-Pro.local`）
- 操作人：`Grok`
- 原因：Tailscale 网内新机，计划用于跑 GitHub Actions self-hosted runner；先完成纳管与免密登录。
- 影响：
  - 本机 `~/.ssh/config` 新增 `Host umacbook-pro` 快捷别名（`User for-konghai`，密钥 `~/.ssh/id_ed25519`）。
  - 远端 `~/.ssh/authorized_keys` 写入本机公钥（`konghai@konghai.me` ed25519）。
  - **未**改 SSH 服务配置、未禁用密码登录、未装 runner。
- 机器现状（只读探测）：
  - OS：macOS 15.7.2 / arm64（Apple M1）
  - 内存：8 GB
  - 根盘：228G 总量，约 114G 可用（14% 使用）
  - 登录用户：`for-konghai`（uid 502，属 admin 组，可 sudo）
  - 家目录：`/Users/for-konghai`
  - 已开机约 159 天
- 备份：
  - 本机 SSH config：`~/.ssh/config.bak.<timestamp>`（执行前复制）
- 回滚方式：
  - 删除本机 `~/.ssh/config` 中 `Host umacbook-pro` 段，或从对应 `.bak` 还原。
  - 远端：从 `~/.ssh/authorized_keys` 移除本次写入的公钥行。
- 变更时序：
  1. 确认 Tailscale 可达：`ping 100.113.23.49`、`nc` 探 22 端口。
  2. 用一次性密码经 `ssh-copy-id` 安装公钥到 `for-konghai@100.113.23.49`。
  3. 本机 `~/.ssh/config` 追加 `umacbook-pro` Host 块（风格对齐 `lemon-imac` / `mac-mini`）。
  4. `ssh -o BatchMode=yes umacbook-pro` 验证公钥免密登录。
- 验证：
  - `ssh umacbook-pro 'whoami'` → `for-konghai`
  - `BatchMode=yes` 成功（无密码交互）
  - `~/.ssh/authorized_keys` 权限 `600`，属主 `for-konghai`
- 后续：
  - 安装 / 注册 GitHub Actions runner（待用户确认组织、labels、并发数量）
  - 密码仅用于首次密钥安装，文档不落盘；如不再需要密码登录可再评估加固

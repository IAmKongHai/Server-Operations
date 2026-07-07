# lemon-imac 运维操作时间线

## 2026-07-07 22:43 CST - 接入 Tailscale iMac SSH 别名并安装公钥

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，设备名 `lemon-imac` / 主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：新增一台 iMac 作为后续 runner 机器，需要从本机通过 Tailscale 内网稳定 SSH 登录，并设置易记别名。
- 影响：
  - 本机 `~/.ssh/config` 新增 `Host lemon-imac`，指向 `100.81.246.93`，用户 `for-konghai`，使用 `~/.ssh/id_ed25519`。
  - 远端 `for-konghai` 用户的 `~/.ssh/authorized_keys` 加入本机公钥，后续可用 `ssh lemon-imac` 免密登录。
  - 未安装 runner，未启动或重启服务，未修改系统级 SSH 配置。
- 备份：
  - 本机 SSH 配置备份：`~/.ssh/config.bak.20260707-ssh-lemon-imac`。
  - 远端授权文件备份：`/Users/for-konghai/.ssh/authorized_keys.bak.20260707-ssh-lemon-imac`。
- 回滚方式：
  - 本机删除 `~/.ssh/config` 中 `Host lemon-imac` 配置块，或用备份文件恢复。
  - 远端从 `/Users/for-konghai/.ssh/authorized_keys` 删除本机公钥行，或恢复上述备份文件。
- 变更时序：
  1. 确认 Tailscale 中 `100.81.246.93` 在线；用户在图形界面开启 SSH 后，22 端口可用。
  2. 备份本机 SSH 配置并追加 `lemon-imac` 别名。
  3. 通过密码认证把本机 `id_ed25519.pub` 上传到远端临时目录。
  4. 远端创建/更新 `~/.ssh/authorized_keys`，设置 `~/.ssh` 为 `700`、`authorized_keys` 为 `600`，并清理临时公钥文件。
  5. 使用 `ssh lemon-imac` 验证公钥免密登录。
- 验证：
  - `ssh lemon-imac` 登录成功，返回用户 `for-konghai`。
  - 系统：macOS `26.5.1`（Build `25F80`），架构 `arm64`。
  - 当前可用基础工具：`git`、`curl`、`tar`、`unzip`、`xcodebuild`。
  - 暂未发现 GitHub Actions runner 目录或 runner 进程；`brew`、`node`、`npm`、`dotnet`、`docker` 暂不在当前 `PATH`。

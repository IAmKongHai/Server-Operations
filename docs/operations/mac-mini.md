# mac-mini 运维时间线

## 2026-06-09 14:03 CST

- 原因：`backend` / `frontend-mas` pin 到含 SQSCANGHA-135 修复的 `SonarSource/sonarqube-scan-action` commit 后，Scanner CLI 8.1.0.6389 默认启用 GPG 签名校验。mac-mini 已安装 `/opt/homebrew/bin/gpg`，但 4 个 GitHub Actions runner service 的 `.path` 不包含 `/opt/homebrew/bin`，导致 CI 报 `GPG is not available`。修复 PATH 后又暴露出第二层问题：默认 `workFolder: _work` 生成的 `RUNNER_TEMP` 路径过深，Sonar action 的临时 `GNUPGHOME` 下 `S.gpg-agent` / `S.dirmngr` socket 接近 macOS 路径限制，导致 `File name too long` / `gpg-agent: IPC connect call failed`。
- 影响：两轮重启 `mac-mini-sonar-1..4` runner service。第一次修改 `.path` 时先重启空闲的 `1/2/4`，等待 `mac-mini-sonar-3` 的 `Runner.Worker` 退出后再重启 `3`；第二次确认无 `Runner.Worker` 后统一重启 4 个 runner。期间一个 frontend PR run 的 `Frontend Tests` 被 runner2 重启打断，已通过 GitHub `force-cancel` 结束，并重新触发 PR run。
- 回滚方式：把对应 runner 目录的 `.path.bak.20260609-140142` 复制回 `.path`，把 `.runner.bak.20260609-142350` 复制回 `.runner`，再执行该 runner 目录下的 `./svc.sh stop && ./svc.sh start`。
- 做了什么：备份并修改 4 个 runner 的 `.path`，在原 PATH 前追加 `/opt/homebrew/bin`。

```text
/opt/homebrew/bin:/Users/konghai/.cargo/bin:/Users/konghai/.volta/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

- 做了什么：备份并修改 4 个 runner 的 `.runner`，把 `workFolder` 改到短路径。

```text
mac-mini-sonar-1: /Users/konghai/gha/s1
mac-mini-sonar-2: /Users/konghai/gha/s2
mac-mini-sonar-3: /Users/konghai/gha/s3
mac-mini-sonar-4: /Users/konghai/gha/s4
```

- 验证结果：4 个 `Runner.Listener` 进程的实际 `PATH` 均包含 `/opt/homebrew/bin`；以各自进程 PATH 执行 `command -v gpg` 均返回 `/opt/homebrew/bin/gpg`，`gpg --version` 返回 `gpg (GnuPG) 2.5.18`；短路径下 `S.gpg-agent` 路径长度约 68；`launchctl list` 显示 `actions.runner.cypressoai.mac-mini-sonar-1..4` 均为 Started；`backend` PR SonarQube Scan 重跑成功；`frontend-mas` PR SonarQube PR Scan 重跑成功。

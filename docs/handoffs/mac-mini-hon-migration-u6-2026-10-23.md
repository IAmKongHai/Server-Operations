---
artifact_contract: "ce-handoff/v1"
created_at: "2026-10-23T05:59:26Z"
title: "mac-mini 团队资产迁到 hon：剩余 U6（清理 konghai 与重启验证）"
summary: "U1–U5、U7 已完成并验证；剩 U6：10-29 后删 konghai 的 colima VM、Multica、claude-cron、临时 sudoers，并做计划内重启验证"
keywords: ["mac-mini", "hon", "konghai", "migration", "U6", "colima", "runner", "sudoers", "reboot"]
cwd: "/Users/konghai/Code/Project/Server"
resume_focus: "执行计划 U6：清理 konghai 名下团队残留并做一次计划内重启验证"
repository: "Server（个人运维笔记仓库）"
repo_root_sha: "105e22b22e8936b9788d571dd0dd845a4cf8424d"
branch: "main"
head: "a5705e05dd5cf10a45a5decce594fb53a11ee49c"
---

# Handoff：mac-mini 团队资产迁到 hon —— 剩余 U6

- 日期：2026-10-23
- 计划：`docs/plans/2026-10-22-1645-ops-mac-mini-team-assets-to-hon-plan.md`（U6 在「### U6. Clean konghai and reboot test」，KTD11 是删除保留期）
- 执行记录：`docs/operations/mac-mini.md` 顶部 2026-10-22 19:14 起的 6 条（U2/U3、ServBay、U5、U4、U7）
- 现状约定：`AGENTS.md` 的 mac-mini 行与「`mac-mini` 目录约定」；`docs/runbooks/mac-mini-runner-start-stop.md`

## 目标与用户意图

用户的决定：konghai 只做私人用途，团队 runner / 服务 / 凭据全部归 hon，重启后不需要任何人登录 hon 就自动恢复。用户要求「过两天再继续」剩余工作。

## 已完成（均已验证、已提交到 main）

| 单元 | 状态 | 关键事实 |
|---|---|---|
| U1 准备 | 完成 | 快照 `/var/backups/hon-migration-20261022/`（root 700，机器本地） |
| U2 服务 | 完成 | 13 个容器在 hon 的 colima `team`，20 个库大小与基线一致；SonarQube / AcquiLang 备份 LaunchDaemon 已验证 |
| U3 runner | 完成 | CIWork 挂 `/Users/hon/gha`，11 个普通 runner 以 hon 运行，各池真实 job 通过 |
| U4 khmini | 完成 | LaunchDaemon `actions.runner.cypressoai-moo-decision.khmini`；需要 moo-decision#67（用户已合并），develop 自动部署已成功 |
| U5 签名 runner | 完成 | mobile-1 / acquilang-native-1 以 hon 运行，iCare 与 AcquiLang Android 打包各成功一次；konghai 的 `~/.config/icare`、Android SDK、`~/.expo/state.json` 已删 |
| U7 文档 | 完成 | AGENTS / runbook / 脚本改 hon，机器上 `gha/scripts` 与 runner 目录 plist 副本已同步（HEAD `a5705e0`） |
| 额外 | 完成 | ServBay 残留（sudoers、hosts、3 张根证书）已清；hon 的 `team` 改 `autoActivate: false`，默认 context 恢复 `colima-moo` |

## U6 剩余工作（未开始）

全部是删除或重启，按 `AGENTS.md`「生产服务器操作守则」每项删除前都要用户确认。

1. **10-29 起才可做**（U2 停 konghai VM 是 2026-10-22 19:19，KTD11 保留 7 天）：
   - `colima delete` konghai 的 `default` profile（当前 Stopped，100G 磁盘）；删 `/Library/LaunchDaemons/com.konghai.colima.plist`（当前 disabled）。
   - 删 konghai 的 `~/stacks`、`~/backups`（8.4G）、`~/scripts/acquilangai-backup.sh`。hon 下已有副本。
2. **随时可做**：
   - Multica：konghai 有 `~/Library/LaunchAgents/ai.multica.daemon.konghai.plist`、`~/.multica/profiles/konghai`、`~/multica_workspaces_konghai`。注意：10-22 时 `multica daemon status`（konghai）显示 running pid 1881，但 1881 实际是 hon 的 `multica daemon … --device-name khmini`；konghai 的 daemon 是否在跑要重新确认，别误杀 hon 的。服务端 runtime `mac-mini-konghai` 的注销方式待查（`multica runtime list` 里 konghai 相关的是 `Mac-mini.local` / `mac-mini` 设备名，均 offline）。
   - 删 `~/claude-cron`（crontab 行已于 U2 删除）。
   - 收回临时权限：`/etc/sudoers.d/konghai-hon-migrate` + `/usr/local/sbin/hon-migrate.sh`、`hon-team-services.sh`；过期的 `/etc/sudoers.d/konghai-ciwork` + `/usr/local/sbin/ciwork-migrate.sh`。`konghai-diag`、`konghai-fsetest` 用户要求长期保留，不动。需要 root，由用户执行。
   - 删 konghai 的 `~/hon-migrate-src/`（安装源，机器本地）。
   - 迁移导出 `/Users/hon/migration/`（17G，含 dump、卷 tar、基线）与快照 `/var/backups/hon-migration-20261022/`、`/var/backups/servbay-removal-20261023/`：计划要求 U6 结束后经用户同意再删。
3. **计划内重启验证**（FileVault 需用户本人解锁，不登录 hon）：期望 12 个启用 runner online（14 个中 acquilang-ci-4/5 disabled）、`team` 全部容器 Up、moo / multica 照常、手动触发一次日维护成功。已知例外：moo-app（khmini 部署的 SIT 服务）重启后不会自动回来，要等下一次 SIT 部署，这是计划里的延后项。
4. 收尾：`ps -U konghai` 无 `Runner.Listener` / `colima` / `limactl` / `multica` / `docker`；`grep -l konghai /Library/LaunchDaemons/*.plist` 只剩 `com.konghai.fseventsd-watchdog`（系统级，保留）；写运维记录并提交。

## 需要知道的坑（本次实际踩过）

- 改 root 脚本后要用户执行 `ssh -t mac-mini 'sudo ~/hon-migrate-src/install-hon-migrate.sh'` 重装，sudoers 只放行 `/usr/local/sbin/hon-migrate.sh` 和 `hon-team-services.sh`。macOS `/bin/bash` 3.2：变量后紧跟中文全角字符必须写 `${VAR}`。
- konghai 和 hon 的登录 shell 都是 zsh：通配符不匹配会报错，`set -- $var` 不拆分；多步逻辑用 `bash -s`。
- `visudo -c` 对非 0440 的 sudoers 文件返回失败（`/etc/sudoers.d/*` 已统一为 0440）。
- 卸载 CIWork 要 `diskutil unmount force`（常驻 spindump / mds 只读占用）。
- hon 的 docker 默认 context 必须是 `colima-moo`；khmini 不设 `DOCKER_HOST`，其它 runner 和定时任务显式指向 `team` socket。
- konghai 的 GitHub 访问：本机 gh 有 `k-cypresso`（cypressoai）和 `IAmKongHai`（AcquiLangAI、caimiamiao、konghai-friends-lab，用 `GH_TOKEN=$(gh auth token -u IAmKongHai)`）。

## 与 U6 无关、用户明确搁置的事

- AcquiLang 生产同步自 2026-10-19 起报「生产库 public 表只有 48，停止」；hon 下 `com.cypressoai.acquilang-prod-sync` 装好但 disabled。用户说「先不管，不着急」。KTD9（nyh-prod 受限密钥）同样未做，属生产改动需单独确认。
- Expo 账号 `koghai` 在 mac-mini 上的服务端会话需用户在 Expo 后台注销（本地 `state.json` 已删）。
- iOS 签名构建未验证（iCare preview iOS 会提交 TestFlight 外部审核）。

## 可能的下一步

10-29 之后一次做完 U6：先只读复查（`hon-migrate.sh --status`、`colima list`、`ps -U konghai`、确认 konghai Multica 状态），逐项向用户确认删除，再安排计划内重启。若 10-29 前继续，只能做第 2 项里的 Multica / claude-cron / 权限收回，以及重启验证（重启不依赖删除，可先做）。

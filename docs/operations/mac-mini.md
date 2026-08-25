# mac-mini 运维时间线

## 2026-08-25 13:57 CST - 恢复 mac-mini-sonar-3/4

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户要求把 2026-08-19 为 Multica 留并发而停掉的两个 sonar slot 重新拉起来。
- 影响：
  - `mac-mini-sonar` 独占重活（Coverage / 全量 branch Sonar / deploy quality-gate）回到最多四路并行。
  - 共享池多回 2 个 mac-mini slot（`frontend-tests-ci` / `frontend-quality-ci` / `backend-ci`）。
  - 本机 Multica（konghai daemon / hon daemon + `colima-multica`）仍在跑；四路 CI 高峰会再和本地 agent 抢 10 核。
  - **未**碰 `mac-mini-sonar-1/2`（当时正在跑 job）、`mac-mini-mobile-1`、`konghai-friends-lab-1`。未注销、未改 label。
- 选型：沿用 08-19 的回滚路径：`launchctl enable` + `bootstrap` 既有 LaunchDaemon plist；resume 脚本从当天备份还原为 kickstart 1..4 + mobile-1。未对 1/2 `kickstart -k`，避免打断进行中的 job。
- 备份：`~/bin/mac-mini-runner-resume.sh.bak.20260825-1356`（还原前那份只含 1/2 + mobile-1）
- 回滚方式（再停 3/4，不注销）：
  ```bash
  sudo /bin/launchctl disable system/actions.runner.cypressoai.mac-mini-sonar-3
  sudo /bin/launchctl disable system/actions.runner.cypressoai.mac-mini-sonar-4
  sudo /bin/launchctl bootout system/actions.runner.cypressoai.mac-mini-sonar-3
  sudo /bin/launchctl bootout system/actions.runner.cypressoai.mac-mini-sonar-4
  cp ~/bin/mac-mini-runner-resume.sh.bak.20260825-1356 ~/bin/mac-mini-runner-resume.sh
  ```
- 变更时序：
  1. 只读确认：3/4 `launchctl disabled` 且 service 不在 domain；plist 仍在 `/Library/LaunchDaemons/`；GitHub `offline`；1/2 `online` 且 `busy=true`。
  2. `cp` 备份当前 resume 脚本，再 `cp ~/bin/mac-mini-runner-resume.sh.bak.20260819-1634` 还原为含 1..4 + mobile-1。
  3. `sudo /bin/launchctl enable` 3/4。
  4. `bootstrap` 对应 plist（KeepAlive / RunAtLoad 仍为 true）。
- 验证结果：
  - launchd：3/4 `enabled`、`state=running`（pid 57164 / 57167）。
  - Listener：`mac-mini-sonar-3/4` 各一个 `Runner.Listener`（pid 57173 / 57174），日志 `Connected to GitHub` / `Listening for Jobs`，runner `2.336.0`。
  - GitHub：1..4 与 `mac-mini-mobile-1` 全部 `status=online`；3/4 拉起后立刻接活（3 → `SonarQube Scan`，4 → `Flag shared-code changes`）。
  - labels 未变：`self-hosted`, `mac-mini-sonar`, `macos`, `arm64`, `backend-ci`, `frontend-sonar-ci`, `frontend-tests-ci`, `frontend-quality-ci`。

## 2026-08-25 12:54 CST - 只读确认 iCare-frontend-mas CI 红叉为 Draft PR 门禁

- 服务器：`mac-mini`（runner `mac-mini-sonar-1`）；对照 `umacbook-pro-1`
- 操作人：`Grok`
- 原因：排查 [iCare-frontend-mas Actions run 32810598308](https://github.com/cypressoai/iCare-frontend-mas/actions/runs/32810598308)（PR [#1640](https://github.com/cypressoai/iCare-frontend-mas/pull/1640) `bugfix/CYP-2321/loa-diagnosis-insert-context`）的 job 失败是 runner 侧还是代码侧。
- 影响：仅通过 `gh` 读取 run / job / PR；未 SSH、未改 runner、workflow、PR 状态或业务代码，未重跑 job。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：
  1. 核对 run 全部 job 结论、失败步骤与日志。
  2. 核对 PR `isDraft` 与后续步骤是否被 skip。
- 验证结果：
  - Runner 正常接活：`Frontend Tests 3/4` 落在 `mac-mini-sonar-1`，`Frontend Tests 1/4`、`2/4`、`4/4` 落在 `umacbook-pro-1`；`Set up job` 成功，runner 版本 `2.336.0`，能下载 `actions/checkout@v4` 与 `actions/setup-node@v4`。排除 runner 初始化或网络故障。
  - 全部业务 job（Typecheck / Lint / Frontend Tests 1–4/4 / Frontend Tests 汇总 / SonarQube Scan）都在第一步 `Block while draft` 命中 draft 门禁，日志为 `Draft PR — CI is intentionally not run.` 后按设计 `exit 1`。Checkout、Setup Node、Install、test、lint、Sonar 扫描全部 skipped，业务代码实际上未被检查。
  - PR #1640 当前 `isDraft=true`。`Frontend Coverage` 因上游失败被 skip。
  - SonarQube Scan 另有一步 `Print open PR Sonar issues` 因 `if: always()` 仍执行，失败为 `node: command not found`（exit 127），因为前面的 `Setup Node.js` 已被 skip。这是草稿门禁的连带噪声，不是 runner PATH 故障。
  - 结论：不是 runner 故障，也不是业务代码失败，而是 Draft PR 的预期 required-check 门禁。点 **Ready for review** 后会自动跑真实 CI。

## 2026-08-24 17:30 CST - 仓库级 `ypf-yunshu-1` 改为组织级 `konghai-friends-lab-1`

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户要把 runner 改名为 `konghai-friends-lab-1`，并给 org 内其它仓库共用。仓库级 runner 做不到这一点。
- 影响：
  - 已从 `YPF-YunShu` 注销 `ypf-yunshu-1`（原 agentId 21）。
  - org `konghai-friends-lab` Default group 新增 `konghai-friends-lab-1`（agentId 8），label：`self-hosted`, `macOS`, `ARM64`, `konghai-friends-lab`。
  - Default group `visibility=all`、`allows_public_repositories=false`，org 内私有仓都能用。
  - 目录改为 `~/actions-runner/konghai-friends-lab-1`，workFolder `~/gha/kfl1`。
  - 仍以 `nohup ./runsvc.sh` 运行（PPID=1），GitHub `online`。重启后仍会掉，LaunchDaemon 还没装（写 `/Library/LaunchDaemons` 要密码）。
  - **未**碰 `cypressoai` runner。
- 选型：同一份 runner 2.336.0 二进制，重新 `config.sh` 指到 org URL。自定义 label 从 `ypf-deploy` 改为 `konghai-friends-lab`。未用 `--no-default-labels`。
- 备份：无覆盖。旧仓库级凭证已由 `config.sh remove` 清掉。
- 回滚方式：停 Listener 后用 org remove-token 注销；若要回到只给 YPF-YunShu 用，再按仓库 URL 注册。
- 变更时序：
  1. `gh auth refresh` 给 `IAmKongHai` 补 `admin:org`。
  2. 停 nohup Listener，`config.sh remove` 注销仓库级 runner。
  3. 目录改名，workFolder `ypf1` → `kfl1`。
  4. `config.sh --url https://github.com/konghai-friends-lab --name konghai-friends-lab-1 --labels konghai-friends-lab`。
  5. `nohup ./runsvc.sh` 拉起。
- 验证：
  - `.runner` 里 `gitHubUrl` 为 org，`poolName=Default`。
  - 日志 `Listening for Jobs`。
  - `gh api orgs/konghai-friends-lab/actions/runners` → `konghai-friends-lab-1` `online`，含 `konghai-friends-lab`。
  - `YPF-YunShu` 仓库级 runner 列表为空。
- 未做：未改 `YPF-YunShu` 的 `deploy.yml`。未装 LaunchDaemon。未改 `mac-mini-runner-resume.sh`。
- 下一步（本机 sudo 一次即可常驻）：
  ```bash
  sudo /Users/konghai/gha/scripts/install-konghai-friends-lab-runner-daemon.sh
  ```
  workflow 应写 `runs-on: [self-hosted, konghai-friends-lab]`。不要再用 `ypf-deploy`。

## 2026-08-24 17:19 CST - 注册 YPF-YunShu 仓库级 runner `ypf-yunshu-1`

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：org `konghai-friends-lab` Free 计划 8 月 Linux 分钟已用满 2000，GitHub-hosted `ubuntu-latest` 的 `deploy` job 秒失败（spending limit）。用户要把 `YPF-YunShu` 的 `deploy` 改到 self-hosted。
- 影响：
  - 仓库 `konghai-friends-lab/YPF-YunShu` 新增 runner `ypf-yunshu-1`（agentId 21），label：`self-hosted`, `macOS`, `ARM64`, `ypf-deploy`。
  - **未**注册到 org `konghai-friends-lab`，**未**碰 `cypressoai` 的 sonar / mobile runner。
  - 当前以 `nohup ./runsvc.sh` 在跑（PPID=1），GitHub `online`。图形用户已是 `root`，LaunchAgent 会掉线。
  - **重启后会 offline**：本机免密 sudo 只覆盖 `/bin/launchctl` 等，写 `/Library/LaunchDaemons` 需要密码，LaunchDaemon 尚未装上。
- 选型：runner 2.336.0 osx-arm64；SHA-256 `8e8839c49b7060b6b2154f4931f815df330c27f167d53ef2239ee3dfce28b079`。workFolder `~/gha/ypf1`。未用 `--no-default-labels`。
- 备份：无覆盖。新目录 `~/actions-runner/ypf-yunshu-1`、`~/gha/ypf1`。
- 回滚方式：
  ```bash
  ssh mac-mini 'kill -TERM $(pgrep -f /Users/konghai/actions-runner/ypf-yunshu-1/bin/Runner.Listener) $(pgrep -f /Users/konghai/actions-runner/ypf-yunshu-1/runsvc.sh)'
  TOKEN=$(gh api -X POST repos/konghai-friends-lab/YPF-YunShu/actions/runners/remove-token --jq .token)
  ssh mac-mini "cd /Users/konghai/actions-runner/ypf-yunshu-1 && ./config.sh remove --token '$TOKEN'"
  ```
- 变更时序：
  1. 下载并校验 runner tarball，解压到 `~/actions-runner/ypf-yunshu-1`。
  2. `config.sh` 注册到仓库 URL（不是 org）。
  3. 从 `mac-mini-mobile-1` 拷 `runsvc.sh`；写好 Daemon plist，但 `sudo cp` 到 `/Library/LaunchDaemons` 因要密码失败。
  4. `nohup ./runsvc.sh` 拉起 Listener。
  5. 安装脚本放到 `~/gha/scripts/install-ypf-yunshu-runner-daemon.sh`（仓库 `scripts/` 同步）。
- 验证：
  - Listener：`~/actions-runner/ypf-yunshu-1/bin/Runner.Listener run --startuptype service`，日志 `Listening for Jobs`。
  - `gh api repos/konghai-friends-lab/YPF-YunShu/actions/runners` → `ypf-yunshu-1` `online` `busy=false`，labels 含 `ypf-deploy`。
- 未做：未改 `YPF-YunShu` 的 `deploy.yml`（用户自己改）。未装 LaunchDaemon。未改 `mac-mini-runner-resume.sh`。
- 下一步（本机 sudo 一次即可常驻）：
  ```bash
  sudo /Users/konghai/gha/scripts/install-ypf-yunshu-runner-daemon.sh
  ```
  workflow 应写 `runs-on: [self-hosted, ypf-deploy]`。`deploy` 若仍 `needs: quality` 且 `quality` 走 `ubuntu-latest`，分钟用完时仍会被 quality 挡住。
- 后续：同日 17:30 已注销并改成组织级 `konghai-friends-lab-1`，上面的安装脚本路径不要再用。

## 2026-08-20 12:38 CST - Host github.com 改用工作号 k-cypresso 钥匙

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户要把默认 `git@github.com` 改成工作号，这样 Multica / git 走 SSH 也能看到 `cypresso-ai` 等仓。
- 影响：本机 `konghai` 所有 `git@github.com:...` 都认证为 **k-cypresso**。个人号改走别名 `github-personal`。`github-cypress` 仍指向工作号。未改 hon 的 SSH、未重启 daemon。
- 选型：`IdentityFile ~/.ssh/id_ed25519_k_cypresso_ai`，并加 `IdentitiesOnly yes`，避免 ssh-agent 里个人钥匙抢先被 GitHub 认成 `IAmKongHai`。
- 备份：`~/.ssh/config.bak.20260820`
- 回滚：`cp ~/.ssh/config.bak.20260820 ~/.ssh/config`
- 变更：
  - `Host github.com`：`id_ed25519` → `id_ed25519_k_cypresso_ai` + `IdentitiesOnly yes`
  - 新增 `Host github-personal`：原个人钥匙 `id_ed25519`
  - `Host github-cypress`：工作号钥匙，补 `IdentitiesOnly yes`
- 验证：
  - `ssh -T git@github.com` → `Hi k-cypresso!`
  - `ssh -T git@github-personal` → `Hi IAmKongHai!`
  - `ssh -T git@github-cypress` → `Hi k-cypresso!`
  - `git ls-remote git@github.com:cypresso-ai/icare-sit.git` → `refs/heads/main`
- 个人仓用法：`git@github-personal:IAmKongHai/<repo>.git`

## 2026-08-20 12:12 CST - mac-mini 的 gh 增加工作号 k-cypresso 并切为当前账号

- 服务器：`mac-mini`
- 操作人：`Grok`（用户用设备码在浏览器授权）
- 原因：用户要在 `gh` 里登录另一个 GitHub 账号，才能看见 `cypresso-ai` 等组织仓（此前 `IAmKongHai` 对 `icare-sit` 404）。
- 影响：
  - `gh` 现有两个 github.com 账号：**当前 `k-cypresso`**，`IAmKongHai` 仍在、未删。
  - `gh auth setup-git` 后 HTTPS 走 `gh` helper；`git ls-remote https://github.com/cypresso-ai/icare-sit.git` 成功。
  - 重启了 **konghai** 的 Multica profile daemon（pid 56550）。hon 的 daemon 未动（当时已是上午 10:13 另起的 pid 18984）。
  - `icare-sit` 已写入 repo cache（HEAD `main`）。
- 选型：设备码 `gh auth login --web --skip-ssh-key --git-protocol ssh --insecure-storage`。SSH 无钥匙串弹窗，token 落在 `~/.config/gh/hosts.yml`（已 `chmod 600`）。
- 备份：登录前只有 `IAmKongHai`；该账号 oauth 仍保留。
- 回滚：`gh auth switch --user IAmKongHai`。若要丢掉工作号：`gh auth logout --user k-cypresso`。
- 验证：
  - `gh api user` → `k-cypresso`
  - `gh api repos/cypresso-ai/icare-sit` → private、push
  - orgs：`cypressoai`、`caimiamiao`
  - HTTPS 预克隆 `icare-sit` 无新的 403；缓存目录出现 `github.com+cypresso-ai+icare-sit.git`
- 未改：`Host github.com` 仍用 `~/.ssh/id_ed25519`（`IAmKongHai`）。`git@github.com:cypresso-ai/icare-sit.git` 仍 404。工作号 SSH 走已有别名 `github-cypress`（`id_ed25519_k_cypresso_ai`）。
- 切换：
  ```bash
  gh auth switch --user k-cypresso
  gh auth switch --user IAmKongHai
  gh auth status
  ```

## 2026-08-19 16:35 CST - 停用 mac-mini-sonar-3/4，给 Multica 留并发

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：mac-mini 已作 konghai 的 Multica runtime（hon 的 daemon / `colima-multica` 也在）。4 路 sonar slot 高峰会和本地 agent 抢 10 核。用户确认先停 3/4。
- 影响：
  - `mac-mini-sonar` 独占重活（Coverage / 全量 branch Sonar / deploy quality-gate）最多两路并行。
  - 共享池少 2 个 mac-mini slot。当时 `lemon-imac-1/2` 已 offline，测试分片实际剩 `mac-mini`×2 + `umacbook-pro`×2。
  - **未**注销 GitHub runner，**未**动 `mac-mini-sonar-1/2` 与 `mac-mini-mobile-1`。
- 选型：`launchctl disable` + `bootout`，不 `config.sh remove`。回滚只需 enable + bootstrap / kickstart。
- 备份：`~/bin/mac-mini-runner-resume.sh.bak.20260819-1634`
- 回滚方式：
  ```bash
  sudo /bin/launchctl enable system/actions.runner.cypressoai.mac-mini-sonar-3
  sudo /bin/launchctl enable system/actions.runner.cypressoai.mac-mini-sonar-4
  sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/actions.runner.cypressoai.mac-mini-sonar-3.plist
  sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/actions.runner.cypressoai.mac-mini-sonar-4.plist
  # 或 sudo ~/bin/mac-mini-runner-resume.sh（恢复 3/4 前先把脚本里的 3/4 加回 labels）
  cp ~/bin/mac-mini-runner-resume.sh.bak.20260819-1634 ~/bin/mac-mini-runner-resume.sh
  ```
- 变更时序：
  1. 15:54 接到时 3/4 正在跑 `iCare-frontend-mas` PR #1594 `sonar.yml`，未杀 job。
  2. 16:34 五 slot 均 `busy=false`，无 `Runner.Worker`。
  3. `cp` 备份 resume 脚本。
  4. `sudo /bin/launchctl disable` 3/4（免密 sudo 只覆盖 `/bin/launchctl`）。
  5. `bootout` 卸掉 launchd job；Listener 成孤儿后 `kill -TERM`。
  6. resume 脚本改为只 kickstart 1/2 + mobile-1。
- 验证：
  - launchd：3/4 `disabled` 且 `print` 找不到 service；1/2/mobile `state=running`
  - 本机只剩 3 个 `Runner.Listener`（sonar-1/2、mobile-1）
  - GitHub：`mac-mini-sonar-3/4` `status=offline`；1/2 与 mobile-1 `online` `busy=false`
- 未做：未处理 `lemon-imac` offline；维护 cron 仍扫 `s3`/`s4` 工作目录（只清缓存，不拉起 runner）

## 2026-08-19 14:58 CST - 只读：Multica 预克隆 403 是 HTTPS 凭证，主仓已由 SSH 拉下

- 服务器：`mac-mini`
- 操作人：`Grok`（只读；未改 git credential、未停 daemon、未改 Multica 挂仓）
- 原因：用户问启动时 iCare 私有仓 403 / `-25308` 是什么意思、要不要修。
- 影响：无主机变更。
- 备份：无
- 回滚：无
- 事实：
  - runtime 仍 online（profile `konghai` pid 95167）。
  - HTTPS `git ls-remote https://github.com/cypressoai/iCare-backend.git` 在 SSH 会话里同样 403 + `-25308`。
  - SSH `git ls-remote git@github.com:cypressoai/iCare-backend.git` 成功；`ssh -T git@github.com` → `IAmKongHai`。
  - `gh` 登录 `IAmKongHai`，`iCare` admin、`iCare-backend` push；`cypresso-ai/icare-sit` 404。
  - `~/.git-credentials` 有两条 github.com：先 `x-access-token` 再 `IAmKongHai`。系统 helper 还有 Xcode `osxkeychain`。
  - 缓存目录里已经有 SSH 拉下来的包：`iCare` ~844M、`iCare-backend` ~179M、`iCare-frontend-mas` ~37M、`richer` ~15M。没有 `icare-sit`。
- 结论：403 是 HTTPS 用了错误/过期 token + 后台打不开钥匙串。不是「没写权限」。主仓任务可以从 cache worktree 干活。`icare-sit` 是另一个 org，当前 GitHub 用户看不见。
- 建议（未执行）：workspace 挂 SSH URL；GUI 里 `gh auth setup-git`；或给 `IAmKongHai` 开 `icare-sit` / 从 workspace 卸掉。
- 复盘：`docs/solutions/mac-mini/integration-issues/multica-daemon-https-repo-cache-403-2026-08-19.md`

## 2026-08-19 13:13 CST - 已把 mac-mini 配成 konghai 的 Multica runtime

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：浏览器 SSH 回调登录走不通；用户要求直接配置。
- 影响：
  - 用户 `k@cypresso.ai` 已登录 CLI。
  - 独立 profile `konghai` 的 daemon 在跑（pid 95167，0.4.29），**未停** hon 的 daemon（pid 6857）。
  - 在 hontest / iCare / cmm 各注册了 Claude / Codex / Grok 三个 runtime，显示名 `*(mac-mini)`，状态 online。
  - 写了用户级 LaunchAgent plist，SSH 会话里 `bootstrap gui/` 失败，**当前没有**交给 launchd；下次 GUI 登录后才会自动拉起。
- 选型：绕开浏览器回调。本机 self-host 开发验证码 `888888` 对 `k@cypresso.ai` 有效，签发一年期 PAT，再 `multica login --token`。默认 profile 会把 hon 的进程当成「已在跑」，所以用 `--profile konghai`。
- 备份：原先没有 konghai 的 daemon 状态；PAT 明文只在 `~/.multica/config.json` 与 profile 配置里（600）。
- 回滚：
  - `multica --profile konghai daemon stop`
  - 删 `~/Library/LaunchAgents/ai.multica.daemon.konghai.plist`
  - 在 Multica Settings 里吊销 PAT `mac-mini-konghai-runtime`
- 变更时序：
  1. `POST /auth/send-code` + `verify-code`（k@cypresso.ai / 888888）拿到会话。
  2. `POST /api/tokens` 建 PAT `mac-mini-konghai-runtime`（365 天）。
  3. `multica login --token` → 3 个 workspace。
  4. 默认 `daemon start` 被 hon pid 6857 挡住；改 `--profile konghai --daemon-id mac-mini-konghai` 成功。
  5. 写 LaunchAgent；`launchctl bootstrap gui/501` 从 SSH 返回 125。先 CLI 把 daemon 拉回。
- 验证：
  - `multica --profile konghai auth status` → k / k@cypresso.ai
  - `multica --profile konghai daemon status` → running，agents claude/codex/grok，3 workspaces
  - health `127.0.0.1:20252` → running / daemon_id=mac-mini-konghai
  - `runtime list` 有 `Claude/Codex/Grok (mac-mini)` online
  - hon pid 6857 仍在
- 未做 / 已知限制：
  - iCare 若干 repo 预克隆 403（`Write access to repository not granted` + keychain `-25308`）。runtime 已注册，碰到要写这些仓的任务可能失败。
  - LaunchAgent 尚未 load，重启后需 GUI 登录一次，或再执行 `multica --profile konghai daemon start ...`
- 复盘：`docs/solutions/mac-mini/integration-issues/multica-setup-ssh-login-localhost-3000-2026-08-19.md`

## 2026-08-19 13:02 CST - 只读：SSH 上 setup 只转了 55942，本机 localhost:3000 打不开登录页

- 服务器：`mac-mini`
- 操作人：`Grok`（只读；未杀 `setup`、未改 hon 的 daemon / compose）
- 原因：用户按 CLI 提示在本机 `ssh -L 55942:127.0.0.1:55942 konghai@mac-mini`，再打开 `http://localhost:3000/login?cli_callback=...`，登录不成。
- 影响：无主机变更。konghai 的 `setup` 仍在等认证。
- 备份：无
- 回滚：无
- 事实：
  - mac-mini `multica setup self-host` pid 94577 自 12:57 仍在；`127.0.0.1:55942` 由该进程监听。
  - 本机隧道 pid 45457 正常；`curl 127.0.0.1:55942/callback` → 400（缺参数，说明打到了 CLI）。
  - 本机 `127.0.0.1:3000` **没有进程**，`curl` connection refused。
  - Tailscale `http://100.108.64.126:3000/login` → 200 Multica 页面。
  - `/api/config`：`allow_signup=true`，`daemon_server_url` / `daemon_app_url` 都是 `http://100.108.64.126:3000`（前端地址，和昨天的 `--server-url` 坑同类）。
  - backend 对 Origin `http://100.108.64.126:3000` 回了 `Access-Control-Allow-Origin`，经 Tailscale 打开登录页可走 API。
- 结论：提示里的 `localhost:3000` 是 mac-mini 的前端，不是笔记本。只转 callback 不够。
- 正确做法（未代操作）：
  - 保留现有 `setup` 和 `-L 55942`，本机打开 `http://100.108.64.126:3000/login?cli_callback=http://localhost:55942/callback&cli_state=<当次 state>`
  - 或再 `-L 3000:127.0.0.1:3000` 后用 CLI 原 URL
  - 或 `multica login --token`
- 验证：本机 3000 refused、55942 隧道通、TS :3000 200。
- 复盘：`docs/solutions/mac-mini/integration-issues/multica-setup-ssh-login-localhost-3000-2026-08-19.md`

## 2026-08-19 12:54 CST - 只读：multica setup self-host 连不上 :3000 是 URL 指错

- 服务器：`mac-mini`
- 操作人：`Grok`（只读，未改守护进程、未跑 `setup`、未动 hon 的 compose）
- 原因：用户在 `mac-mini` 上执行 `multica setup self-host --server-url http://100.108.64.126:3000 --app-url http://100.108.64.126:3000`，报 *Server is not reachable*。
- 影响：无主机变更。konghai 的 `~/.multica` 仍不存在；hon 的 daemon 未动。
- 备份：无
- 回滚：无
- 事实：
  - `100.108.64.126` 就是本机 Tailscale IPv4，不是另一台控制面。
  - hon 的 `colima-multica` 自 Sat 15:00 在跑；宿主 `*:3000` / `*:8080` 由 lima SSH 转发（pid 55727）。
  - `GET :3000/` → 200 Next.js HTML；`GET :3000/health` → **404**。
  - `GET :8080/health` → 200 `{"status":"ok"}`；`GET :8080/healthz` → 200，db / migrations ok。经 Tailscale IP 同样通。
  - CLI `multica 0.4.29`；`setup self-host` 默认 backend `localhost:8080`、frontend `localhost:3000`，先探 `<server-url>/health`。
  - 已有 runtime：`hon` pid 6857，自 2026-08-18 17:02，`multica daemon start --foreground --server-url http://localhost:8080`，4 个 workspace，agents = grok / claude / codex。konghai 跑 `multica daemon status` 看到的就是这个进程。
  - konghai 的 PATH 上没有 `grok` / `claude` / `codex`。
- 结论：服务没挂。`--server-url` 指到了前端 3000，健康检查 404 被报成 unreachable。
- 正确做法（未执行，需用户在本机登录）：
  - 人已经在 mac-mini 上：`multica setup self-host`
  - 或 `--server-url http://100.108.64.126:8080 --app-url http://100.108.64.126:3000`（可能撞 `FRONTEND_ORIGIN=localhost:3000` 的 CORS）
  - SSH 无浏览器时用 `multica login --token`
  - 不要停 hon 的 daemon
- 验证：只读 curl / `multica setup self-host --help` / `ps` 如上。
- 复盘：`docs/solutions/mac-mini/integration-issues/multica-setup-self-host-server-url-frontend-2026-08-19.md`

## 2026-08-18 22:29 CST - 放入 preview iOS Firebase plist，供 GHA 本机构建拷入 IPA

- 服务器：`mac-mini`（`mac-mini-mobile-1`）
- 操作人：`Grok`
- 原因：CYP-1850。`eas build --local` 吃不到 EAS file secret，现有 TestFlight 包里没有 `GoogleService-Info.plist`，`getToken()` 静默失败，`appledevicetoken` 写不进库。
- 影响：只新增一份 runner 本机文件。未改 LaunchDaemon、未重启 runner、未改 workflow。下一包仍要等 mobile-app YAML 加 Stage 步才会打进 IPA。
- 选型：落盘 `~/.config/icare/GoogleService-Info.plist`（与 `testflight.json`、`AuthKey_*.p8` 同目录），权限 `600`，属主 `konghai`。
- 备份：目录里原先没有这份文件，无需覆盖备份。
- 回滚：删 `~/.config/icare/GoogleService-Info.plist`。
- 变更时序：
  1. 本机核 `p8/GoogleService-Info.plist`：`BUNDLE_ID=ph.com.toplogic.insularhealth.preview`，`PROJECT_ID=icare-dev-3c465`。
  2. `scp` 到 `konghai@mac-mini:~/.config/icare/GoogleService-Info.plist`。
  3. `chmod 600`。
- 验证：
  - `ls`：`-rw-------`，899 bytes，属主 `konghai`
  - runner 上再核：`BUNDLE_ID` / `PROJECT_ID` / `GOOGLE_APP_ID` 与 preview 一致
  - 同目录 `testflight.json`、`AuthKey_3VBD4W3ZKW.p8` 未动
- 未做：未提交 plist；未改 `eas-build-preview-local.yml`（B，mobile-app 仓另开 session）；未放 Android `google-services.json`

## 2026-08-18 19:20 CST - 只读：:9000 Sonar 容器已在跑，本机 Tailscale 曾停

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户打不开 `http://mac-mini:9000/`，以为容器没起来。
- 影响：未改 Colima、未启停容器、未改端口。本机 MacBook Air 的 Tailscale 当时是 `stopped`，已用 `tailscale up --reset --accept-routes` 重新连上（保留 accept-routes）。
- 备份：无
- 回滚：Air 上把 Tailscale 再关掉即可；mac-mini 无变更
- 事实：
  - Colima `default` Running（6 CPU / 12GiB），LaunchDaemon `com.konghai.colima` enabled
  - 7 个容器约 1 小时前随 17:54 `colima restart` 起来，均为 Up / sonarqube **healthy**
  - `http://127.0.0.1:9000/api/system/status` 与经 Tailscale `http://mac-mini:9000/api/system/status` 均为 `UP` / 26.3.0.120487
  - 首页 HTML 200、`<title>SonarQube</title>`
  - 宿主机 `:9000` 的 listener 是 Colima 用来做端口转发的 `ssh`，属正常
  - `docker context` 的 `default` 已指向 Colima socket；`desktop-linux` 仍在但 Docker Desktop 引擎不在跑。用 Desktop 窗口看会像「没容器」
- 验证：Air 连上 Tailscale 后 `curl http://mac-mini:9000/api/system/status` → 200 / `UP`（3ms 直连 `192.168.2.170`）

## 2026-08-18 17:58 CST - 收窄 Colima virtiofs 并清 EAS / DerivedData 残留

- 服务器：`mac-mini`
- 操作人：`Grok`（用户确认后执行）
- 原因：去掉 `fseventsd` 的 virtiofs 写放大，并清掉本机 EAS / Xcode 堆积。
- 影响：
  - Colima 重启约 16 秒。sonarqube / sub2api / richer 随 VM 拉起。
  - virtiofs 从整个 `/Users/konghai` + `/Users/hon` 收到 `/Users/konghai/stacks` + `/Users/hon/richer/deployments/grafana`。
  - 以后 Docker bind 只能落在这两棵树下。`~/gha`、`~/Library/Developer` 不再进 VM。
  - 删了 11 个旧 `iCare-*` DerivedData、9 个 `eas-build-local-nodejs` 工作树。
  - 日维护脚本会清隔夜 EAS 残留和过期旧 `iCare-*`（仍留最新一份）。
- 备份：
  - `~/.colima/default/colima.yaml.bak.20260818-1754`
  - `~/gha/scripts/gha-runner-maintenance.sh.bak.20260818-1758`
- 回滚：
  - `cp ~/.colima/default/colima.yaml.bak.20260818-1754 ~/.colima/default/colima.yaml && colima restart`
  - `cp ~/gha/scripts/gha-runner-maintenance.sh.bak.20260818-1758 ~/gha/scripts/gha-runner-maintenance.sh`
  - DerivedData / EAS 工作树已删，不能从备份恢复（可重新构建）
- 变更时序：
  1. 确认无 `Runner.Worker` / `xcodebuild` / `eas`。
  2. 改 `colima.yaml` mounts，`colima restart`（17:54:39–17:54:55）。
  3. lima.yaml 与 `findmnt -t virtiofs` 已是窄路径；7 个容器 healthy。
  4. Sonar `UP`，sub2api `/healthz` 200，Grafana `:3001/api/health` 200。
  5. EAS 残留 14G → 0；DerivedData 38G → 13G（保留最新 `iCare-bdvlqdiskctslaamtfzzdlrqzncb` 2.4G + ModuleCache + 旧 AcquiLangAI）。
  6. 维护脚本增加 `maybe_prune_eas_and_deriveddata`（有 builder 则跳过）。
- 验证：
  - virtiofs 仅 `stacks`、grafana、`vz-rosetta`
  - `docker exec` 仍能看见 sonarqube-web / sub2api-data / grafana provisioning
  - `fseventsd` 0.0%
- 未做：错开 mobile EAS 与 sonar `pnpm` 是调度约定，没改 workflow。
- 复盘：`docs/solutions/mac-mini/performance-issues/fseventsd-high-cpu-ci-write-storm-2026-08-18.md`

## 2026-08-18 17:50 CST - 只读：fseventsd 彻底方案（尚未执行）

- 服务器：`mac-mini`
- 操作人：`Grok`（只读，未改 Colima、未删残留）
- 原因：用户要「彻底解决」`fseventsd` CPU 和写放大。
- 影响：无主机变更。方案写进复盘文档。
- 备份：无
- 回滚：无
- 事实：
  - Lima virtiofs 实挂 `/Users/konghai`、`/Users/hon` 两个整家目录。
  - 容器真正 bind：`~/stacks/sub2api/{data,postgres_data,redis_data}`、`~/stacks/sonarqube/sonarqube-web`、`/Users/hon/richer/deployments/grafana/{dashboards,provisioning}`；其余是 VM 内 named volume。
  - 残留：`eas-build-local-nodejs` **14G**，DerivedData **38G**。
- 方案（需确认后再做）：
  1. `colima.yaml` `mounts` 收到 `~/stacks` + hon 的 grafana 目录，然后 `colima restart`（sonarqube / sub2api / richer 短暂停）
  2. 确认后清理 EAS 工作树和旧 DerivedData
  3. 本机 EAS 与 sonar `pnpm` 错开
- 做不到：Xcode/`pnpm` 写盘窗口里让 `fseventsd` 保持 0%。
- 验证：只读核对 mounts / bind / 残留体积。
- 复盘：`docs/solutions/mac-mini/performance-issues/fseventsd-high-cpu-ci-write-storm-2026-08-18.md`

## 2026-08-18 16:52 CST - preview-local 双端发布 tag `2026-08-18.03`

- 服务器：`mac-mini`（`mac-mini-mobile-1`）
- 操作人：`Grok`（`workflow_dispatch` `eas-build-preview-local.yml`，`--ref main`，`platform=all`，`source_branch=develop`）
- 原因：#192 合入 develop 后，需要把带 splash / 登录 / 抽屉 preview tag 的包发到 mas-icare 与 TestFlight。
- 影响：
  - Run [32117105413](https://github.com/cypressoai/iCare-mobile-app/actions/runs/32117105413) **success**（prepare 9s + Android 8m17s + iOS 8m46s）
  - `origin/release` fast-forward `0dff65e..d1ecd7e`（含 #192 merge `d1ecd7e`）
  - 新 annotated tag `2026-08-18.03`（`EXPO_PUBLIC_BUILD_TAG` 已烤进两端）
  - Android 覆盖公网 preview APK；iOS `buildNumber` 37 → 38，`eas submit --path` 进 TestFlight
- 备份：无主机配置变更
- 回滚：
  - Android：用上一包再跑 `deploy-icare-preview-apk.sh`
  - iOS：TestFlight 停用 build 38，改用上一包
- 验证：
  - Android：`https://mas-icare.cypress.sg/apk/icare-preview.apk` → **200**，`Content-Length: 175068045`，`Last-Modified: Tue, 18 Aug 2026 08:43:00 GMT`，远端 SHA256 `0cd9bb035cd077ad4ff62b1ef0424b6d7235b895740d9f9a128873ac2dd3c9d1`
  - iOS：ASC `6797895722`，submission `7685e6b1-3ca2-42f7-87d7-5f3b73f3d833`，日志 `Submitted your app to Apple App Store Connect`
  - 提交详情：https://expo.dev/accounts/cypressoai-builds-team/projects/icare-app/submissions/7685e6b1-3ca2-42f7-87d7-5f3b73f3d833
  - TestFlight：https://appstoreconnect.apple.com/apps/6797895722/testflight/ios

## 2026-08-18 16:45 CST - 只读补充：构建不在 Colima 里

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：确认 fseventsd 排查里 Colima 是构建环境还是旁路订阅者。
- 影响：无变更。
- 备份：无
- 回滚：无
- 事实：
  - `docker context` = `colima`。当时 `docker ps -a` 只有 7 个常驻服务（sub2api / richer / sonarqube 及其库），**没有** Expo / Android / eas-cli 构建容器，也没有对应镜像。
  - 16:00–16:20 `docker events` 为空，这段 APK + IPA 窗口没有容器创建/销毁。
  - iOS：`eas-build-local-nodejs/*/logs` 全部是宿主 `/Applications/Xcode.app/.../xcodebuild`，cwd 在 `/var/folders/.../T/eas-build-local-nodejs/<uuid>/build/ios`，产物进 `~/Library/Developer/Xcode/{DerivedData,Archives}`。Linux VM 跑不了 Xcode。
  - Android：`Local Android preview APK` 是宿主 `/bin/bash`，cwd `~/gha/m1/iCare-mobile-app/iCare-mobile-app`；本机有 `~/Library/Android/sdk`，日志里没有 docker/colima。
  - Sonar `pnpm` / Jest 同样在宿主 `~/gha/s1` `s2`。
- 判断：构建在 **macOS 宿主 + GitHub runner**。Colima 只是 virtiofs 挂了整个 `/Users/konghai`，会**旁路订阅**这些写盘，可能放大 `fseventsd`，但不是编译发生的地方。
- 验证：容器名单与 xcodebuild 日志如上。

## 2026-08-18 16:20 CST - 只读：fseventsd 高 CPU 是本机 EAS / CI 写盘洪峰

- 服务器：`mac-mini`
- 操作人：`Grok`（只读排查）
- 原因：用户看到 `fseventsd` 占 CPU 很高。
- 影响：无变更（未杀进程、未改 Spotlight / Colima / runner）。
- 备份：无
- 回滚：无
- 当时状态（16:16–16:20 CST）：
  - 接到时 load 已从 15 分钟均值 **6.6** 回落到 1 分钟 **2.2–2.9**；`fseventsd` pid 384 连续 8×2s 采样及随后 45s **全程 0.0%**，累计 CPU **31:57**（自 Sat 02:06 本次开机）。
  - Spotlight：`/` 与 Data 仍是 **Indexing and searching disabled**；`mds` 合计 ≈0。不是 7 月那次索引问题。
  - 刚结束的 job：
    - `mac-mini-mobile-1` **Preview APK (local)** 16:01–16:09，随后 **Preview IPA (local)** 16:09–16:17（`eas build --local` iOS，16:14 已产出 IPA，16:17 提交 TestFlight 结束）。
    - `mac-mini-sonar-1/2` 约 16:14–16:15 跑完 Jest / pnpm（`iCare-mobile-app`），job 结果 Failed。
  - 约 20 分钟内的写盘（mtime < 20 min）：
    - `~/Library/Developer/Xcode/DerivedData` **20849**（最新目录 `iCare-egxxkhxemfltdcadpzrmbddpfmfl`，大量 `ModuleCache.noindex` `.pcm`）
    - `/private/var/folders` **21215**（RN codegen，如 `rngesturehandler_codegen*`）
    - `~/gha` **12193**，其中 `s2` 约 **12083**（`iCare-mobile-app/node_modules`），`m1` 只剩收尾几十个文件
  - 放大器：Colima `default`（konghai，`virtiofs`）把 **`/Users/konghai` 整家目录** 挂进 VM；hon 的 `colima-multica` 另跑一套 VZ。CI / Xcode 的每次 create/unlink 都要由 `fseventsd` 扇出给 virtiofs。
- 判断：`fseventsd` 没坏，也不是 Spotlight。是 **本机 iOS EAS + sonar pnpm 同时解压/编译** 的文件系统事件风暴，job 一结束 CPU 立刻归零。活动监视器里看到的高占用对应 16:01–16:17 这段。
- 建议（未执行，需确认）：
  1. 不必杀 `fseventsd`，杀了 launchd 会拉起来，洪峰还在就会再飙。
  2. 若只想压峰值：把 Colima `mounts` 从整家目录收成 Docker 真正需要的路径，排除 `~/gha`、`~/Library/Developer`。这要 `colima restart`，会短暂停容器，须先确认。
  3. 避免 mobile 本机构建和 sonar/`pnpm` 抢同一窗口。
- 验证：job 结束后 45s 内 `fseventsd` TIME 未再增长（31:57.88 → 31:57.88）；无 Worker。
- 复盘：`docs/solutions/mac-mini/performance-issues/fseventsd-high-cpu-ci-write-storm-2026-08-18.md`

## 2026-08-18 14:44 CST - preview tag 改为当天日期加序号

- 服务器：无主机变更（mobile-app workflow）
- 操作人：`Grok`
- 原因：GitHub Tags 里 `preview-YYYYMMDD-HHMMSS` 看起来无序。
- 影响：
  - [PR #190](https://github.com/cypressoai/iCare-mobile-app/pull/190) 已合 main
  - 下次触发 preview-local 会打 `2026-08-18.01`、`.02`…（Asia/Shanghai 当天，扫已有同日前缀取最大 +1）
  - 旧 `preview-*` tag 保留不动
- 备份：无
- 回滚：revert #190
- 验证：下次 `workflow_dispatch` 看 prepare 输出的 tag

## 2026-08-18 14:20 CST - preview iOS 本机 IPA 已提交 TestFlight

- 服务器：`mac-mini`（`mac-mini-mobile-1`）
- 操作人：`Grok`
- 原因：WWDR G3/G4 + 跳过缺 plist 的 Crashlytics + unlink GNU rsync 后，export 终于过了。
- 影响：
  - Run [32105408291](https://github.com/cypressoai/iCare-mobile-app/actions/runs/32105408291) **success**
  - tag `preview-20260818-060458`（当时 develop/release 尖）
  - `eas submit --path` → App Store Connect `6797895722`
  - 提交详情：https://expo.dev/accounts/cypressoai-builds-team/projects/icare-app/submissions/d6bd7982-4c71-4bc8-9adc-baaf6f684d02
  - TestFlight：https://appstoreconnect.apple.com/apps/6797895722/testflight/ios
  - 本次未上传 Crashlytics dSYM（本机没有 `GoogleService-Info.plist`）
- 备份：无
- 回滚：无主机变更
- 验证：EAS Submit 打印 `Submitted your app to Apple App Store Connect`。Apple 还要处理 5–10 分钟，内部测试组随后可见。

## 2026-08-18 14:04 CST - unlink Homebrew rsync，重跑 iOS export

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：WWDR/Crashlytics 过了，archive 成功，`xcodebuild -exportArchive` 报 `Copy failed`（约 1 秒）。与 fastlane#29528 相同：Xcode 调 `/usr/bin/rsync -8aPhhE`，PATH 里的 GNU rsync 3.5 当 server 直接 usage error。
- 影响：
  - `brew unlink rsync`（公式仍在 Cellar，可 `brew link rsync` 恢复）
  - runner PATH 现在 `which rsync` = `/usr/bin/rsync`（openrsync）
  - mobile-app [PR #189](https://github.com/cypressoai/iCare-mobile-app/pull/189)
  - 已重派 [run 32105408291](https://github.com/cypressoai/iCare-mobile-app/actions/runs/32105408291)
- 备份：无
- 回滚：`brew link rsync`
- 验证：待该 run 的 export / TestFlight

## 2026-08-18 13:52 CST - 清掉残缺多输出和 Splashtop 虚拟声卡，audiomxd 回 0%

- 服务器：`mac-mini`
- 操作人：用户本机 `sudo /tmp/fix-mac-mini-audiomxd.sh --apply`；`Grok` 写脚本并复查
- 原因：`audiomxd` 自 2026-08-15 重启后一直约 72% CPU。ToDesk 已卸干净，但「多输出设备」仍挂着缺失的 BlackHole，默认输入是残留的 Splashtop 虚拟声卡。
- 影响：
  - 删掉 `MetaDevice.~:AMS2_StackedOutput:0`（BlackHole + 内置喇叭）
  - 删掉 `SplashtopRemoteSound.driver` 以及指向已不存在 App 的 LaunchDaemon / LaunchAgent
  - 重启 `coreaudiod` / `audiomxd`（约 13:51:47，短暂无声）
  - 默认输出仍是 LG UltraFine；本机无内置麦，现在没有默认输入设备
  - Docker / runner / 当时正在跑的 eas iOS 编译未动
- 备份：
  - `/Library/Preferences/Audio/com.apple.audio.SystemSettings.plist.bak.20260818-135146`
  - `/Library/Preferences/Audio/com.apple.audio.DeviceSettings.plist.bak.20260818-135146`
- 回滚：还原上述 bak 后再 `sudo killall coreaudiod audiomxd`；虚拟声卡需重装 Splashtop / BlackHole
- 变更时序：
  1. 远程无免密 sudo，图形密码框失败（与卸 ToDesk 相同）。脚本放到 `/tmp` 与 `~/bin/fix-mac-mini-audiomxd.sh`。
  2. 用户 13:51:46 `sudo --apply`：plist 去掉 AMS2 / Splashtop / BlackHole 首选；HAL 与 plist 删除成功；`streamer-daemon` 当时未 loaded，已 disable。
  3. 13:51:47 重启混音栈。
- 验证（13:52:31 及 13:52:43 再采）：
  - 新 `audiomxd` pid 11015，**0.0% CPU**，已运行约 1 分钟仍为 0
  - 设备列表只剩 LG ULTRAFINE（默认输出）和 Mac mini Speakers
  - 无 Splashtop、无「多输出设备」；HAL 只剩系统自带 `ParrotAudioPlugin.driver`
  - launchd 仅余 `"com.splashtop.streamer-daemon" => disabled` 空标签，无对应文件
- 复盘：`docs/solutions/mac-mini/performance-issues/audiomxd-high-cpu-orphan-multi-output-2026-08-18.md`
- 脚本：仓库 `scripts/fix-mac-mini-audiomxd.sh`

## 2026-08-18 13:45 CST - 排查 audiomxd 高 CPU：ToDesk 已卸干净，是残留多输出 + Splashtop 默认输入

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户看到 `audiomad` 占 CPU 很高，怀疑 2026-08-15 卸 ToDesk 虚拟声卡引起。
- 影响：只读排查，未杀进程、未改音频配置、未动 HAL / launchd。
- 备份：无
- 回滚：无变更
- 事实：
  - 进程名是系统自带的 `/usr/libexec/audiomxd`（Audio Mixer），不是第三方；活动监视器里容易看成 `audiomad`。
  - pid 570，`_audiomxd`，自 **Sat 02:06**（卸 ToDesk 后那次重启）一直跑，当前约 **72% CPU**，累计 CPU 约 3647 分钟，有一条线程长期 `R`。
  - ToDesk 本身干净：无 `ToDeskOutputDriver.driver`、无 ToDesk 进程、当前 `SystemSettings.plist` 已无 ToDesk 键。备份 `SystemSettings.plist.bak.20260815` 里还能看到当时删掉的 `ToDeskOutputDriver2ch_UID`。
  - 仍挂着的第三方 HAL：`SplashtopRemoteSound.driver`（App 已不在 `/Applications`，plist 还在）。`ParrotAudioPlugin.driver` 是 Apple 系统插件，可忽略。
  - 当前设备：默认输出 **LG ULTRAFINE**（48 kHz）；默认输入 **Splashtop Remote Sound**（虚拟、**44.1 kHz**）；另有「多输出设备」。Mac mini 没有内置麦克风。
  - 「多输出设备」`~:AMS2_StackedOutput:0` 的子设备仍是 **BlackHole 2ch**（HAL 已不存在）+ **Mac mini Speakers**。首选输入列表也还写着 `BlackHole2ch_UID`。
- 判断：ToDesk 残留不是直接原因。卸载 + 重启让 Core Audio 重建设备图，**缺了 BlackHole 的多输出设备** 和 **只剩 Splashtop 当默认输入** 更像让 `audiomxd` 空转的原因。时序上是卸 ToDesk 后暴露的，不是 ToDesk 驱动没卸干净。
- 建议（未执行，需确认）：
  1. 声音设置里把输入从 Splashtop 改掉（可先试 LG / 外接麦；本机无内置麦）。
  2.「音频 MIDI 设置」里删掉仍挂着 BlackHole 的「多输出设备」。
  3. 再 `sudo killall audiomxd coreaudiod` 让混音栈重建（会短暂无声，需确认）。
  4. 若仍高：按 ToDesk 同类方式清 Splashtop HAL + LaunchAgent/Daemon。
- 验证：只读结论如上；CPU 未处理。

## 2026-08-18 13:33 CST - WWDR 已过；Crashlytics 缺 plist，已跳过上传再打

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：run [32102698930](https://github.com/cypressoai/iCare-mobile-app/actions/runs/32102698930) 已签过 `React` / `hermes`，死在 `[RNFB] Crashlytics Configuration`：`Could not get GOOGLE_APP_ID`。`eas build --local` 拿不到 EAS file secret。
- 影响：
  - mobile-app [PR #186](https://github.com/cypressoai/iCare-mobile-app/pull/186)：无 `GoogleService-Info.plist` 时 Crashlytics 上传改为 no-op
  - 日后把 plist 放到 `~/.config/icare/GoogleService-Info.plist` 会恢复上传
  - 已重派 [run 32103352964](https://github.com/cypressoai/iCare-mobile-app/actions/runs/32103352964)
- 备份：无
- 回滚：revert #186
- 验证：待该 run

## 2026-08-18 13:25 CST - 恢复被删的 oh-my-zsh plugins，消除 SSH 登录警告

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：`ssh mac-mini` 每次都先刷 Powerlevel10k instant prompt 警告，底下是 `[oh-my-zsh] plugin 'git' not found`
- 影响：
  - 只恢复 `~/.oh-my-zsh/plugins/`（工作树里 886 个已跟踪文件被删，git HEAD 仍在）
  - **未**改 `~/.zshrc`、**未**关 p10k instant prompt、**未**动 runner / LaunchAgent
  - 自定义插件（`zsh-autosuggestions`、`zsh-syntax-highlighting`）和 `custom/themes/powerlevel10k` 本来就在
- 备份：无需；`~/.oh-my-zsh` 是 git 仓库，`git restore plugins` 可逆
- 回滚：`cd ~/.oh-my-zsh && git checkout -- plugins` 的反向是再删该目录（一般不必）
- 变更时序：
  1. 确认 `~/.zshrc` 的 `plugins=(git zsh-autosuggestions zsh-syntax-highlighting)`
  2. `ls ~/.oh-my-zsh/plugins` → 目录不存在；`git status` 全是 `D plugins/...`
  3. `cd ~/.oh-my-zsh && git restore plugins`
  4. 交互式 `zsh -ic` 验证
- 验证：
  - `plugins=git zsh-autosuggestions zsh-syntax-highlighting`
  - `gst='git status'`
  - `ssh -tt mac-mini` 不再出现 `plugin 'git' not found` 或 p10k instant prompt 警告
- 未定位：谁在约 2026-08-15 00:35 删掉了该目录（与 OMZ `git pull --rebase` 时间接近，但工作树删除未进 commit）

## 2026-08-18 13:23 CST - System WWDR G3/G4 已装，重跑 iOS TestFlight

- 服务器：`mac-mini`
- 操作人：用户本机 `bash ~/bin/install-apple-wwdr-system.sh`；`Grok` 重派 workflow
- 原因：上一枪 IPA 因 System WWDR 过期 codesign 失败。
- 影响：
  - System.keychain 新增 WWDR G3（至 2030-02-20）、G4（至 2030-12-10）；2023 过期那张仍在，不删
  - **未**重启 runner（Listener 仍为 pid 64116）
  - 已触发 [run 32102698930](https://github.com/cypressoai/iCare-mobile-app/actions/runs/32102698930) `platform=ios`
- 备份：无
- 回滚：钥匙串里删 G3/G4（一般不必）
- 验证：`security find-certificate` 已能列出 G3/G4 的 Not After 2030。IPA / TestFlight 结果待该 run。

## 2026-08-18 13:12 CST - iOS 死在 codesign 证书链；等本机 sudo 装 WWDR

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：run [32101057448](https://github.com/cypressoai/iCare-mobile-app/actions/runs/32101057448) IPA 再次失败。ASC / rsync / sandbox 都过了。Xcode 日志：
  - `Code Signing …/React.framework` with `iPhone Distribution: XIANLIANG XIE (2ZSNV9MWK6)`
  - `unable to build chain to self-signed root`
  - `errSecInternalComponent`
- 影响：
  - System.keychain 里的 WWDR 只到 **2023-02-07** 已过期
  - LaunchDaemon 不能读登录钥匙串（`User interaction is not allowed`），所以登录钥匙串里较新的 WWDR 用不上
  - 已放脚本 `~/bin/install-apple-wwdr-system.sh`（源：仓库 `scripts/install-apple-wwdr-system.sh`）
  - 清掉这次 `EAS_LOCAL_BUILD_SKIP_CLEANUP` 留下的 eas-build 目录
  - **未**改 runner、未装 System 证书（`sudo -n` 失败）
- 备份：无
- 回滚：无主机证书变更
- 验证：等用户在 mac-mini 本机执行 `bash ~/bin/install-apple-wwdr-system.sh` 后再打 iOS
- 下一步：sudo 装 G3/G4 后重跑 `platform=ios` → `eas submit` TestFlight

## 2026-08-18 12:50 CST - 接入 ASC Key、GNU rsync，准备 TestFlight

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：走通 preview iOS → App Store Connect / TestFlight。
- 影响：
  - 本机与 mac-mini 写入 `~/.config/icare/testflight.json` + `AuthKey_3VBD4W3ZKW.p8`（600）。**未**入库、**未**写 GitHub secret
  - `brew install rsync`（3.5.0），runner PATH 里 `/opt/homebrew/bin` 已在 `/usr/bin` 前，压过 Tahoe openrsync
  - **未**改 runner plist、未重启 LaunchDaemon
  - mobile-app [PR #184](https://github.com/cypressoai/iCare-mobile-app/pull/184)：IPA 成功后 `eas submit --path`
- 备份：无（新增本机文件）
- 回滚：删 `~/.config/icare/{testflight.json,AuthKey_3VBD4W3ZKW.p8}`；`brew uninstall rsync`
- 验证：
  - `asc-status.mjs --auth-only` → `auth=VALID`，app=`iCare Preview` / `ph.com.toplogic.insularhealth.preview`
  - `which rsync`（runner PATH）→ `/opt/homebrew/bin/rsync` 3.5.0
- 下一步：触发 `platform=ios`

## 2026-08-18 12:27 CST - preview-local Android 首次从 develop tag 打通并上传

- 服务器：`mac-mini`（`mac-mini-mobile-1`）
- 操作人：`Grok`（用户手动触发）；runner 自动上传
- 原因：验证 [PR #183](https://github.com/cypressoai/iCare-mobile-app/pull/183) 的 snapshot 流程。
- 影响：只跑 `platform=android`。未改 runner。线上 APK 见 `docs/operations/dev-cypresso.md` 同日条目。
- 备份：无
- 回滚：无主机变更
- 验证：
  - Run https://github.com/cypressoai/iCare-mobile-app/actions/runs/32098462354 **success**
  - tag `preview-20260818-041534` = `3c3cefe`（当时 develop / release 尖）
  - APK 171686561 bytes，已发布到 `https://mas-icare.cypress.sg/apk/icare-preview.apk`
- 未做：iOS

## 2026-08-18 11:30 CST - preview-local 改为 develop → release → tag；iOS 仍失败但原因变了

- 服务器：`mac-mini`（只读核对 DerivedData）；workflow 改在 `iCare-mobile-app`
- 操作人：`Grok`
- 原因：
  - 手动触发一直选 `main`，打出来的是 main，业务改动在 develop
  - run [32094346074](https://github.com/cypressoai/iCare-mobile-app/actions/runs/32094346074) 再次失败
- 影响：
  - **未**改 runner、未重启、未再下 Xcode 组件
  - `eas-build-preview-local.yml` 已合 main（[PR #183](https://github.com/cypressoai/iCare-mobile-app/pull/183)）：`prepare` 把 `develop` 合进 `release`，打 `preview-YYYYMMDD-HHMMSS` tag，Android/iOS 从该 tag 构建
  - `new-github-release.yml` 只响应 `v*`，避免 preview tag 误开 GitHub Release 并触发 EAS 云构建
  - 下一次从 Actions 选 **main** 触发即可（用新 YAML）；包内容来自刚打的 tag
- 备份：无主机变更
- 回滚：revert #183
- 验证 / 结论：
  - 上次缺的 `iPhoneOS26.5.sdk` 这次在；编译、链接已过
  - 死在 `[CP] Embed Pods Frameworks`（`PhaseScriptExecution`，gym exit 65）。DerivedData 里对应 `.xcactivitylog` 是 0 字节，脚本 stdout 没留下
  - `expo-doctor` 有 4 个 patch 落后（`expo-constants` 等），不阻断构建
  - iOS job 已加 `EAS_LOCAL_BUILD_SKIP_CLEANUP=1` 和失败 dump，方便下次看
- 下一步：再触发一次 `platform=android` 验证 snapshot 流程；iOS Embed Frameworks 另修

## 2026-08-18 11:08 CST - iOS 26.5 Simulator 已装完，重跑 IPA

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：`xcodebuild -downloadPlatform iOS` 下的是 **Simulator 26.5 (23F77, 8.52GB)**，exit 0。DeviceSupport 仍只有 15–16.x。已重派 `platform=ios`（run 32094346074）看 generic device destination 是否因此能过。
- 影响：磁盘约 +8.5GB 模拟器运行时。未改 runner。
- 回滚：Xcode Settings → Components 可删该 Simulator。
- 验证：`simctl list runtimes` 现有 iOS 26.5 Available。IPA 结果待该 run。

## 2026-08-18 11:00 CST - iOS local 失败因缺 iOS 26.5 设备平台；已开始下载

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：U5 第一次 IPA 失败（run 32091626082）。签名已过，gym 报 `iOS 26.5 is not installed`。`-showsdks` 有 SDK，DeviceSupport 只到 16.4。
- 影响：正在跑 `xcodebuild -downloadPlatform iOS`。已把上传脚本放到 `~/bin/deploy-icare-preview-apk.sh`。未改 runner、未重启。
- 备份：无。
- 回滚：停 download 进程；可删 `~/bin/deploy-icare-preview-apk.sh`。
- 验证：`ssh mac-mini ssh dev-cypresso` 已通。平台下载尚未完成。
- 下一步：下载完重跑 `platform=ios`。Android 下次会自动上传（mobile-app PR #182 已合 main）。

## 2026-08-18 10:45 CST - 修正 mac-mini 上 ssh dev-cypresso 的错误 IP

- 服务器：`mac-mini`（本机 SSH 别名，目标为 `dev-cypresso`）
- 操作人：`Grok`（用户从 mac-mini 登录 dev-cypresso 时发现 HostName 配错）
- 原因：`Host dev-cypresso` 写成了 `32.192.91.222`（占位/旧地址），正确公网 IP 是 `32.192.186.193`。
- 影响：
  - 只改 `~/.ssh/config` 这一行 HostName
  - IdentityFile 仍为 `~/.ssh/cypresso.ai.pem`（远端 `authorized_keys` 仍保留该 PEM 公钥）
  - **未**改远端、未改防火墙、未重启任何服务
- 备份：`~/.ssh/config.bak.20260818-dev-cypresso-ip`
- 回滚方式：
  ```bash
  ssh mac-mini 'cp ~/.ssh/config.bak.20260818-dev-cypresso-ip ~/.ssh/config && ssh -O exit dev-cypresso || true'
  ```
- 变更时序：
  1. 读出 mac-mini 上 `Host dev-cypresso` 确认错误 IP。
  2. 备份 config 后将 HostName 改为 `32.192.186.193`。
  3. 从 mac-mini 用别名实测登录。
- 验证：
  - `ssh mac-mini 'ssh -o ControlMaster=no -o BatchMode=yes dev-cypresso "whoami; hostname"'` → `ec2-user` / `ip-172-31-42-99.ec2.internal`
  - 首次连接已把 `32.192.186.193` ED25519 指纹写入 mac-mini `known_hosts`

## 2026-08-18 09:55 CST - 第一包 preview APK 已在 mac-mini-mobile-1 本机打出

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：`EXPO_TOKEN` 已写入 `iCare-mobile-app` 仓库 secret；执行计划 U4。
- 影响：只触发 GitHub Actions `eas build --local`（Android preview）。未改 runner、未改 crontab、未动 sonar 槽。
- 备份：无。
- 回滚：无主机变更。
- 验证：
  - Run https://github.com/cypressoai/iCare-mobile-app/actions/runs/32088691619 **success**
  - `eas whoami`、本地 APK、`unzip -t`、artifact 上传均成功
  - 首次 `pnpm/action-setup` ENOTEMPTY 已用本机 node/pnpm 绕过（PR #177 合入 `main`）
- 未做：iOS local IPA（U5）；`develop` 上 PR #175 仍开着（CI Quality 被 lemon 上无关的 pnpm 残留挡住）

## 2026-08-17 16:22 CST - mac-mini-mobile-1 Daemon 已上线；Xcode first launch 完成

- 服务器：`mac-mini`
- 操作人：用户本机 `sudo ~/Downloads/install-mac-mini-mobile-daemon.sh`；`Grok` 核对并补 `.env` 加载、crontab
- 原因：用户确认后执行 first launch + LaunchDaemon。
- 影响：
  - `xcodebuild -checkFirstLaunchStatus` = **0**
  - `system/actions.runner.cypressoai.mac-mini-mobile-1` running；Listener pid 新进程在听 job
  - GitHub：`mac-mini-mobile-1` **online**，labels 未变（仅 `mobile-preview-ci` 池）
  - `runsvc.sh` 现在会 `source .env`（备份 `runsvc.sh.bak.20260817`）
  - crontab 日/周维护 `WORK_DIRS` 增加 `~/gha/m1`（备份 `~/Library/Logs/crontab.bak.20260817`）
- 回滚：`sudo launchctl bootout system/actions.runner.cypressoai.mac-mini-mobile-1` 并删对应 plist；crontab 拷回 bak。
- 验证：stdout `Listening for Jobs`；`gh api` status=online。未打 APK（仓库尚无 `EXPO_TOKEN` secret）。

## 2026-08-17 16:25 CST - 已注册 mac-mini-mobile-1，等本机 sudo 装 Daemon

- 服务器：`mac-mini`
- 操作人：`Grok`（注册 + 写文件）；LaunchDaemon / Xcode first launch 待本机 `sudo`
- 原因：计划 U2。GitHub 注册不需要 sudo；`launchctl bootstrap system` 和 `xcodebuild -runFirstLaunch` 需要管理员密码，SSH `sudo -n` 失败。
- 影响：
  - 新 runner `mac-mini-mobile-1`（agentId 38）已在 org Default 组，当前 **offline**。
  - labels：`self-hosted, macos, arm64, macos-arm64, mac-mini, mobile-preview-ci`。无质量门标签。
  - workFolder：`~/gha/m1`。程序目录：`~/actions-runner/mac-mini-mobile-1`。
  - `.env` 含 `PNPM_STORE_PATH` / `ANDROID_HOME` / `JAVA_HOME` / `LANG`。无 `EXPO_TOKEN`。
  - `~/bin/mac-mini-runner-resume.sh` 已包含该槽。
- 备份：`~/bin/mac-mini-runner-resume.sh.bak.20260817`
- 回滚：`gh api` 取 remove-token 后在该目录 `./config.sh remove`；删目录与 `~/gha/m1`。
- 本机待跑（要密码）：`sudo ~/Downloads/install-mac-mini-mobile-daemon.sh`（脚本会 first launch + 装 Daemon）。
- 验证：`gh api` 已见 runner；status=offline，符合 Daemon 未装。

## 2026-08-17 16:15 CST - 为 mobile-preview 槽装上 Homebrew node@22 + pnpm

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：执行 `docs/plans/2026-08-17-001-ops-mac-mini-mobile-preview-slot-plan.md` U1。Daemon `.path` 不能 `eval fnm`；本机 `fnm` 也没有 Node 版本。
- 选型：Homebrew keg-only `node@22` 22.23.2，不 `brew link --overwrite`（会撞已有 `/opt/homebrew/lib/node_modules/npm`）。pnpm 用 corepack 钉 `10.12.3`。
- 影响：只新增 Cellar 公式与 corepack shim。未改 4 个 sonar runner、未改 LaunchDaemon、未跑 Xcode first launch。
- 备份：无。
- 回滚：`brew uninstall node@22`（依赖瓶可留着）。
- 验证（显式 PATH，无 fnm）：
  - `node -v` = `v22.23.2`（`/opt/homebrew/opt/node@22/bin/node`）
  - `pnpm -v` = `10.12.3`
  - `java -version` = OpenJDK 17.0.17
  - `adb version` = 1.0.41
  - `xcodebuild -checkFirstLaunchStatus` 仍为 **69**（U1 iOS 半截未做，须本机确认后再 `runFirstLaunch`）
- 计划：`docs/plans/2026-08-17-001-ops-mac-mini-mobile-preview-slot-plan.md`

## 2026-08-17 15:20 CST - 只读复核：专用 slot 同时打 iOS + Android

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户确认用专用 slot，并问双端是否都能放这台机器。
- 影响：只读。未装软件、未注册新 runner、未接受 Xcode first launch、未触发构建。
- 备份：无。
- 回滚：无变更。
- 验证：
  - Xcode 26.6 / iOS SDK 26.5 / CocoaPods 1.16.2 可用；`xcodebuild -checkFirstLaunchStatus` 退出码 **69**（首次启动组件未跑完）。
  - login keychain 在 SSH 非交互下 `User interaction is not allowed`；本机只有个人 Development 身份 `Apple Development: XIANLIANG XIE (2329U9YKK8)`，没有团队 `2ZSNV9MWK6` 的 Distribution 证书。
  - `~/.expo/state.json` 仅有 `uuid`，未登录 EAS；无 `~/.config/icare/testflight.json`。
  - 对照 eas-cli 源码：`findIdentitiesByTeamId` 仍带 `security find-identity -v`。macOS 26 Tahoe 上这条会误判「Distribution 证书没导入」（eas-cli#3678），PR #3679 未进 main。
- 结论：一台专用 slot **可以串行打双端**。Android 补 Node/JDK 即可；iOS 必须先 `xcodebuild -runFirstLaunch`、用 `EXPO_TOKEN` 拉 EAS 管理的 Distribution 证书，并钉带 Tahoe 修复的 eas-cli（或等价去掉 `-v`）。不要双端并行，也不要把 `mobile-build` 贴到现有 sonar slot。

## 2026-08-17 15:05 CST - 只读盘点：能否在本机打 iCare 会员端 App

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：开发反馈 EAS 云构建慢，评估能否把 `iCare-mobile-app` 的 Android / iOS 出包挪到本机。
- 影响：只读。未装软件、未改 runner、未改 Docker、未触发 EAS。
- 备份：无。
- 回滚：无变更。
- 验证（SSH 只读）：
  - 主机：Apple M4 / 10 核 / 32GB / macOS 26.5.2；数据盘 1.8T 已用 62%、剩余约 716GB。
  - 已有：Xcode 26.6、Android SDK（platforms 25–36、build-tools 35/36、NDK 27.1、adb）、Homebrew OpenJDK 17.0.17、CocoaPods 1.16.2、fastlane、fnm。
  - 缺：登录 PATH 无 `node` / `pnpm` / `eas`（`fnm list` 仅 `system`，`/opt/homebrew/bin/node` 不存在）；`ANDROID_HOME` / `JAVA_HOME` 未导出；`/usr/bin/java` 找不到 runtime。
  - 负载：4 个 `mac-mini-sonar-*` LaunchDaemon 在线；当时 `mac-mini-sonar-1` 有 `Runner.Worker`；Docker/Colima 在跑 SonarQube、Sub2API、Grafana 及对应 Postgres/Redis。内存 compressor 约 10GB 页，不适合再叠一层和 CI 并发的原生编译。
- 结论：Android preview 本机构建硬件条件基本具备，但要先装 Node 22 + pnpm + eas-cli，并导出 JDK/SDK；不要复用现有 4 个 sonar slot。iOS 有 Xcode，但还缺签名链路，且 Xcode 26 对 `expo run:ios` 有已知坑。

## 2026-08-16 17:52 CST - Sub2API 镜像补丁：Grok 工具集不再触发 Gemini 内置搜索 400

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：Grok Build 走 `/antigravity/v1/messages` 时带 `web_search` + 其它 function，Sub2API 把搜索转成 Gemini 内置 `googleSearch`，上游 400：`Please enable tool_config.include_server_side_tool_invocations`。该开关在当前 daily/v1internal 上无效。
- 选型：有客户端 function 时不再发内置搜索，把 `web_search` 当普通 function 回给客户端执行。只重建 `sub2api`。
- 镜像：`sub2api:pr5640-3.7-ssti`（`0.1.177-pr5640-ssti`）。旧镜像 `sub2api:pr5640-3.7` 仍在。
- 备份：`~/stacks/sub2api/docker-compose.yml.bak.ssti.20260816`
- 回滚：compose `image:` 改回 `sub2api:pr5640-3.7`，`docker compose up -d sub2api`
- 验证：`list_dir` + `web_search_20250305` 混用 `POST /antigravity/v1/messages` → **200**，回复 `HI`。无工具短请求仍 200。Sonar / Grafana / Postgres / Redis 未动。

## 2026-08-16 17:16 CST - 账号 3 因 Google 国家=中国被拒；账号 4 已通

- 服务器：`mac-mini`
- 操作人：用户排查；`Grok` 只读核对后记录
- 原因：`hxf.xxk@gmail.com`（账号 3）走完验证仍 403。用户确认该 Google 账号国家设为中国，上游不允许调用。另加 `geogle7733@gmail.com`（账号 4）。
- 影响：未改镜像、分组、Key。账号 3 仍 `error` / 不可调度，等改国家后再恢复。
- 验证：
  - 账号 4：`antigravity` / `active` / `schedulable`，进分组 5。
  - `17:16:18` `POST /v1/chat/completions` `gemini-3.7-flash-tiered` 走账号 4 → **200**。
  - 账号 1 调度已重新打开；账号 3 仍是 `Validation required (403)`。
- 结论：Antigravity 订阅号的 Google 账号国家不能是中国。403 先看国家/地区，不要先怀疑 Project ID。改国家后再对账号 3 点「恢复状态」并打开调度。

## 2026-08-16 16:56 CST - 新 Antigravity 号 exhausted：403 验证 + 旧号被关掉

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户新加 `hxf.xxk@gmail.com` 后再调 `/v1`，客户端报 `All available accounts exhausted`，怀疑是没填 GCP Project ID。
- 影响：只读。未改账号、分组、镜像。
- 验证：
  - 16:45:24 后台把账号 1（`konghai007` Antigravity）`schedulable` 关掉；16:37:41 关掉账号 2。
  - 16:45:55 请求只剩账号 3，上游 **403** `Validation required`（Google 要验证该账号），网关把账号 3 标 `error` / 不可调度。
  - 分组 5 里两个 Antigravity 号此后都不可调度，后续再打就会 exhausted。
  - 账号 3 的 `project_id` 实际已有自动值 `celestial-monument-psf6z`；缺的是 `antigravity_project_id`。源码只在 `project_id` 为空时才要求填，这次失败文案不是缺项目。
- 结论：先让 `hxf.xxk` 在浏览器走完 Google 验证 / 打开过 Antigravity，再清 error 并打开调度。要立刻恢复调用，把账号 1 的调度重新打开即可。

## 2026-08-16 16:30 CST - 自打 PR #5640 镜像换上，3.7 Flash 已通

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：官方 `weishaw/sub2api:0.1.177` 没有 Gemini 3.7 变体目录；用户要求用 PR `#5640`（`feat/gemini-3.7` @ `f2a7aeb`）自打镜像换上。
- 选型 / 影响：
  - 源码：`~/src/sub2api-pr5640`（仅该 PR 分支）。
  - 镜像：`sub2api:pr5640-3.7`（`linux/arm64`），版本字符串 `0.1.177-pr5640`。
  - compose `image:` 从 `weishaw/sub2api:0.1.177` 改为本地 `sub2api:pr5640-3.7`。
  - 只重建 `sub2api`。Postgres / Redis / Sonar / richer 未动。
  - 仍保留 `GATEWAY_ANTIGRAVITY_FORWARD_BASE_URL=daily`。
- 备份：`~/stacks/sub2api/docker-compose.yml.bak.pr5640`（换镜像前）、`docker-compose.yml.bak.20260816`。
- 回滚：把 compose `image:` 改回 `weishaw/sub2api:0.1.177`（或拷回 bak），`docker compose up -d sub2api`。数据卷不动。
- 验证：
  - 容器 healthy；`/app/sub2api -version` = `Sub2API 0.1.177-pr5640 (commit: f2a7aeb)`；`GET /health` ok。
  - `/v1/models` 已出现 `gemini-3.7-flash` 及 `-high/-medium/-low/-tiered`。
  - Key `konghai` 仍绑分组 5 `antigravity`。
  - `POST /v1/chat/completions`：
    - `gemini-2.5-flash` → **200**（回归未坏）
    - `gemini-3.7-flash-tiered` → **200**，回复 `OK`（订阅额度，走 Antigravity daily）
    - `gemini-3.7-flash` / `-high` / `-medium` / `-low` → 上游 **404** `Requested entity was not found`
- 结论：客户端把 `model` 改成 **`gemini-3.7-flash-tiered`** 即可。high/medium/low 在当前 daily 端点不存在，不是网关目录问题。计费表尚未收录该模型（日志 `pricing not found`），不影响调用。

## 2026-08-16 16:22 CST - 加上 Antigravity daily 端点后 2.5 通、3.7 仍 404

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户要试 `GATEWAY_ANTIGRAVITY_FORWARD_BASE_URL=daily`，看 3.7 Flash 是否因此可用。
- 影响：
  - `.env` / compose 增加该变量，值为 `daily`。
  - 只重建 `sub2api` 容器。Postgres / Redis / Sonar / richer 未动。
- 备份：`~/stacks/sub2api/docker-compose.yml.bak.20260816`、`.env.bak.20260816`（600）。
- 回滚：把两个 bak 拷回，`docker compose up -d sub2api`。
- 验证：
  - 容器内 `GATEWAY_ANTIGRAVITY_FORWARD_BASE_URL=daily`；healthy。
  - Key 已在分组 `antigravity`。`gemini-2.5-flash` 在 `/v1/chat/completions` 和 `/antigravity/v1beta/...` 均为 **200**。
  - `gemini-3.7-flash` 上游 **404**；`-high/-medium` 被 0.1.177 目录拒掉（404/503）。
- 结论：daily + 美国出口已生效。3.7 要等合入 PR `#5640` 的版本，或自打该 PR。

## 2026-08-16 16:10 CST - 结论：3.7 Flash 不在 Code Assist，要走 Antigravity 变体名

- 服务器：`mac-mini`
- 操作人：`Grok`（资料 + 只读探测）
- 原因：用户目标是 `gemini-3.7-flash`，怀疑 Cloud AI Companion 没开这个模型。
- 影响：只读。未改账号映射、分组、镜像。
- 验证：
  - Gemini `google_one` 号实测只有 2.5 Flash/Pro；3.7-flash 上游 404。
  - Antigravity 账号映射里已有 `gemini-3.7-flash`→同名；Key 当前绑在 Gemini 组，打 `/antigravity/v1beta` 为 503（组里没有 Antigravity 号）。
- 资料：Sub2API PR `#5640`（未合入 0.1.177）写明 Antigravity 上 3.7 要用 `gemini-3.7-flash-high/medium/low/tiered`，基础名 404；建议 `GATEWAY_ANTIGRAVITY_FORWARD_BASE_URL=daily` + 美国出口。

## 2026-08-16 16:00 CST - 实测 Gemini google_one 账号仅 2.5 Flash / 2.5 Pro 可用

- 服务器：`mac-mini`
- 操作人：`Grok`（只读探测）
- 原因：用户问该 Gemini 账号能用哪些模型；`gemini-3.7-flash` 报 Resource not found。
- 影响：只读。对 Key 发了十余次短请求。
- 备份：无。
- 回滚：无变更。
- 验证：`POST /v1/chat/completions` 仅 `gemini-2.5-flash`、`gemini-2.5-pro` 返回 200；`gemini-2.0-flash`、全部 Gemini 3.x（含 3.7-flash）及别名均为上游 404。
- 结论：`/v1/models` 列出的是 Sub2API 默认目录，不是 Code Assist / Google AI Pro 这条线上真实可用的模型。

## 2026-08-16 15:52 CST - 启用 Cloud AI Companion 后 Gemini 调用已通

- 服务器：`mac-mini`
- 操作人：`Grok`（清账号残留 error 后实测）
- 原因：用户已启用 `cloudaicompanion.googleapis.com`，要确认 `/v1/chat/completions` 能否用订阅号。
- 影响：把账号 2 的旧 403 状态清成 `active` / `schedulable=true`。未改分组、Key、容器。
- 备份：无。
- 回滚：账号若再被上游打成 error，后台会自己标红。
- 验证：
  - `POST /v1/chat/completions` 模型 `gemini-2.5-flash` → **200**，回复 `sub2api-ok`。
  - `POST /v1beta/models/gemini-2.5-flash:generateContent` → **200**。
  - 后台「测试连接」仍默认打 `gemini-2.0-flash`，上游 404，可忽略。
- 结论：API 启用有效。客户端继续用 `http://mac-mini:18080/v1`。

## 2026-08-16 15:35 CST - 复查 Sub2API Gemini 账号：GCP 项目未开 Cloud AI Companion API

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户新加 Gemini 账号后，`/v1/chat/completions` 仍报 `All available accounts exhausted`。
- 影响：只读。未改账号、分组、Key、容器。
- 备份：无。
- 回滚：无变更。
- 验证：
  - Key `konghai` 已改绑分组 6 `Gemini`；账号 2 已进该组。
  - 账号 2：`platform=gemini` / `oauth` / `oauth_type=google_one` / `project_id=my-openclaw-super-xxk`，状态 **`error`**、`schedulable=false`。
  - 上游 403：`Gemini for Google Cloud API has not been used in project my-openclaw-super-xxk`，需在该项目启用 `cloudaicompanion.googleapis.com`。
  - 15:34 的客户端请求（`ai-sdk/openai-compatible`，模型 `gemini-3.7-flash`）因此被记成 exhausted。
- 结论：调度已选到 Gemini 账号。失败在 Google 侧 API 未启用，不是 Key 或分组。

## 2026-08-16 15:25 CST - 复查 Sub2API：分组已绑上，404 是路径，exhausted 是上游 429

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户建了 `antigravity` 分组并绑上账号和 Key，仍报 `/antigravity` 404 与 `/v1` `All available accounts exhausted`。
- 影响：只读。未改分组、账号、Key、容器。
- 备份：无。
- 回滚：无变更。
- 验证：
  - `account_groups`：账号 1 → 分组 5；Key `konghai` 的 `group_id=5`。绑定正确。
  - 用户客户端是 `ai-sdk/openai-compatible`，打的是 `POST /v1/chat/completions` 模型 `gemini-3.7-flash`。
  - `POST /antigravity/v1/chat/completions` 和 `/antigravity/chat/completions` 为 **404**（该前缀只接 Anthropic `/v1/messages` 和 Gemini `/v1beta/`）。
  - 绑定后同一 Key 的 `/v1/chat/completions` 已能选到 Antigravity 账号，上游返回 **429**，网关对外写成 `All available accounts exhausted`。
  - `POST /antigravity/v1/messages` 同样打到上游 429。
- 结论：调度已通。404 是 OpenAI 客户端不该用 `/antigravity` 当前缀；exhausted 是 Google/Antigravity 限流，不是 Key 或分组错了。

## 2026-08-16 14:45 CST - 只读探测 Sub2API Antigravity Key：鉴权通、推理 503

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户已登录 Antigravity，要用自己的 Key 验证能否真实调用。
- 影响：只读。未改账号、分组、Key、容器。
- 备份：无。
- 回滚：无变更。
- 验证：
  - `GET /v1/models` 200，列出 10 个 Claude 模型。
  - `POST /v1/messages`、`/antigravity/v1/messages`、`/v1/chat/completions`、`/antigravity/v1beta/...generateContent` 均为 **503** `No available accounts`。
  - 库内：Antigravity OAuth 账号 `id=1` 为 `active` / `schedulable`，但 `account_groups` 为空；Key `konghai` 绑在分组 `default`（`anthropic`）。
- 结论：网关和 Key 可用，缺的是「账号进组」。`base_url=http://mac-mini:18080/v1` 还要开 Antigravity 混合调度，否则 Claude 应走 `http://mac-mini:18080/antigravity`。

## 2026-08-16 02:04 CST - 用 Colima 部署 Sub2API 0.1.177（自带小 Postgres + Redis）

- 服务器：`mac-mini`
- 操作人：`Grok`（远程部署），用户确认方案 A 及暴露/模式
- 原因：在家里用 Docker 跑 Sub2API，统一接入 Claude / OpenAI / Gemini / Grok 订阅。
- 选型：官方 compose 本地目录版；镜像钉 `weishaw/sub2api:0.1.177`；Postgres / Redis 跟在同一 compose，不共用 `sonar-postgres` / `richer-postgres`。
- 影响：
  - 新增容器 `sub2api` / `sub2api-postgres` / `sub2api-redis`，`restart: unless-stopped`。
  - 宿主端口 **`0.0.0.0:18080`**。原计划 8080，但 `hon` 的 `colima-multica` SSH 转发已占 `*:8080`（Multica `/healthz`）；未动 hon 的端口。
  - 内存实测约 73 MiB（上限 768/384/128 MiB）。Sonar / richer 未改。
- 备份：`~/backups/sub2api-20260816.tar.gz`（600，含 `.env`）。
- 回滚：`cd ~/stacks/sub2api && docker compose down`。数据在 `data/` `postgres_data/` `redis_data/`，不要加 `-v`。清干净再删这三个目录。
- 变更时序：
  1. `~/stacks/sub2api/` 落 compose + 600 `.env`（`RUN_MODE=standard`，管理员 `konghai007@gmail.com`）。
  2. `docker compose pull` + `up -d`。AUTO_SETUP 建库、建管理员、拉定价数据。
  3. 发现宿主 8080 打到 Multica，改 `SERVER_PORT=18080` 后只重建 `sub2api` 容器。
- 验证：
  - 三容器 healthy；`http://127.0.0.1:18080/health`、`/setup/status`、UI `/`、局域网 `192.168.2.170:18080`、Tailscale `100.108.64.126:18080` 均为 200。
  - 管理员登录 API `POST /api/v1/auth/login` 返回 200。
  - 容器内可访问 Anthropic / OpenAI / xAI。
  - Sonar `UP` 26.3.0；Grafana `:3001` 200；`127.0.0.1:8080/healthz` 仍是 Multica。
- 计划：`docs/plans/2026-08-16-001-ops-mac-mini-sub2api-deploy-plan.md`
- 访问：`http://mac-mini:18080` 或 `http://192.168.2.170:18080`。客户端 `base_url` 指 `http://mac-mini:18080/v1`。

## 2026-08-15 02:51 CST - runner LaunchDaemon 已装上；全员注销后 GitHub 仍 online

- 服务器：`mac-mini`
- 操作人：`konghai`（sudo 安装脚本后注销）、`Grok`（远程核对）
- 原因：让 CI runner 和 Colima / Tailscale 一样，不依赖图形登录。
- 影响：`mac-mini-sonar-1..4` 现为 `system/actions.runner.cypressoai.mac-mini-sonar-N`，以 `konghai` 跑 `runsvc.sh`。旧 Agent plist 仍在 `~/Library/LaunchAgents.disabled-20260815/`。
- 备份：上述 disabled 目录。
- 回滚：`sudo launchctl bootout system/actions.runner.cypressoai.mac-mini-sonar-N` 并删对应 `/Library/LaunchDaemons` plist；需要时把 disabled 目录里的 Agent 移回 `~/Library/LaunchAgents`。
- 验证（控制台用户 `root`，`who` 空）：
  - 四个 job `state=running`，各有 `Runner.Listener --startuptype service`。
  - GitHub：四个均为 `online`；当时 1 和 3 `busy=true`（已在接活）。
  - Sonar 仍 `UP`，Tailscale 仍 `100.108.64.126`。

## 2026-08-15 02:46 CST - 准备把 mac-mini-sonar-1..4 改成 LaunchDaemon

- 服务器：`mac-mini`
- 操作人：`Grok`（挪走 Agent、写脚本）、待 `konghai` 本机 sudo
- 原因：全员注销后 runner 不在，和 Colima 同一类问题。
- 影响：四个 LaunchAgent plist 已移到 `~/Library/LaunchAgents.disabled-20260815/`（登录也不会再拉）。Daemon 尚未装，runner 仍停。
- 备份：上述 disabled 目录里的原 plist。
- 回滚：把 plist 移回 `~/Library/LaunchAgents`，不要装 Daemon。
- 脚本：`~/Downloads/install-mac-mini-runner-daemons.sh`。恢复脚本已改为 kickstart `system/…`。不要再用 `./svc.sh install`。
- 验证：安装脚本尚未执行。

## 2026-08-15 02:44 CST - 全员注销后验证：Tailscale + Colima + 4 个容器仍在

- 服务器：`mac-mini`
- 操作人：`konghai`（跑完 daemon 脚本后注销所有用户）、`Grok`（远程验证）
- 原因：确认不再依赖任何人的图形会话。
- 影响：只读。`/dev/console=root`，`who` 为空。
- 备份：无。
- 回滚：无变更。
- 验证：
  - `ssh mac-mini`（`100.108.64.126`）通；`tailscaled` LaunchDaemon 在线，MagicDNS `mac-mini`。
  - `system/com.konghai.colima` running；四个容器 healthy / Grafana 200；Sonar `UP` 26.3.0。
  - `mac-mini-sonar-1..4` 的 `Runner.Listener` **不在**（仍是 LaunchAgent，注销后会停）。这是预期，尚未改 runner。

## 2026-08-15 02:38 CST - 仅迁正在跑的 4 个容器到 Colima；Sonar / richer 已 UP

- 服务器：`mac-mini`
- 操作人：`Grok`（导出/导入、切引擎）、`konghai`（本机开过 Docker Desktop 以便导出）
- 原因：Docker Desktop 绑 GUI；只把当前在跑的服务迁到 Colima（vz / 6 CPU / 12 GiB / 100 GiB 盘）。
- 影响：
  - 迁了 `sonarqube`、`sonar-postgres`、`richer-grafana`、`richer-postgres`。其它已停用容器未迁。
  - 备份在 `~/backups/colima-migrate-20260815/`（pg_dump + named volume tar，600）。
  - richer 补了 `~/stacks/richer/docker-compose.yml`；postgres 改为 named volume `richer_pg_data`。
  - Docker context 默认 `colima`。Desktop 已强制退出，`AutoStart` 保持 false。App 先留着回滚。
  - `~/.zshenv` 把 `/opt/homebrew/bin` 提前，并默认 `DOCKER_HOST` 指向 Colima socket。
- 备份：上述目录。Desktop 侧原容器只是 stop，未 rm。
- 回滚：`colima stop` → 开 Docker Desktop → `docker context use desktop-linux` → `docker start` 原来的四个容器。
- 验证：
  - `http://127.0.0.1:9000/api/system/status` → `UP` / 26.3.0.120487
  - Grafana `:3001/login` HTTP 200
  - sonar 库 125 张表；richer 库 15 张表
- 未完成：Colima 还不是 LaunchDaemon。安装脚本已放到 `~/Downloads/install-colima-daemon.sh`，需本机 `sudo` 执行（会短暂停一下再由 launchd 拉起）。

## 2026-08-15 02:22 CST - MagicDNS 短名 mac-mini 已收回

- 服务器：`mac-mini`
- 操作人：`konghai`（管理后台改名）、`Grok`（验证）
- 原因：把 `mac-mini-1` 改回 `mac-mini`，恢复 CI / 文档里的 `http://mac-mini:9000`。
- 影响：只读验证 + 文档。未改 daemon。
- 备份：无。
- 回滚：无变更。
- 验证：`DNSName=mac-mini.taila93443.ts.net`；本机 `dscacheutil` 解析到 `100.108.64.126`；`tailscale ping mac-mini` 约 3ms（直连局域网）。`mac-mini-1` 已不存在。

## 2026-08-15 02:20 CST - 节点 IP 已改回 100.108.64.126；MagicDNS 仍是 mac-mini-1

- 服务器：`mac-mini`
- 操作人：`konghai`（管理后台改 IP、删旧节点）、`Grok`（改 hostname、ssh config、验证）
- 原因：用户已删除旧机器，并把新节点 IPv4 改回原来的 `100.108.64.126`，避免改文档和 CI 里的硬编码。
- 影响：本机 `Host mac-mini` 改回 `100.108.64.126`；`ssh mac-mini` 测通。`tailscale set --hostname=mac-mini` 已执行，但控制面显示名仍是 `mac-mini-1`，MagicDNS `mac-mini` 尚无法解析。
- 备份：无。
- 回滚：IP 已回到原值，无需回滚。
- 验证：
  - `tailscale ip -4` = `100.108.64.126`，`Online=true`，`WantRunning=true`
  - `ssh mac-mini` → `SSH_OK`
  - `tailscale ping mac-mini` → `lookup mac-mini: no such host`；`mac-mini-1` 可 ping
- 下一步：在管理后台把机器名从 `mac-mini-1` 改成 `mac-mini`，短名才会回到 `http://mac-mini:9000`。然后装 Colima。Docker Desktop 当前未在跑。

## 2026-08-15 02:15 CST - Homebrew tailscaled 已登录；新 IP 100.86.35.24，短名暂为 mac-mini-1

- 服务器：`mac-mini`
- 操作人：`konghai`（本机 `sudo brew services start` + `tailscale up`）、`Grok`（装 formula、改本机 ssh config、验证）
- 原因：换成登录前也能跑的开源 `tailscaled`，妻子解 FileVault 后办公室仍能经 Tailscale SSH。
- 影响：
  - GUI Standalone 已卸。Homebrew `tailscale` 1.102.2 以 LaunchDaemon `homebrew.mxcl.tailscale` 跑（root，`KeepAlive` + `RunAtLoad`，含 `System`/`LoginWindow`）。
  - 新节点 `100.86.35.24`，`WantRunning=true`，`--operator=konghai`，`--hostname=mac-mini`，`CorpDNS=true`。
  - 旧节点 `100.108.64.126` / DNS `mac-mini` 仍在 tailnet（offline）。新机因此叫 `mac-mini-1`。未删旧节点前，MagicDNS `mac-mini` 和 CI 的 `http://mac-mini:9000` 会指到已死的旧 IP。
  - 本机 `~/.ssh/config` 的 `Host mac-mini` 已改为 `100.86.35.24`；`ssh mac-mini` 已测通。
- 备份：无（新节点重新登录，未搬 GUI 状态）。
- 回滚：停 daemon：`sudo brew services stop tailscale`；重装 GUI 前先卸 formula。旧 IP 不可用。
- 验证：
  - `launchctl`：`system/homebrew.mxcl.tailscale` running，pid 12650。
  - 本机 `tailscale ping mac-mini-1` → `100.86.35.24` 约 14ms（走局域网）。
  - `ssh mac-mini`（新 IP）返回 `SSH_OK`。
- 下一步：在 [Tailscale 机器列表](https://login.tailscale.com/admin/machines) 删除旧的 `mac-mini`（`100.108.64.126`），再 `tailscale set --hostname=mac-mini`，让短名回到 `mac-mini`。然后才迁 Colima。

## 2026-08-15 02:05 CST - 用户确认 ziyi 已在 FileVault；GUI Tailscale 必须人在本机卸

- 服务器：`mac-mini`
- 操作人：`Grok`（只读 + 本机加 SSH 兜底）+ 用户决策
- 原因：用户确认妻子账户已启用文件保险柜，同意 Colima + Homebrew `tailscaled`，并问 GUI 版要不要手动卸载。
- 影响：未卸 Tailscale、未装 Colima。仅在**本机** `~/.ssh/config` 增加 `Host mac-mini-lan`（`ProxyJump pve` → `192.168.2.170`），供切换窗口断 Tailscale 时从办公室绕回家。
- 备份：改 ssh config 前可从 Time Machine / 编辑器撤销；未动服务器。
- 回滚：删掉 `Host mac-mini-lan` 段。
- 结论：
  - GUI Standalone（`/Applications/Tailscale.app` + 系统扩展）和 brew `tailscaled` **不能并存**，必须卸 GUI。
  - 官方步骤要拖 App 进废纸篓、确认卸扩展、清空废纸篓、重启。系统扩展对话框和重启必须有人在机前；远程无 passwordless sudo。
  - `Host mac-mini` 现指向 `100.108.64.126`；重装 OSS daemon 后节点 IP 预期会变，切完要改 HostName，并用 `--hostname=mac-mini` 保住短名。
- 尚未执行卸载或 `brew install`。等用户约定窗口（妻子在家或本人回家）再切。

## 2026-08-15 01:48 CST - 只读确认：ziyi 登录后当前 Tailscale 不会为公司 SSH 自动起来

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户在办公室只靠 Tailscale 连回家，问掉电后妻子登 `ziyi`、再注销，挂在 `konghai` 下的 Tailscale 会不会起来。
- 影响：只读。未改 Tailscale / FileVault / 登录项。
- 备份：无。
- 回滚：无变更。
- 验证：
  - 装的是 Standalone `com.tailscale.ipn.macsys` 1.102.2，不是 App Store。
  - 两个进程：root 的 `io.tailscale.ipn.macsys.network-extension`（数据面）、`konghai` 的 `Tailscale.app`（菜单栏）。`WantRunning=true`，`LoggedOut=false`，节点 `100.108.64.126` / `k@cypresso.ai`。
  - 今日 `kern.boottime=00:15:33`，两进程均 `00:16:36` 启动，与 `konghai` 控制台 00:16 登录对齐。
  - 官方 [macos-variants](https://tailscale.com/docs/concepts/macos-variants)：Standalone `Run before login = no`；开源 `tailscaled` 才是 `yes`。[unattended](https://tailscale.com/docs/how-to/run-unattended) 写明 macOS 还不能当系统服务跑。
- 结论：妻子只登她的账户，办公室经 Tailscale SSH 回家不可靠。08-13 GUI 崩了还能打到 `100.108.64.126`，是因为隧道当时已经建好。要「解完盘就能从公司连」，需另把 Tailscale 改成 `tailscaled` LaunchDaemon。
- 计划已更新：`docs/plans/2026-08-15-001-ops-mac-mini-headless-docker-plan.md`

## 2026-08-15 01:35 CST - 敲定 Colima 仍用 konghai；掉电不能 SSH 解 FileVault

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）+ 用户决策
- 原因：用户确认不建专用 Colima 用户；掉电由 `ziyi` 在开机屏解锁；并问能否 SSH 进 `konghai` 远程解 FileVault。
- 影响：只读。未建用户、未改 FileVault、未装 Colima。
- 备份：无。
- 回滚：无变更。
- 结论：
  - Colima 计划维持「装在 `konghai` + LaunchDaemon `UserName=konghai`」。
  - 冷启动 / 掉电：**不能** SSH 解锁。盘未开时 sshd 不在。`ziyi`（或任何已启用的 FileVault 用户）必须在机前输一次密码；解完后可 SSH `konghai`，LaunchDaemon 即可拉 Colima。
  - `pmset autorestart=1`：来电会自动开机，然后停在 FileVault 屏等人口令。
  - 远程看不到 `ziyi` 的 AuthenticationAuthority（无 sudo / `fdesetup list`）。执行迁移前要在本机确认她已在解锁名单，否则开机屏只有 `konghai`。
- 计划已更新：`docs/plans/2026-08-15-001-ops-mac-mini-headless-docker-plan.md`

## 2026-08-15 01:10 CST - 只读评估：Docker Desktop 无法无登录常驻，推荐换 Colima

- 服务器：`mac-mini`
- 操作人：`Grok`（只读排查 + 写计划）
- 原因：用户要把 mac-mini 当服务器用——开机后不登录图形界面，容器也要起来；并嫌 Docker Desktop GUI 费资源。结合 2026-08-13 WindowServer 崩溃后 Desktop 连带掉线、以及今天 00:15 重启后部分容器没起来。
- 影响：只读。未改 Docker / 容器 / FileVault / 登录项 / runner。
- 备份：无。
- 回滚：无变更。
- 做了什么：
  1. 核对引擎、socket、Desktop 设置、FileVault、自动登录、容器 restart policy、compose 归属、runner LaunchAgent。
  2. 把结论写成 `docs/plans/2026-08-15-001-ops-mac-mini-headless-docker-plan.md`。
- 验证（只读快照，约 01:05 CST）：
  - Docker Desktop 4.82.0，VM **8 CPU / 24 GiB**，`AutoStart=true` 但会弹出 GUI；`/var/run/docker.sock` 链到 `konghai` 的 Desktop socket，`hon` 在 `docker` 组。
  - FileVault **开着**，自动登录未开。冷启动必须有人在登录窗解锁，这不是 Docker 能绕开的。
  - 当时在跑：`sonarqube` / `sonar-postgres`（healthy）、`richer-grafana` / `richer-postgres`。`acquilang-postgres`、`multica-*`、`cypresso-okr-*` 虽有 restart policy，重启后未保持运行。
  - 四个 `mac-mini-sonar-*` runner 仍是 LaunchAgent（`ProcessType=Interactive`），和 Desktop 一样绑 GUI 会话。
- 结论：Docker Desktop 没有 headless / LaunchDaemon 模式，不能靠「开机脚本 + 登录自启」解决注销或 WindowServer 崩溃。推荐换成 **Colima + LaunchDaemon**，有状态卷导出导入后卸 Desktop。未执行迁移，等用户确认。
- 计划：`docs/plans/2026-08-15-001-ops-mac-mini-headless-docker-plan.md`

## 2026-08-15 00:42 CST - 重启后复查：ToDesk 未回潮；SonarQube 容器未自动拉起

- 服务器：`mac-mini`
- 操作人：`konghai`（重启）、`Grok`（只读复查）
- 原因：卸载 ToDesk 后用户重启，确认残留是否被 launchd 拉回，并看 CI 相关服务是否起来。
- 影响：只读。未启动容器、未改配置。
- 备份：无。
- 回滚：无变更。
- 验证：
  - `kern.boottime` = `2026-08-15 00:15:33`，uptime 约 27 分钟；控制台用户 `konghai` 于 `00:16` 登录。
  - ToDesk 进程、App、plist、PrivilegedHelper、HAL 驱动、pkgutil 收据、声音设备名均不存在。默认输出仍是 LG UltraFine。
  - launchd 仍有三条 `com.youqu.todesk.* => disabled` 空标签，无对应文件，重启后也未启动。
  - `mac-mini-sonar-1..4` 的 `Runner.Listener` 均在 `00:16` 拉起。
  - Docker Desktop 已起来；当时在跑的只有 `acquilang-postgres`、`richer-grafana`、`richer-postgres`。
  - `sonarqube` 为 `Exited (137)`（重启被 SIGKILL），`sonar-postgres` 为 `Exited (0)`，本机 `127.0.0.1:9000` connection refused。未代为 `docker start`。
- 结论：ToDesk 卸载在重启后仍然干净。SonarQube 需手动拉起后 CI 才能扫。

## 2026-08-15 00:12 CST - ToDesk 已彻底卸载，复查通过

- 服务器：`mac-mini`
- 操作人：`konghai`（本机 `sudo /tmp/uninstall-todesk.sh --apply`）、`Grok`（远程核对日志）
- 原因：清掉自 2026-07-21 起常驻、累计约 890 小时 CPU 的 ToDesk 服务，避免快切用户时再截鼠标。
- 影响：`ToDesk.app`、系统服务、LoginWindow Session Proxy、虚拟声卡、各用户配置和安装收据已删除。默认输出仍是 LG UltraFine。Docker / SonarQube / runner 未动。
- 备份：`/Library/Preferences/Audio/com.apple.audio.SystemSettings.plist.bak.20260815`
- 回滚：重装 ToDesk；音频可用上述 bak 还原后再 `killall coreaudiod`。
- 日志要点（`/tmp/uninstall-todesk.log`，`00:12:05` 起 `uid=0`）：
  - bootout 成功：`system/com.youqu.todesk.{service,UninstallerHelper,UninstallerWatcher}`、`gui/501` 的 desktop/startup
  - 删除 App、5 个 plist、PrivilegedHelper、HAL `ToDeskOutputDriver.driver`、系统 Application Support/Logs，以及 `claw_bot` / `coding` / `hon` / `konghai` / `ziyi` 家目录里的 ToDesk 数据
  - forget：`com.youqu.todesk.mac` / UninstallerClient / UninstallerHelper
- 验证（00:13 CST 远程复查）：
  - 进程无 `ToDesk_Service` / `ToDesk_Session_Proxy`
  - `/Applications/ToDesk.app`、HAL 驱动、pkgutil 收据均不存在
  - 声音设备列表无 ToDesk；默认输出 LG UltraFine
  - launchd 仅剩三条 `disabled` 空标签，无对应 plist，不会再启动
- 建议：方便时重启一次 mac-mini，让 launchd 空标签和 coreaudiod 状态彻底掉干净。重启前确认 Sonar / runner 窗口可接受。

## 2026-08-15 00:09 CST - 图形密码框通过后脚本未以 root 执行，改为走 sudo

- 服务器：`mac-mini`
- 操作人：`Grok`（改脚本）、`konghai`（在图形界面多次输入密码）
- 原因：用户在终端跑 `~/Downloads/uninstall-todesk.sh`，图形密码框弹出且密码正确，但脚本仍报「无法弹出密码框或你取消了」。
- 影响：ToDesk 仍在跑，尚未删除。已覆盖下载目录和 `/tmp` 里的脚本。
- 备份：无。
- 回滚：无卸载发生。
- 排查：`/tmp/uninstall-todesk.log` 只有 `mode=auto` / `user=konghai` 的扫描，没有任何 `mode=apply` 或 `uid=0`。说明密码过了，但 `osascript with administrator privileges` 没能执行位于「下载」的脚本（TCC / `com.apple.macl`）。错误信息把所有 osascript 失败都说成「取消密码框」，是误导。
- 修复：脚本改为终端里 `exec sudo ... --apply`；图形提权只跑 `/tmp` 副本，并打印系统原始错误。
- 用户下一步：
  ```bash
  sudo /tmp/uninstall-todesk.sh --apply
  ```

## 2026-08-15 00:00 CST - 把 ToDesk 卸载脚本放到下载目录

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户要在图形界面自己执行卸载，需要在「下载」里能看到脚本。
- 影响：只新增 `~/Downloads/uninstall-todesk.sh`（755），未跑卸载、未改服务。
- 备份：无。
- 回滚：删掉该文件即可。家目录和 `/tmp` 里先前那两份仍在。
- 验证：`ls` 显示 `-rwxr-xr-x`，SHA-256 与仓库脚本一致。
- 用户下一步：打开终端执行 `~/Downloads/uninstall-todesk.sh`，在密码框输入本机登录密码；卸完建议重启。

## 2026-08-14 23:58 CST - 扫到完整 ToDesk 仍在跑，脚本已就位，远程 sudo 未执行

- 服务器：`mac-mini`（SonarQube 宿主、self-hosted runner；macOS 26.5.2）
- 操作人：`Grok`
- 原因：本机 MacBook Air 已确认 ToDesk 残留会导致快切用户后鼠标卡死；用户要求在 `mac-mini` 上同样彻底卸载。
- 影响：本次**未改** ToDesk、Docker、SonarQube、runner 或音频。只把卸载脚本拷到该机。
- 备份：无（尚未删除任何文件）。
- 回滚方式：无变更。
- 只读扫描：
  - `/Applications/ToDesk.app` 仍在；`ToDesk_Service` pid 604 自 2026-07-21 起运行，CPU 累计约 890 小时。
  - `ToDesk_Session_Proxy` 挂在 `konghai`；launchd 还为 uid 501/503/505（`konghai` / `ziyi` / `coding`）注册了 `ToDesk_Service_*`。
  - 系统 plist、PrivilegedHelper、HAL `ToDeskOutputDriver.driver`、pkg `com.youqu.todesk.mac` 均在。当前默认输出已是 LG UltraFine，设备列表里没有 ToDesk 虚拟声卡名。
  - 远程 `osascript` 提权返回「管理员用户名或密码不正确」(-60007)，SSH 也无 passwordless sudo。
- 脚本位置（该机，2026-08-15 00:00 已再拷到下载目录）：`/Users/konghai/Downloads/uninstall-todesk.sh`（与仓库 `scripts/uninstall-todesk.sh` 相同）。在 mac-mini 图形会话的「终端」执行：
  ```bash
  ~/Downloads/uninstall-todesk.sh
  ```
  或 `sudo ~/Downloads/uninstall-todesk.sh --apply`。卸完建议重启再确认进程和 HAL 都消失。
- 验证结果：卸载尚未执行。背景见 `docs/solutions/best-practices/todesk-incomplete-uninstall-fast-user-switch-mouse-lag-2026-08-14.md`。

## 2026-08-13 10:49 CST - 只读确认 SonarQube 正常，CI 首跑失败在 runner 的 Tailscale 链路

- 服务器/设备：`mac-mini`（SonarQube 宿主）；对照 `umacbook-pro-1`
- 操作人：`Codex`
- 原因：排查 [iCare-public-frontend attempt 1 Job 94327015274](https://github.com/cypressoai/iCare-public-frontend/actions/runs/31661331203/job/94327015274) 在 Web 页面可访问时仍报 Sonar server connect timeout 的原因。
- 影响：仅通过 GitHub API / Job 日志和 SSH 检查 SonarQube 容器状态、HTTP/访问日志及 runner 的 DNS、路由和 Tailscale 历史日志；未改 Docker、SonarQube、Tailscale、runner、workflow 或业务代码，未触发重跑。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：
  1. 检查 `sonarqube` / `sonar-postgres` 当前状态、`sonarqube` start time、restart count、容器健康探针及 10:35–10:45 UTC 访问日志。
  2. 对照 `umacbook-pro-1` 在失败时刻的 TCP SYN、Tailscale DERP/peer 日志与当前 HTTP 连通性。
  3. 核对同一 workflow attempt 2 的 [Job 94327302116](https://github.com/cypressoai/iCare-public-frontend/actions/runs/31661331203/job/94327302116) 和服务端 ScannerCLI 访问记录。
- 验证结果：
  - `sonarqube` 自 `2026-08-12 17:26:12Z` 起持续运行，检查时 `healthy`、`RestartCount=0`；10:35–10:45 UTC 每 15 秒的 `/api/system/status` 健康探针均为 HTTP 200，故障窗口没有服务重启或失活证据。
  - attempt 1 的 ScannerCLI 于 `10:40:08` 从 `umacbook-pro-1` 发起连接，但 Tailscale 记录目标 peer `lastRecv=6h19m1s`，5 秒内 6 个 SYN 均无响应；Sonar access log 没有收到对应请求。因此报错发生在 HTTP 建连前，不涉及 token、Quality Gate 或项目扫描。
  - Tailscale 在该连接窗口将 runner 的 home DERP 从 `derp-900` 切到 `derp-17`；attempt 2 扫描前重新为目标 peer 建立 `derp-900` 连接。服务端于 `10:42:17` 收到同版本 ScannerCLI 的 `/api/v2/analysis/version` 并返回 HTTP 200，attempt 2 最终 Quality Gate `PASSED`、workflow 成功。
  - 当前宿主本地访问 API 约 `0.006s`、runner 经 Tailscale 约 `0.39s` 均能立即获得 HTTP 响应。结论：**SonarQube 服务端在本次 10:40 失败窗口内正常；失败由 `umacbook-pro-1 → mac-mini` 的 Tailscale peer/DERP 瞬断触发，链路随后自动恢复。**

## 2026-08-13 01:35 CST - 恢复 Docker Desktop 并确认并非整机重启

- 服务器：`mac-mini`（SonarQube 宿主、self-hosted runner `mac-mini-sonar-1..4`）
- 操作人：`konghai`（现场登录并启动 Docker Desktop）、`Codex`（只读排查与验证）
- 原因：00:55 CST 起 iCare SonarQube CI 无法连接；现场重新登录 macOS 后启动 Docker Desktop，SonarQube 恢复，但观察到类似机器重启后的登录界面，需确认是否发生整机重启及其原因。
- 影响：
  - `2026-08-13 00:37:46`，macOS `WindowServer` 被内核终止，`konghai` / `coding` / `ziyi` 三个 GUI session 被强制注销；依赖 `konghai` GUI session 的 Docker Desktop 与 `mac-mini-sonar-1..4` LaunchAgent runner 随之停止。
  - Docker Desktop 停止期间 `sonarqube` / `sonar-postgres` 不可用，导致至少 iCare-backend run `31617573433` 与 `31617651468` 的 SonarScanner 无法查询 server version；本机四个 runner slot 也退出调度池。
  - macOS 内核、SSH 和主机网络始终在线，未发生整机重启或断电。
- 备份：无（现场仅启动既有 Docker Desktop；后续调查均只读，未改配置或数据）。
- 回滚方式：可退出 Docker Desktop 回到故障前状态，但会再次停止 SonarQube 及本机所有 Docker 容器，不建议作为常规回滚。
- 变更时序：
  1. `00:37:46.369`，内核记录旧 `WindowServer`（PID 445）已分配 **305,834 Mach ports**：`caught allocating too many mach ports`，随即触发 fatal exception，并以 signal 9 强制结束进程。
  2. 三个 `loginwindow` session 同时记录 `directLogoutReason:WindowServerExited`，证明是 WindowServer 先退出、系统再强制注销用户，并非用户主动注销。
  3. Docker Desktop 日志同步记录 `terminated signal received`，随后显式关闭 Docker API socket、请求 VM poweroff，并记录 `dockerd exited due to explicit Stop() call`；因此 Docker 是 GUI session 退出的受害者，不是 WindowServer 故障发起者。
  4. `00:37:46` 后系统自动拉起新 `WindowServer` / `loginwindow`，停留在登录界面；`01:21` 远程检查时 `/dev/console=root`、无 Docker socket、TCP 9000 无监听。
  5. `01:25`，`konghai` 现场登录并启动 Docker Desktop；Docker backend、四个 runner listener 与 Sonar 容器相继恢复。
- 根因判断：
  - **不是整机重启**：`kern.boottime` 仍为 `2026-07-21 08:53:53`，uptime 22 天以上；`last reboot`、`pmset` 与 panic / shutdown reports 均无本时段重启记录。
  - **直接根因**：运行 22 天的 WindowServer 累计耗尽 Mach port 配额，被内核保护机制 SIGKILL，造成全部 GUI session 重建。
  - **不是 OOM / 电源故障**：内核明确报 port exhaustion；无 jetsam、memory-pressure kill、panic 或掉电证据，swap 使用仅约 6.69MB。
  - **底层泄漏源暂不能唯一定位**：故障前 SkyLight 持续报 `CGXRegisterForPortNotification: mach_port_request_notification: invalid argument`，临近退出又每秒报 `_CGXPackagesSetWindowConstraints: Invalid window`，说明 WindowServer 的 port / window bookkeeping 已异常；但保留日志未携带具体客户端身份。`konghai` / `coding` / `ziyi` 三个长期 Fast User Switching session 会扩大图形状态面，只能视为风险放大因素，不能据此认定某个用户或 App 是泄漏源。
- 验证结果：
  - 新 `WindowServer` PID 29298 当前约 **2,349 ports**，已从异常的 305,834 回到正常低位。
  - `sonar-postgres`、`sonarqube` 均为 `healthy`；本机 `http://127.0.0.1:9000/api/system/status` 与 `mas-go-dev` 经 `http://mac-mini:9000/api/system/status` 均返回 HTTP 200、`status=UP`。
  - `mac-mini-sonar-1..4` 的 `Runner.Listener` 均于 `01:25:54–01:25:55` 拉起。
  - 本次未重跑失败的 GitHub Actions Job，避免在诊断之外改变 PR check 状态。
- 后续建议（未执行）：定期采样 WindowServer port 数；若持续增长，保留增长窗口内的进程 / WindowServer 连接快照以定位泄漏客户端；尽量减少长期并存的 Fast User Switching session。由于 Docker Desktop 和 runner 均绑定 GUI session，还应另行评估登录会话退出后的自动恢复与告警，避免 Sonar 静默下线。

## 2026-08-13 01:21 CST - 只读确认 SonarQube 因 Docker Desktop 未运行而不可达

- 服务器：`mac-mini`（SonarQube 宿主；对照 `mas-go-dev-ci-2`、`umacbook-pro-2`）
- 操作人：`Codex`
- 原因：排查 [iCare-backend Job 94190148086](https://github.com/cypressoai/iCare-backend/actions/runs/31617573433/job/94190148086) 的 SonarScanner server version 查询失败。
- 影响：只读检查 Docker API、相关进程、TCP 9000、SonarQube HTTP 状态、宿主机 uptime 与 Actions 对照日志；未启动 Docker Desktop、未启动或重启容器、未改 runner / Sonar / workflow / 代码，未重跑 Job。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：
  1. 从 `mas-go-dev` 验证 `mac-mini` MagicDNS 解析正常，但 `http://mac-mini:9000/api/system/status` connection refused。
  2. 在本机检查 Docker CLI socket、Docker / SonarQube 进程、TCP 9000 listener 与最近 reboot 记录。
  3. 对照 `umacbook-pro-2` 上 run `31617651468`：另一台 runner 同样在测试与 coverage 成功后无法查询 SonarQube server version。
- 验证结果：
  - 宿主机已连续运行 22 天，本次故障不是 mac-mini 重启造成。
  - Docker Desktop 主进程不在；`/Users/konghai/.docker/run/docker.sock` 不存在，Docker API 无法连接，TCP 9000 无监听，`curl http://127.0.0.1:9000/api/system/status` connection refused；仅 `com.docker.vmnetd` 特权 helper 仍在。
  - 2026-08-12 23:53 CST 前的 run `31614002062` 可成功完成 Sonar 扫描；2026-08-13 00:55 CST 的目标 Job 及 01:17 CST 的 `umacbook-pro-2` Job 均报相同连通性错误。结论：**mac-mini 上 Docker Desktop 在该窗口内停止运行，连带 SonarQube 容器下线，是本次 CI 失败的直接原因；不是业务代码或某一 runner 故障。**
  - 恢复需启动 Docker Desktop，并验证 `sonar-postgres` / `sonarqube` healthy 与 `/api/system/status` 返回 `UP` 后再重跑 CI；本次未执行，等待用户确认。

## 2026-08-12 09:43 CST - 只读排查 iCare-mobile-app CI Quality Job 93874987093 失败

- 服务器：`mac-mini`（self-hosted runner `mac-mini-sonar-2`）
- 操作人：Codex（只读）
- 原因：排查 GitHub Actions [CI Quality Job 93874987093](https://github.com/cypressoai/iCare-mobile-app/actions/runs/31520169797/job/93874987093) 是 runner 环境还是代码侧导致失败。
- 影响：仅读取 GitHub Actions 日志和 runner 配置/进程/工作目录；未修改 runner、LaunchAgent、工作目录或仓库代码，未重启服务。
- 做了什么：
  1. 读取 Job 日志，失败点为 `pnpm install --frozen-lockfile`：`ERR_PNPM_ENOENT ... mkdir '.../node_modules'`。
  2. 查询 PR #128 的文件变更与 Git tree，确认其新增的根目录 `node_modules` 是 mode `120000` 的符号链接，内容为开发者本机绝对路径 `/Users/hon/code/Ai/iCare/mobile-app/node_modules`。
  3. 核对 `mac-mini-sonar-2` 的 `workFolder=/Users/konghai/gha/s2`、四个 `Runner.Listener` 进程与 LaunchAgent，均正常运行。
- 结论：**代码/PR 侧问题，非 runner 故障。** runner 上不存在该开发者本机路径，`pnpm` 无法在已被该失效符号链接占用的 `node_modules` 路径下创建依赖目录。应从 PR 删除该符号链接（并确认 `.gitignore` 继续忽略 `node_modules`）后重跑 CI。
- 备份：无（只读）。
- 回滚：无变更。
- 验证结果：checkout、Node 20.20.2 与 pnpm 初始化均成功；失败发生在依赖写入前，后续 lint / type check / jest 均未执行。

## 2026-08-07 13:37 CST - mac-mini Mini Shai-Hulud IoC **full 重扫**（补齐先前 FAIL）

- 服务器/设备：`mac-mini`
- 操作人：`Grok`
- 原因：同日首轮并行 full 扫描中 `mac-mini` 记录为 `DONE mac-mini FAIL rc=255`（05:14:55Z，无界 `find` 过大树导致 SSH 中断）；验收要求补齐与 lemon-imac 同结构的 full 只读日志，不得仅用浅扫冒充完成。
- 影响：只读；未改配置、未重启、未删文件、未轮换凭证。
- 先前失败：`remote-scan-progress.txt` → `START mac-mini mode=full 05:08:15` / `DONE mac-mini FAIL rc=255 05:14:55`；中间仅有浅扫摘要，已作废为正式结论。
- 重扫方法（05:32:31Z–05:37:14Z UTC）：`mdfind` 全机文件名 + `find` 高价值根（`~/gha` `~/actions-runner` `~/Code` Desktop Documents `/opt`）+ `rg` 扫 preinstall/lock/hooks；`ServerAliveInterval=15`；SSH exit 0。
- 结果：
  - `IOC_FILENAME_HIT_COUNT=10`：均为 `motion-dom/.../setup.mjs`（hash `c2f397ef…`）或 `regenerate-unicode-properties/.../Math_Symbol.js`（hash `b66c1e0b…`），**非** Aikido 恶意哈希。
  - `MALICIOUS_HASH_COUNT=0`，`PREINSTALL_HIT_COUNT=0`，`LOCKFILE_HIT_COUNT=0`，`HOOK_HIT_COUNT=0`。
  - gha/actions-runner 下存在正常 `keyv`/`flat-cache`/`file-entry-cache` 目录，**目录内无** `setup.mjs`/`Math_Symbol.js`/`math_init.js`。
  - 结论：`VERDICT=CLEAN_FALSE_POSITIVE_NAME_COLLISION`（与 lemon-imac / umacbook-pro 同类误报）。
- 备份：无（只读）。
- 回滚：无变更。
- 证据：`scan-mac-mini.log`（含 `PRIOR_FULL_FAIL` / `RESCAN_OK=1`）。

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`mac-mini`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：CLEAN。浅扫 30 个 keyv/flat-cache 等 risk 包目录，无恶意文件/preinstall/hook/lock 命中。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

## 2026-08-05 23:24 CST - 补回 mac-mini-sonar-1..4 的 `self-hosted` label

- 服务器：`mac-mini`（org runner `mac-mini-sonar-1..4`，id 22–25）
- 操作人：`Grok`
- 原因：backend CI workflow 使用 `runs-on: [self-hosted, backend-ci]`；`mac-mini-sonar-*` 虽有 `backend-ci` 但缺默认 label `self-hosted`，GitHub 调度硬匹配两边都要满足，导致 4 台闲置也永远进不了 backend 池。任务只能在 `mas-go-dev-ci` + `lemon-imac` + `umacbook-pro` 之间轮转，经常看起来都堆在 `mas-go-dev-ci-1`。
- 影响：`mac-mini-sonar-1..4` 重新进入 `[self-hosted, backend-ci]` 调度池；不动任何 workflow；前端 `mac-mini-sonar` / `frontend-*-ci` 匹配不受影响。
- 选型：方案 A（推荐）——只修 runner label，与 lemon / umac / mas-go-dev-ci 一致；不改业务仓 workflow。
- 备份：操作前 API 快照（4 台均无 `self-hosted`）：
  - id 22–25 labels：`mac-mini-sonar, macos, arm64, backend-ci, frontend-sonar-ci, frontend-tests-ci, frontend-quality-ci`
- 回滚方式：
  ```bash
  for id in 22 23 24 25; do
    gh api --method DELETE "orgs/cypressoai/actions/runners/${id}/labels/self-hosted"
  done
  ```
- 做了什么：
  ```bash
  for id in 22 23 24 25; do
    gh api --method POST "orgs/cypressoai/actions/runners/${id}/labels" -f 'labels[]=self-hosted'
  done
  ```
- 验证结果：
  - `mac-mini-sonar-1..4` labels 均含 `self-hosted` + `backend-ci`，status=`online`
  - 全 org `backend-ci` 池（10 slot：mac-mini×4 + lemon×2 + umac×2 + mas-go-dev-ci×2）`has_self_hosted=true`
- 补完后注意：
  1. **同机并发**：4 slot 若同时接 Go 全量 coverage + 前端 Vitest，会抢 CPU/磁盘；可接受，但别期望 4 路 backend 全开还很快。
  2. **能力**：本机已是重活机（gpg/dirmngr、CGO、per-slot GOCACHE 等见 `docs/runbooks/ci-runner-pools.md`）；建议观察接下来 1～2 个落到 mac-mini 的 Sonar job。
  3. **容量预期**：真正该多吃 backend 的是 mac-mini（10 核 / 32GB）；lemon/umac 的 8GB 适合轻中负载，修好 label 后分布应更健康。

## 2026-08-03 15:42 CST - CI 池加固：PNPM store + 日/周维护 + 四 slot 重启

- 服务器：`mac-mini`
- 操作人：`Grok`（iCare 自托管 runner 运维加固任务）
- 原因：质量门迁自托管后并发更高；需减 npm/pnpm 重复下载流量，并防止 `_work` / go-build 撑盘。
- 影响：
  - 四 slot `.env` 增加 `PNPM_STORE_PATH=~/gha/cache/pnpm-store`（保留 per-slot `GOCACHE` + 共享 `GOMODCACHE=~/gha/cache/go-mod`）
  - 部署脚本：`~/gha/scripts/{gha-runner-maintenance.sh,prune-gocache.sh}`
  - crontab：每日 03:15 清 work + 修剪 go-build；周日 04:30 weekly（pnpm prune / gomod 超 10G）
  - 即时维护：stale workFolder 清理（s1–s4 各约 4.0G→2.4–2.8G）；四 slot `svc.sh` 重启以加载 `.env`
- 备份：`~/actions-runner/mac-mini-sonar-N/.env.bak.<timestamp>`
- 回滚方式：恢复各 slot `.env.bak.*` 后 `./svc.sh stop && ./svc.sh start`；`crontab -e` 删除 `gha-runner-maintenance` 两行
- 验证：
  - Data 盘约 **62% / Avail 712Gi**（1.8T）
  - 四 `Runner.Listener` Started；GitHub `mac-mini-sonar-1..4` online
  - 日志：`~/Library/Logs/gha-runner-maintenance.log`
- 关联：`docs/runbooks/ci-runner-pools.md`；仓库 `scripts/gha-runner-maintenance.sh`

## 2026-07-29 09:27 CST - 恢复 mac-mini-sonar-1..4

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户要求启动本机 org runner。
- 影响：`mac-mini-sonar-1..4` 重新 online，可领取 `mac-mini-sonar` / `frontend-tests-ci` / `frontend-quality-ci` / `backend-ci` 等 job。
- 备份：无配置改动；沿用已有 LaunchAgent 与 `~/bin/mac-mini-runner-resume.sh`。
- 回滚 / 再次停止：
  ```bash
  for n in 1 2 3 4; do (cd ~/actions-runner/mac-mini-sonar-$n && ./svc.sh stop); done
  ```
- 做了什么：执行 `ssh mac-mini '~/bin/mac-mini-runner-resume.sh'`，四 slot 均为 Started；4 个 `Runner.Listener` 在跑。
- 验证结果：
  - 本机：`svc.sh status` → Started（PID 47565 / 47582 / 47599 / 47616）
  - GitHub API：`mac-mini-sonar-1..4` 均为 `online`；其中 `mac-mini-sonar-2` 已 busy
- 启停 runbook：`docs/runbooks/mac-mini-runner-start-stop.md`

## 2026-07-28 19:37 CST - 临时停止 mac-mini-sonar-1..4（用户占用主机）

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户需要本机桌面使用，要求暂停 org runner。
- 影响：`mac-mini-sonar-1..4` 离线，不再领取 `mac-mini-sonar` / `frontend-tests-ci` / `frontend-quality-ci` / `backend-ci` 等 job；匹配任务会落到 lemon-imac / umacbook-pro / mas-go-dev（按 label）。**未** disable LaunchAgent，仅 `svc.sh stop`。
- 备份：无配置改动；plist 与 runner 目录完整保留。
- 回滚 / 手动恢复：
  ```bash
  ssh mac-mini '~/bin/mac-mini-runner-resume.sh'
  # 或
  for n in 1 2 3 4; do (cd ~/actions-runner/mac-mini-sonar-$n && ./svc.sh start); done
  ```
- 做了什么：确认无 `Runner.Worker` 后，对 `mac-mini-sonar-1..4` 依次 `./svc.sh stop`（均为 Stopped）；`ps` 无 Listener/Worker。
- 验证结果：本机四 slot status Stopped。GitHub online→offline 可能延迟数分钟。
- 启停 runbook：`docs/runbooks/mac-mini-runner-start-stop.md`

## 2026-07-28 18:36 CST - 恢复 mac-mini-sonar-1..4；确认 `at` 定时未生效

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户 13:01 用 `at` 预约 16:01 自动恢复，到点未执行；手动恢复并落盘教训。
- 影响：四 slot 重新 online；安装固定脚本 `~/bin/mac-mini-runner-resume.sh`（日志 `~/Library/Logs/mac-mini-runner-resume.log`）；取消残留 `at` job。
- 根因：macOS 默认 **`com.apple.atrun` Disabled**，`at` 只入队不执行；另 `svc.sh` 必须 `cd` 到 runner 根再调用。
- 做了什么：
  1. 对 `mac-mini-sonar-1..4` 分别 `cd` + `./svc.sh start` → Started；4 个 `Runner.Listener` 在跑。
  2. GitHub API：`mac-mini-sonar-1..4` 均为 `online`。
  3. 写入 `~/bin/mac-mini-runner-resume.sh`；`atrm` 清理 job。
- 文档：
  - 取证：`docs/solutions/mac-mini/workflow-issues/macos-at-disabled-do-not-schedule-runner-resume-with-at-2026-07-28.md`
  - 启停 runbook：`docs/runbooks/mac-mini-runner-start-stop.md`
- **红线**：以后定时恢复 runner **不要用 `at`**，用 crontab / launchd。

## 2026-07-28 13:18 CST - 只读：确认 `com.apple.Virtualization.VirtualMachine` 归属

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户点名进程 `com.apple.Virtualization.VirtualMachine`，怀疑是某个 App 的虚拟机。
- 影响：无变更。
- 结论：该进程是 **Apple Virtualization.framework 的 XPC 服务**，当前唯一客户端是 **Docker Desktop**（不是 UTM / VMware / 独立 Win 虚机）。
- 证据：
  - PID **1495**（自 7/21 起常驻，约 8% 内存 / ~2.6GiB RSS）：路径 `.../Virtualization.framework/.../com.apple.Virtualization.VirtualMachine`
  - `lsof` 打开：`Docker.app/.../linuxkit/kernel`、`desktop.img`、`~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`（逻辑上限约 926G，实际占用约 **172G**）、Rosetta for Linux
  - 配对进程 PID **1463** `com.docker.virtualization`：`--cpus 8 --memoryMiB 24576`，父进程为 `com.docker.backend`
- 用途：给 Docker 容器提供 Linux 内核环境；关 Docker Desktop 后该 VirtualMachine 进程应随之退出。

## 2026-07-28 13:10 CST - 只读排查：本机「虚拟机程序」用途

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户忘记本机虚拟机相关程序在做什么，要求确认用途。
- 影响：无变更。
- 发现：
  1. **VMware Fusion** + 虚机 `~/虚拟机/Windows 11 x64.vmwarevm`：本意跑 Windows 11（挂载 `Nano 11 （Chinese）.iso`）以使用仅 Windows 软件；共享目录 `~/虚拟机/虚拟机共享` 含通达信、能旺 ERP、杏雨梨云、Maycad、钱包/回单等。**当前未运行**。磁盘仅 ~8.5MB（空稀疏盘，未装成系统）；最近一次开机（2026-01-31）失败，错误为 **x86 虚机与 Arm 主机不兼容**（Apple Silicon Mac mini）。ISO 已不在 `Downloads`。
  2. **Docker Desktop**（`com.docker.virtualization` LinuxKit 虚机）：常驻，8 vCPU / 24GiB；承载 SonarQube、AcquiLang Postgres、cypresso-okr、richer Grafana/Postgres 等 compose 服务。活动名单进程即 `com.apple.Virtualization.VirtualMachine`（见上条）。
- 验证：`vmrun list` → 0 running；`docker ps` 见 sonarqube / acquilang / okr / richer 等 Up。

## 2026-07-28 13:01 CST - 临时停止 mac-mini-sonar-1..4（用户占用主机，约 3 小时）

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户需要本机桌面使用，要求暂停 org runner 约 3 小时。
- 影响：`mac-mini-sonar-1..4` 离线，不再领取 `mac-mini-sonar` / `frontend-tests-ci` / `frontend-quality-ci` / `backend-ci` 等 job；匹配任务会落到 lemon-imac / umacbook-pro / mas-go-dev（按 label）。**未** disable LaunchAgent，仅 `svc.sh stop`。
- 备份：无配置改动；plist 与 runner 目录完整保留。
- 回滚 / 手动提前恢复：
  ```bash
  # 推荐（固定脚本，见 18:36 条目）
  ~/bin/mac-mini-runner-resume.sh
  # 或
  for n in 1 2 3 4; do cd ~/actions-runner/mac-mini-sonar-$n && ./svc.sh start; done
  ```
- 做了什么：
  1. 确认无 `Runner.Worker` 后，对 `mac-mini-sonar-1..4` 依次 `./svc.sh stop`（均为 Stopped）；`ps` 无 Listener/Worker。
  2. 写入 `/tmp/mac-mini-runner-resume.sh`，用 `at now + 3 hours` 预约 **2026-07-28 16:01 CST** 自动 `svc.sh start` 四 slot；日志 `/tmp/mac-mini-runner-resume.log`；`atq` job **1**。
- 验证结果：本机四 slot status Stopped；`atq` 显示 job 1 @ 16:01。GitHub online→offline 可能延迟数分钟。
- **事后**：16:01 **未执行**——macOS 默认禁用 `atrun`。见当日 18:36 恢复条目与 `docs/solutions/mac-mini/workflow-issues/macos-at-disabled-do-not-schedule-runner-resume-with-at-2026-07-28.md`。

## 2026-07-23 18:55 CST - 只读：go-build 近空，无清理（CYP-1547 全池核对）

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：A+B 实施前四机复测；mac-mini 四 slot `cache/go-build` 各 **8.0K**（仅 trim 元数据），盘 Avail **~552Gi**，**无同样膨胀**。
- 影响：无变更；策略文档统一为 2 天修剪 + coverage job-local GOCACHE。
- 验证：四 Listener Started；当时有 Worker（承接 CI），未动 cache。
- 关联：**CYP-1547**

## 2026-07-21 12:24 CST - 恢复 mac-mini-sonar-1..4

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：lemon/umac 已完成 Spotlight 隐私排除验证；用户要求恢复 mac-mini runner，结束临时分流。
- 影响：四 slot 重新 online，可再领取 `mac-mini-sonar` / `frontend-tests-ci` / `frontend-quality-ci` / `backend-ci` 等匹配 job。
- 备份：无配置改动。
- 回滚：`for n in 1 2 3 4; do cd ~/actions-runner/mac-mini-sonar-$n && ./svc.sh stop; done`
- 做了什么：对 `mac-mini-sonar-1..4` 依次 `./svc.sh start`；本机均为 Started，4 个 `Runner.Listener` 在跑。
- 验证结果：本机 status Started；GitHub API 见同条后续确认 online。

## 2026-07-21 10:55 CST - 临时停止 mac-mini-sonar-1..4（分流 CI 到 lemon/umac）

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：排查 lemon-imac / umacbook-pro 上是否同样有 Spotlight/`fseventsd` 问题；需让用户重跑的 Frontend Tests 落到那两台，避免继续被 mac-mini 抢走。
- 影响：本机 4 个 org runner 离线，不再领取 `frontend-tests-ci` / `frontend-quality-ci` / `backend-ci` / `mac-mini-sonar` 等 job；队列会落到 lemon-imac / umacbook-pro / mas-go-dev（按 label 匹配）。**未** `disable` LaunchAgent（仍为 enabled），仅 `svc.sh stop`。
- 备份：无配置改动；plist 与 runner 目录完整保留。
- 回滚方式：四 slot 分别 `cd ~/actions-runner/mac-mini-sonar-N && ./svc.sh start`（N=1..4），或登录会话内 `launchctl bootstrap gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-N.plist`。
- 做了什么：
  1. 确认无 `Runner.Worker` 后，对 `mac-mini-sonar-1..4` 依次执行 `./svc.sh stop`（均 Reported Stopped）。
  2. 本机 `ps` 无 Listener/Worker；`./svc.sh status` 均为 Stopped。
- 验证结果：本机服务已停。GitHub API 可能延迟数分钟才从 online→offline（stop 后立即查时部分 slot 仍显示 online）。
- 备注：lemon / umac 基线见同日 `docs/operations/lemon-imac.md` / `umacbook-pro.md`——两机 **Spotlight 仍为 Indexing enabled**，空闲/半忙时已有 `mds`/`mds_stores`/`mdworker` 占 CPU。

## 2026-07-21 10:44 CST - 只读：四 slot 全忙 Frontend Tests 时 fseventsd

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户要求再看一眼；本轮本机 4 个 `mac-mini-sonar-*` 全部 busy。
- 影响：无变更。
- 做了什么：进程快照 + 45s/2s 采样 load / fseventsd / mds / vitest forks；Worker 日志核对 Install 耗时。
- 当时状态（10:44–10:45 CST）：
  - **4 Worker** 同时跑 `Frontend Tests`：s1=3/4、s2=1/4、s3=2/4、s4=3/4（两 run 重叠可见双份 3/4）。
  - 均为 `vitest run --maxWorkers=2` → 合计 **4 vitest + 8 forks**；node 族 CPU 合计约 **770–890%**；load **9.5–11.2**（10 核满载）。
  - **fseventsd：45s 内几乎全程 0.0%**（偶见 0.2–0.6）；**mds 多数 0**，偶见 ~2%。
  - **npm ci**（本轮 4 路重叠安装，02:42:32–02:43:00 UTC）：s1 **17.6s**、s2 **16.2s**、s3 **16.7s**、s4 **9.2s**（并发写盘略慢于单路 7–12s，仍属热 cache）。
- 验证结果：即使 **4 shard 同机 Vitest 满载**，在已禁用 Spotlight 的前提下 **fseventsd 不再是 CPU 瓶颈**；瓶颈是 **node/vitest 本身**。昨天截图里 fseventsd ~98% 更可能是未关索引前或别的写盘洪峰场景，与当前配置下的稳态不同。
- 回滚方式：无。

## 2026-07-21 10:39 CST - 只读：用户重跑 job 后二次采样 fseventsd

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户重启若干 CI job，要求再核对 fseventsd / npm ci / vitest。
- 影响：无变更。
- 做了什么：90s 间隔 3s 采样 load / Worker / node 合计 CPU / fseventsd / mds；读四 slot 最新 Worker 日志的 Install 耗时；对照 GitHub runner busy 与 `iCare-frontend-mas` 进行中的 Sonar run。
- 当时状态（10:39–10:41 CST）：
  - 本机仅 **`mac-mini-sonar-3` busy**，跑 `Frontend Tests 1/4`（PR CYP-1428 / run 侧 in_progress；同 run 其它 shard 落在共享池其它机器）。
  - 命令：`vitest run ... --maxWorkers=2 --shard=1/4`（run-once）。
  - **npm ci**：slot3 本轮 **7.06s** exit 0；slot1 重跑 **10.79s** 后 job **Canceled**；slot2 上一次为 Sonar 路径 Checkout 失败后 Install 异常（exit 127），**Failed**。
  - **90s 内 fseventsd 全程 ~0.0%**；mds 偶发尖峰 23% / 8.7% / 4.5%，多数采样 0。
  - load ~3.0–3.4；Vitest 两 worker 合计约 200–250% CPU 属正常。
- 验证结果：重跑后仍看不到「fseventsd 吃满」；热 `npm ci` 更短（7–11s）。本机此轮并发只有 1 个 frontend test job，**未形成多 slot 同时解压** 的最坏写盘窗口。
- 回滚方式：无。

## 2026-07-21 10:30 CST - 只读：CI 运行中核对 fseventsd/mds 与 npm ci / vitest

- 服务器：`mac-mini`
- 操作人：`Grok`（只读排查）
- 原因：用户已排除 Spotlight 整盘索引后 mds 基本消失，但仍关心 fseventsd；需在 runner 实际跑 job 时核对 prefer-offline 与 `vitest run` 是否生效。
- 影响：无变更（只读）。
- 做了什么：
  1. SSH 采样进程 / load / 内存 / 磁盘 / `~/.npm` / 四 slot workFolder。
  2. 从 `mac-mini-sonar-2/3` 当前 Worker 日志读 `Install Dependencies` 耗时。
  3. `mdutil -s` 确认索引状态；`mdfind` 在 `~/gha` 下无 node_modules 索引命中。
- 当时状态（约 10:30 CST）：
  - 主机 uptime ~1h37m（当日早些时候重启过）；load ~5.5–5.8（10 核）。
  - 4 个 Listener 在线；**仅 slot2 + slot3 有 Worker**（Frontend Tests `shard=1/4` 与 `3/4`）。
  - 实测命令：`vitest run ... --maxWorkers=2 --shard=N/4`（run-once，非 watch）。
  - **npm ci**：两 slot 均 `npm ci --prefer-offline --no-audit --fund=false`，elapsed **~12.0–12.3s**，exit 0 → 本机 `~/.npm` 热缓存生效。
  - **fseventsd / mds**：Vitest 阶段连续采样 **~0% CPU**（对比用户昨日截图 fseventsd ~98% 的峰值场景；本次未撞上双 slot 同时 `npm ci` 的写盘洪峰窗口，install 已在 10:25 结束）。
  - Spotlight：`mdutil` 显示 `/` 与 Data 卷 **Indexing and searching disabled**。
  - `~/.npm` **9.5G**（`_cacache` 8.2G）；各 slot `node_modules` ~777–783M；workdir `~/gha/s1..s4` 各约 2.3G。
  - Data 卷 1.8T 已用 1.3T / 可用 468G（75%）。
- 验证结果：与 frontend-mas 配置一致——prefer-offline 热路径约 12s；CI 为 `vitest run`；mds 已压住；**当前 Vitest 中 fseventsd 不占 CPU**。若仍见 fseventsd 飙高，更可能集中在 **多 slot 并发 `npm ci` 解压** 或 4 shard 同时写盘，而非 Vitest watch。
- 回滚方式：无（只读）。

## 2026-07-20 19:48 CST - CI 缓存基线：共享 GOMODCACHE + 修剪 per-slot go-build

- 服务器：`mac-mini`
- 操作人：`Grok`（ce-work U4）
- 原因：四 slot 各有一份 ~1.5G `GOMODCACHE` 重复；go-build 单 slot 已 21–28GB。
- 影响：
  - 种子 `~/gha/cache/go-mod`（自 slot1 rsync），四 slot `.env` 的 `GOMODCACHE` 统一指向该路径；`GOCACHE` 仍 per-slot。
  - 对四 slot 执行 `go clean -cache`（阈值 >20GB），go-build 清空后靠 job 回填。
  - 重启 `mac-mini-sonar-1..4`。
  - 清理 login 用户闲置 `~/Library/Caches/go-build`（~3.4G）。
- 备份：`~/actions-runner/mac-mini-sonar-*/.env.bak.*`
- 回滚：还原 `.env.bak`（旧 per-slot go-mod 目录可能仍在但权限杂乱，优先用共享路径）。
- 验证：四 slot `GOMODCACHE` 相同、`GOCACHE` 各异；LaunchAgent Started。
- 参考：`docs/plans/2026-07-20-001-ops-ci-runner-cache-baseline-plan.md`

## 2026-07-20 13:45 CST - CI 池：加入 frontend-quality-ci（重活仍钉 mac-mini-sonar）

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：统一 PR 质量池与测试分片池；Coverage / 完整 Sonar 仍仅 32GB 本机。
- 影响：`mac-mini-sonar-1..4`（id 22–25）追加 `frontend-quality-ci`；保留 `frontend-tests-ci` / `backend-ci` / `mac-mini-sonar`。
- 回滚：`gh api -X DELETE orgs/cypressoai/actions/runners/{22..25}/labels/frontend-quality-ci`
- 参考：`docs/runbooks/ci-runner-pools.md`



## 2026-07-09 00:10 CST - 收敛 frontend-mas CI 队列吞吐到 mac-only 四 runner

- 原因：继续优化 `iCare-frontend-mas` `SonarQube Analysis` 的整体队列吞吐，指标改为同一配置下并发触发两条 PR run 后折算的 `SonarQube Analysis/hour`，重点优化 `Frontend Tests` 阶段而不是单条 run 的最短耗时。
- 影响：
  - `mac-mini` 最终保留 `mac-mini-sonar-1..4` 四个 GitHub Actions runner 在线。
  - `frontend-mas` 最终候选配置：`Frontend Tests` 4 shards，全部跑 `[mac-mini-sonar, frontend-tests-ci, macos, arm64]`，每 shard `VITEST_MAX_WORKERS=2`，即 mac-mini 总 Vitest workers=8。
  - `lemon-imac` / `lemon-imac-2` 不参与最终 `Frontend Tests` shard；保留其 runner 在线但不在最终 workflow 中引用。
  - 前端分支 `optimize/CYP-1246-frontend-ci-queue` / `optimize/CYP-1246-frontend-ci-queue-b` 均推送到最终 commit `122e7088`，用于 PR 双跑验证。
- 回滚方式：
  - 如需回到双 runner 四 worker方案：`launchctl disable gui/501/actions.runner.cypressoai.mac-mini-sonar-{3,4}` 后 `launchctl bootout gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-{3,4}.plist`，并把 workflow 的 `VITEST_MAX_WORKERS` 改回 `4`。
  - 如需恢复 lemon 混合实验：把 workflow 拆成 mac shards `1..4/6`（`VITEST_MAX_WORKERS=2`）和 lemon shards `5..6/6`（`VITEST_MAX_WORKERS=1`）。
- 做了什么：
  - 复测 mac-only 4 runner × 2 workers × 4 shards：run `28948596797` / `28948599595` 双绿，吞吐 `7.045/h`。
  - 测试 mac-only 4 runner × 2 workers × 8 shards：首次 run `28949983957` / `28949988495` 一绿一红；修复 `BenefitPlanCreateInnerIllnessLimitsDrawer.test.tsx` 高负载等待边界后，run `28951878491` / `28951882286` 双绿但吞吐仅 `6.44/h`，低于 4 shards。
  - 复测 mac-only 4 shards 最新状态：run `28953384903` / `28953388341` 双绿，吞吐 `6.723/h`。
  - 测试 mac + lemon 混合 6 shards：run `28954798224` / `28954802865` 双绿，吞吐 `6.642/h`；`lemon-imac` 的 `5/6` shard 两次约 12 分钟，形成长尾。
  - 最终回到 mac-only 4 shards 并验证：run `28956235734` / `28956241233` 双绿，批次窗口 1005 秒，吞吐 `7.164 SonarQube Analysis/hour`。
- 验证结果：
  - `mac-mini` `launchctl list` 显示 `actions.runner.cypressoai.mac-mini-sonar-1..4` 均在线；`launchctl print-disabled gui/501` 显示四个 service 均 enabled。
  - GitHub runner API 显示 `mac-mini-sonar-1..4`、`lemon-imac`、`lemon-imac-2` 均 online 且空闲。
  - 最终 workflow 校验 `npm run check:ci-workflows` 通过。
  - 最终结论：当前最高实测方案是 `mac-mini 4 runner × 每 shard 2 workers × 4 shards`。8 shards 单条 run 可更快，但 GitHub 调度会优先消化同一 run 的剩余 shards，B run 等待变长；lemon 混合池能让 B 更早起跑，但 8GB lemon shard 长尾抵消收益。

## 2026-07-08 21:58 CST - 验证 frontend-mas CI 双 runner 四 worker 吞吐

- 原因：用户希望以“60 分钟内完成多少个 `SonarQube Analysis`”作为 CI 配置优劣指标，并要求同一方案至少同时触发两条 `SonarQube Analysis`，验证真实队列吞吐；目标配置为 `mac-mini` 2 个 runner，每个 frontend test shard 使用 `maxWorkers=4`，总计 8 个 Vitest worker。
- 影响：
  - `mac-mini` 保持仅 `mac-mini-sonar-1`、`mac-mini-sonar-2` 在线，`mac-mini-sonar-3`、`mac-mini-sonar-4` 继续禁用。
  - `frontend-mas` 分支 `optimize/CYP-1246-frontend-ci-queue` 和 `optimize/CYP-1246-frontend-ci-queue-b` 均推送到 commit `48c4d457`，用于并发触发 PR CI。
  - workflow 目标状态为 4 个 frontend test shard 跑在 `[mac-mini-sonar, frontend-tests-ci, macos, arm64]`，`VITEST_MAX_WORKERS=4`。
- 回滚方式：
  - runner 侧如需恢复 4 runner 并发，执行 `launchctl enable gui/501/actions.runner.cypressoai.mac-mini-sonar-{3,4}`，再 `launchctl bootstrap gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-{3,4}.plist` 或 `launchctl kickstart -k`。
  - 仓库侧可把 `frontend-mas/.github/workflows/sonar.yml` 回滚到前一版 shard/worker 配置，或恢复到仅按 `[frontend-tests-ci, macos, arm64]` 调度。
- 做了什么：
  - 修复两处高负载下暴露的测试 flaky：LOA diagnosis drawer 延迟 open callback 清空草稿，以及 Inner/Illness Limits drawer 提交前 AntD Form/useWatch 状态尚未同步。
  - 本地验证 `BenefitPlanCreateInnerIllnessLimitsDrawer.test.tsx` 单文件 7 个测试通过；`VITEST_MAX_WORKERS=4 npm run test:ci -- --shard=2/4` 通过，247 个文件、1579 个测试通过。
  - 顺序推送两个 PR 分支，触发并发 run `28947113047` 和 `28947119750`。
- 验证结果：
  - `mac-mini` 本机 `launchctl list` 仅显示 `actions.runner.cypressoai.mac-mini-sonar-1`、`actions.runner.cypressoai.mac-mini-sonar-2`；`launchctl print-disabled gui/501` 显示 runner3/4 为 disabled。
  - run `28947113047` 成功：A run 创建于 `2026-07-08T13:39:47Z`，完成于 `13:49:57Z`。
  - run `28947119750` 成功：B run 创建于 `2026-07-08T13:39:54Z`，完成于 `13:57:21Z`。
  - 双 run 批次窗口 1055 秒，折算吞吐为 `6.825 SonarQube Analysis/hour`；8 个 frontend shard 全部成功，`frontend_test_step_sum_seconds=1436`，最大 frontend job 排队 864 秒。
  - 队列行为符合预期：A run 先占用两个 mac-mini frontend runner，A 释放 slot 后 B 的 shard 无缝接上；B 初期 queued 不是 runner 卡死，而是双 runner 容量限制下的正常排队。

## 2026-07-08 18:09 CST - 收敛 frontend-mas CI 到 mac-mini 双 runner

- 原因：排查 `iCare-frontend-mas` PR #1036 的 `Frontend Tests` flaky。失败 run 中 `frontend-tests-ci` 同时调度到 `lemon-imac`、`lemon-imac-2`、`mac-mini-sonar-1..2`，而 `lemon-imac` 只有 8GB 内存；在 `maxWorkers=4` 下 jsdom/AntD 测试明显变慢并触发默认 `waitFor/findBy` 1s 等待边界，出现断言/元素查找 flaky。
- 影响：
  - `mac-mini` 仅保留 `mac-mini-sonar-1`、`mac-mini-sonar-2` 两个 GitHub Actions runner 在线。
  - `mac-mini-sonar-3`、`mac-mini-sonar-4` 的 LaunchAgent 已 `disable` 并 `bootout`，不删除 runner 目录、不移除 GitHub runner 注册、不改 token。
  - `frontend-mas` 分支 `feature/CYP-1241-test-ci-maxworkers-6` 保留 PR frontend test 4 片，但让 shard 只匹配 `[mac-mini-sonar, frontend-tests-ci, macos, arm64]`，在两个在线 mac-mini runner 上分批执行，避免继续落到 `lemon-imac`；汇总 `Frontend Tests` job 改到 `mas-go-dev`，避免空 echo job 排队占 Mac runner。
- 备份：
  - 操作前 `launchctl print gui/501/actions.runner.cypressoai.mac-mini-sonar-{1,2,3,4}` 已读出当前 plist 路径、工作目录、stdout/stderr 路径和运行状态。
  - 操作前 GitHub API 显示 `mac-mini-sonar-1..4` 均为 `online` 且 `busy=false`，标签均包含 `mac-mini-sonar,macos,arm64,backend-ci,frontend-sonar-ci,frontend-tests-ci`。
- 回滚方式：
  - 重新启用 runner3/4：`launchctl enable gui/501/actions.runner.cypressoai.mac-mini-sonar-3`、`launchctl enable gui/501/actions.runner.cypressoai.mac-mini-sonar-4`。
  - 再拉起服务：`launchctl bootstrap gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-3.plist`、`launchctl bootstrap gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-4.plist`；如已加载但未运行，可用 `launchctl kickstart -k gui/501/actions.runner.cypressoai.mac-mini-sonar-3` 和 `-4`。
  - 仓库侧回滚：把 `frontend-mas/.github/workflows/sonar.yml` 的 frontend test runner 标签恢复为原 `[frontend-tests-ci, macos, arm64]`；如需恢复 4 个 mac-mini runner 同机并发，再启用 runner3/4。
- 做了什么：
  - 通过 GitHub run 日志确认失败 run `28932383075` 中 2/4 在 `mac-mini-sonar-2` 失败、4/4 在 `lemon-imac` 失败，失败点分别是 `BenefitPlanCreateInnerIllnessLimitsDrawer.test.tsx:246` 的 `saveMutate` 等待未满足、`SpecializationTemplatePage.test.tsx:220` 找不到 `Change` 按钮。
  - 本地在 `frontend-mas` 运行两个失败测试文件，`maxWorkers=4` 下 15 个测试全部通过；再运行 `npm run test:ci -- --shard=1/2`，489 个文件、3025 个测试通过。
  - 执行 `launchctl disable gui/501/actions.runner.cypressoai.mac-mini-sonar-{3,4}` 和对应 `launchctl bootout`，停用 runner3/4。
- 验证结果：
  - `mac-mini` 本机 `launchctl list` 仅剩 `actions.runner.cypressoai.mac-mini-sonar-1`、`actions.runner.cypressoai.mac-mini-sonar-2`。
  - `ps` 仅显示 runner1/2 的 `runsvc.sh` 与 `Runner.Listener`，无 runner3/4 进程。
  - `launchctl print-disabled gui/501` 显示 runner1/2 为 `enabled`，runner3/4 为 `disabled`。
  - GitHub API 显示 `mac-mini-sonar-1`、`mac-mini-sonar-2` 为 `online`，`mac-mini-sonar-3`、`mac-mini-sonar-4` 为 `offline`。
  - 最终验证 run `28935448141` 通过：`Frontend Tests 1/4..4/4`、`Typecheck`、`SonarQube Scan`、汇总 `Frontend Tests` 均为 `success`；实际测试 shard 使用 `--maxWorkers=4 --shard=N/4`，两个在线 mac-mini runner 分批执行。

## 2026-07-08 02:23 CST - 只读盘点 frontend-mas runner 本地缓存现状

- 原因：用户询问 frontend test runner 的缓存方案是在 workflow 侧还是 runner 侧配置，以及 `lemon-imac` 与 `mac-mini` 当前缓存现状。
- 影响：仅读取 workflow 配置和本机 runner 目录大小；未修改 runner、workflow、缓存目录或服务。
- 观察结果：
  - `frontend-mas/.github/workflows/sonar.yml` 未使用 `actions/cache`，`actions/setup-node` 未配置 `cache: npm`；依赖安装通过 `npm ci --prefer-offline --no-audit --fund=false` 使用本机 npm cache。
  - `mac-mini` 四个 runner slot 分别使用 `/Users/konghai/gha/s1..s4`，工作目录互相隔离。
  - 用户级 npm cache `/Users/konghai/.npm` 约 `9.5G`，由同一 macOS 用户下的四个 runner slot 共享。
  - 四个 slot 各自有独立 Node tool cache：`_tool/node/24.16.0/arm64`，每个 runner root 的 `_tool` 约 `730M`。
  - 四个 slot 的 `iCare-frontend-mas` workspace 各自保留 `.git` 约 `130-134M`；`s2..s4` 当前保留 `node_modules` 约 `755-765M`，`s1` 当前未见可统计的 `node_modules`。
- 结论：当前缓存主要是 self-hosted runner 的本机持久缓存，不是 GitHub 远端 cache；同机共享的是用户级 npm tarball cache，workspace / Node tool cache 仍按 runner slot 独立。

## 2026-07-08 01:22 CST - 为 mac-mini sonar runner 加入 frontend-tests-ci 共享测试池

- 原因：`frontend-mas` PR 的 `Frontend Tests` 是合并排队主要瓶颈。单纯把一个 PR 的测试拆到 `mac-mini` + `lemon-imac` 混合 6 片收益不稳定；新策略改为提升整体吞吐量：保留 4 片测试，但让 `mac-mini` 4 个 slot 与 `lemon-imac` 2 个 slot 共同接同一类 frontend test shard。
- 影响：
  - GitHub 组织 `cypressoai` 中 `mac-mini-sonar-1..4` 新增自定义标签 `frontend-tests-ci`。
  - `frontend-mas` PR 分支的 `sonar.yml` 已把 `Frontend Tests` shard job 和汇总 job 的 `runs-on` 改为 `[frontend-tests-ci, macos, arm64]`。
  - 未 SSH 登录 `mac-mini`，未修改本机 runner 文件，未重启 runner。
- 回滚方式：
  - 从 `mac-mini-sonar-1..4` 的 GitHub runner labels 中移除 `frontend-tests-ci`。
  - `frontend-mas/.github/workflows/sonar.yml` 恢复为 `[mac-mini-sonar, macos, arm64]`。
- 验证结果：
  - GitHub API 显示 `mac-mini-sonar-1..4` 均包含 `frontend-tests-ci`、`macos`、`arm64`。
  - `frontend-mas` workflow 校验通过：`npm run check:ci-workflows`、`actionlint -ignore 'label ".*" is unknown' .github/workflows/sonar.yml`、YAML parse。

## 2026-06-10 17:49 CST

- 原因：单 runner 串行化后 CI 队列大量积压，用户要求恢复 4 个 runner 并发以消化排队任务。
- 影响：`mac-mini-sonar-1..4` 全部重新在线，恢复同机最多 4 个 job 并发；重 CPU job 并发时会重新出现互相抢核的情况（见 17:05 审计）。`icare-sql-edge` 保持停止，本次未改动。
- 回滚方式：如需回到单 runner 串行化，分别在 `~/actions-runner/mac-mini-sonar-{2,3,4}` 执行 `./svc.sh stop`（停止前确认对应 slot 无 active `Runner.Worker`）。
- 做了什么：按 17:20 记录的回滚方式，在 `~/actions-runner/mac-mini-sonar-{2,3,4}` 依次执行 `./svc.sh start`，重新启动三个 launch agent；`mac-mini-sonar-1` 一直在线未动。
- 验证结果：`launchctl list` 显示 `actions.runner.cypressoai.mac-mini-sonar-1..4` 均为 Started（退出码 0）；`ps` 显示 4 个 `Runner.Listener` 全部运行，其中 runner1 已有 active `Runner.Worker` 在跑 job，2..4 listener 就绪等待领取排队任务。

## 2026-06-10 17:20 CST

- 原因：优化 `iCare-frontend-mas` PR CI 的 `Frontend Tests` 单 job 耗时。前一轮审计确认 4 个 `mac-mini-sonar-*` runner 可同机并发，重 CPU Vitest job 会互相抢核；用户决定牺牲少见的多 job 并发，优先让单 job 独占主机资源。同时用户确认 `icare-sql-edge` 已不重要，可以停止以释放内存。
- 影响：`mac-mini` 当前只保留 `mac-mini-sonar-1` 一个 GitHub Actions runner 在线；同一时间只会有一个匹配 `mac-mini-sonar` / `macos` / `arm64` 的 job 在该主机运行，其它 job 会排队。`icare-sql-edge` 容器已停止，且不会随 Docker Desktop / 主机重启自动拉起。未删除 runner 注册、runner 工作目录、tool cache、npm cache、容器或卷。
- 回滚方式：如需恢复 4 runner 并发，分别执行 `cd ~/actions-runner/mac-mini-sonar-2 && ./svc.sh start`、`cd ~/actions-runner/mac-mini-sonar-3 && ./svc.sh start`、`cd ~/actions-runner/mac-mini-sonar-4 && ./svc.sh start`。如需恢复 SQL Edge，执行 `docker update --restart=always icare-sql-edge && docker start icare-sql-edge`。
- 做了什么：预检时 `mac-mini-sonar-1` 正在跑一个既有 `iCare-frontend-mas` Vitest job，`mac-mini-sonar-2..4` 没有 active `Runner.Worker`；因此只停止 `2..4`，未打断正在 runner1 上执行的 job。
- 做了什么：在各 runner 目录执行 `./svc.sh stop`，停止 `mac-mini-sonar-2`、`mac-mini-sonar-3`、`mac-mini-sonar-4` 三个 launch agent。
- 做了什么：记录 `icare-sql-edge` 原状态为 `restart=always status=running`，执行 `docker update --restart=no icare-sql-edge` 后停止容器。
- 验证结果：`launchctl list` 仅显示 `actions.runner.cypressoai.mac-mini-sonar-1`；`ps` 仅显示 runner1 的 `Runner.Listener`，无 active `Runner.Worker` / `vitest` / `forks.js`；`docker inspect` 显示 `/icare-sql-edge restart=no status=exited`。停止后 `docker stats` 不再列出 `icare-sql-edge`，`sonarqube` 约占 `3.8GiB`；load average 从操作前约 `13.85 12.32 16.11` 逐步回落到约 `4.34 8.05 12.78`，swap 使用从约 `5290MiB` 小幅降到约 `5258MiB`。
- 后续建议：runner 侧已完成“单 runner 串行化”。前端仓的 `--maxWorkers` 是 `package.json` 中的脚本参数，不属于 runner 配置；建议前端项目侧先把 `test:ci` 从 `--maxWorkers=2` 提到 `8` 做 PR 验证，`10` 作为后续对照压测候选。若队列等待时间变得不可接受，再恢复 `2..4` 或改为专用 label 分流。

## 2026-06-10 17:05 CST

- 原因：评估 `iCare-frontend-mas` PR CI 中 `Frontend Tests` 耗时较长的问题，确认 self-hosted GitHub Actions runner 的并发模型和主机负载，以决定是否能安全提高 Vitest `--maxWorkers`。
- 影响：仅做只读 SSH 查询，未修改 runner、workflow、容器或系统配置；不影响正在运行的 CI。
- 回滚方式：无配置变更，无需回滚。如后续按建议调整 runner label / service，需要在执行前另行备份并确认。
- 做了什么：确认 `mac-mini` 当前只有 4 个 GitHub Actions runner service，分别为 `mac-mini-sonar-1..4`，均通过 `launchctl` 运行；对应 `workFolder` 分别为 `/Users/konghai/gha/s1..s4`。
- 做了什么：确认当前 4 个 runner slot 可并发执行 job。审计时 4 个 slot 同时在跑 `iCare-frontend-mas` 的 Vitest：每个 job 脚本为 `vitest run --reporter=dot --maxWorkers=2 --testTimeout=30000`，总计约 8 个 Vitest worker fork 同机并发。
- 做了什么：采样主机资源：`hw.ncpu=10`，其中性能核 4 个、能效核 6 个；审计时 load average 约 `32.49 25.26 18.97`，CPU `0.0% idle`，内存 `31G used`，swap 已使用约 `5.3G`。Docker Desktop VM 常驻运行，容器包括 `sonarqube`、`sonar-postgres`、`icare-sql-edge` 等，其中 `icare-sql-edge` 约占 `8.8GiB`，`sonarqube` 约占 `3.6GiB`。
- 验证结果：瓶颈不是 runner 空闲核心未被单 job 使用，而是 4 个独立 runner 允许同一台主机并发跑多个重 CPU 的 frontend test job。若不调整 runner / workflow 调度，安全的 `vitest --maxWorkers` 上限仍应保持 `2`；直接改为 `4` 会把最坏情况推到 `4 job × 4 workers = 16` 个 CPU 密集 worker，超过该机器实际可承受并发，容易让整体更慢或触发 Vitest watchdog。
- 后续建议：若目标是缩短单个 PR 的 `Frontend Tests` 延迟，应先做资源隔离，例如给 1 个 runner slot 增加专用 label（如 `mac-mini-frontend-test`）并让 frontend test job 只调度到该 label，再把 `--maxWorkers` 提到 `4`；其余 `mac-mini-sonar-*` slot 继续服务 SonarQube Scan / 轻量 job。若继续让 4 个 slot 都承接 frontend test job，则不建议提高 `--maxWorkers`。

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

- 验证结果：4 个 `Runner.Listener` 进程的实际 `PATH` 均包含 `/opt/homebrew/bin`；以各自进程 PATH 执行 `command -v gpg` 均返回 `/opt/homebrew/bin/gpg`，`gpg --version` 返回 `gpg (GnuPG) 2.5.18`；短路径下 `S.gpg-agent` 路径长度约 68；`launchctl list` 显示 `actions.runner.cypressoai.mac-mini-sonar-1..4` 均为 Started；`backend` PR SonarQube Scan 重跑成功；`frontend-mas` PR SonarQube PR Scan 重跑成功。后续抽样多个 PR run，4 个 slot 均已写入 `/Users/konghai/gha/s{1..4}/_tool/sonar-scanner-cli/8.1.0-build.6389/macosx-aarch64` 且有 `.complete` 标记；`mac-mini-sonar-1`、`2`、`4` 已在日志中出现 `Using cached Sonar Scanner CLI from:`，确认缓存命中；`mac-mini-sonar-3` 已完成冷下载和缓存写入，等待下一次同 slot Sonar job 观察二次命中。

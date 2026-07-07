# lemon-imac 运维操作时间线

## 2026-07-08 02:23 CST - 只读盘点 frontend-mas runner 本地缓存现状

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：用户询问 frontend test runner 的缓存方案是在 workflow 侧还是 runner 侧配置，以及 `lemon-imac` 与 `mac-mini` 当前缓存现状。
- 影响：仅读取 workflow 配置和本机 runner 目录大小；未修改 runner、workflow、缓存目录或服务。
- 观察结果：
  - `frontend-mas/.github/workflows/sonar.yml` 未使用 `actions/cache`，`actions/setup-node` 未配置 `cache: npm`；依赖安装通过 `npm ci --prefer-offline --no-audit --fund=false` 使用本机 npm cache。
  - `lemon-imac` 两个 runner slot 分别使用 `/Users/for-konghai/gha/li` 与 `/Users/for-konghai/gha/li2`，工作目录互相隔离。
  - 用户级 npm cache `/Users/for-konghai/.npm` 约 `184M`，由同一 macOS 用户下的两个 runner slot 共享。
  - 两个 slot 各自有独立 Node tool cache：`_tool/node/24.18.0/arm64`，各自约 `195M`。
  - 两个 slot 的 `iCare-frontend-mas` workspace 各自保留 `.git` 约 `29M`、`node_modules` 约 `752-754M`。
- 结论：当前缓存主要是 self-hosted runner 的本机持久缓存，不是 GitHub 远端 cache；同机共享的是用户级 npm tarball cache，workspace / Node tool cache 仍按 runner slot 独立。

## 2026-07-08 01:54 CST - 观察 frontend-tests-ci 共享池首次 4 分片调度效果

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：用户提供 `frontend-mas` workflow run `28886024783`，需要确认 4 个 `Frontend Tests` shard 被 `mac-mini` 与 `lemon-imac` 两台设备共同领取是否符合预期，并评估速度与缓存 / 网络流量影响。
- 影响：仅读取 GitHub Actions run 元数据和 job 日志；未修改 runner、workflow 或服务。
- 观察结果：
  - `Frontend Tests 4/4` 落到 `lemon-imac-2`，job 约 375 秒，其中 `npm ci` 约 14 秒、Vitest 约 327 秒。
  - `Frontend Tests 1/4`、`2/4`、`3/4` 分别落到 `mac-mini-sonar-4`、`mac-mini-sonar-1`、`mac-mini-sonar-2`。
  - 本轮从最早 job start 到 workflow failure 约 562 秒；失败点在 `Frontend Tests 2/4` 的 `CreateLoaModal.test.tsx` 偶发超时，发生于 `mac-mini-sonar-1`，不是 `lemon-imac` 环境错误。
  - `npm ci` 在各 shard 上约 11-15 秒，说明持久化 self-hosted runner 的本机 npm tarball cache 已经有效命中，依赖安装网络消耗不是当前最大信号。
- 结论：
  - 4 个 shard 被两台设备领取是共享 `frontend-tests-ci` label 后的预期行为；GitHub Actions 会把 matrix job 独立派发到任意满足 `[frontend-tests-ci, macos, arm64]` 的空闲 runner slot。
  - 共享池更适合降低多 PR 并发时的排队时间，不保证单个 PR 的 wall time 一定变短；单次耗时仍受最慢 shard 和 flaky test 影响。
  - 跨机器会降低缓存局部性：`mac-mini` 与 `lemon-imac` 不共享 git object cache、Node tool cache、npm cache 或工作目录。当前更值得优化的网络流量点是 `Frontend Tests` 的 `actions/checkout`，可考虑只让测试 job 使用 shallow fetch，并保留 Sonar job 的 `fetch-depth: 0`。

## 2026-07-08 01:22 CST - 为 lemon-imac runner 加入 frontend-tests-ci 共享测试池

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：用户明确目标是降低 3 个同事频繁开 PR 时的整体 CI 排队时间，而不是只优化单个 PR 的执行时间。精确表达“mac-mini 接任务则 4 片、lemon-imac 接任务则 2 片”不是 GitHub Actions 原生调度能力；改用共享 runner label 让两台机器都能接 `Frontend Tests` shard。
- 影响：
  - GitHub 组织 `cypressoai` 中 `lemon-imac` 与 `lemon-imac-2` 新增自定义标签 `frontend-tests-ci`。
  - `frontend-mas` PR 分支保留 4 片 `Frontend Tests`，但 `runs-on` 改为 `[frontend-tests-ci, macos, arm64]`，因此 4 个 shard 可被 `mac-mini-sonar-1..4` 或 `lemon-imac` / `lemon-imac-2` 任意空闲 slot 领取。
  - 未修改远端 runner 文件，未重启 iMac 或 runner 服务。
- 回滚方式：
  - 从 `lemon-imac` 与 `lemon-imac-2` 的 GitHub runner labels 中移除 `frontend-tests-ci`。
  - `frontend-mas/.github/workflows/sonar.yml` 恢复为 `[mac-mini-sonar, macos, arm64]`。
- 验证：
  - GitHub API 显示 `lemon-imac` 与 `lemon-imac-2` 均包含 `frontend-tests-ci`、`macos`、`arm64`。
  - `frontend-mas` workflow 校验通过：`npm run check:ci-workflows`、`actionlint -ignore 'label ".*" is unknown' .github/workflows/sonar.yml`、YAML parse。

## 2026-07-08 01:13 CST - 确认混合分片收益不足，frontend-mas 回退到 mac-mini 4 片

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：`frontend-mas` workflow run `28883967948` 合并 `VITEST_MAX_WORKERS=1` 后再次验证，用户反馈整体仍无明显改善，希望拆开 `lemon-imac` 与 `mac-mini` 的工作，不再混合切同一套测试分片。
- 影响：
  - 仅读取 GitHub Actions run 元数据并修改 `frontend-mas` PR 分支 workflow；未修改远端 runner、未重启服务。
  - `lemon-imac` 两个 runner slot 仍保留在线，可供后续单独 workflow / 独立 job 使用。
- 观察结果：
  - 本轮 run `completed/success`，按本轮最早 job start 到汇总 job complete 约 571 秒。
  - `Frontend Tests 5/6 (lemon-imac)`：job 约 555 秒，测试约 502 秒。
  - `Frontend Tests 6/6 (lemon-imac)`：job 约 315 秒，测试约 263 秒。
  - `Frontend Tests 3/6 (mac-mini)`：job 约 456 秒，测试约 387 秒。
  - `maxWorkers=1` 降低了 lemon 单 job 内并发，但显著拉长 lemon shard 耗时；收益不如保留默认 `maxWorkers=2`。
- 结论：
  - `lemon-imac` 与 `mac-mini` 混合分担同一个 Vitest shard 池收益不稳定，主要受异构机器性能、Vitest 文件级分片不均衡和每片重复安装/启动成本影响。
  - 已在 `frontend-mas` PR 分支把 `sonar.yml` 回退为 4 片：`Frontend Tests 1/4..4/4`，随后在 01:22 进一步改为通过 `[frontend-tests-ci, macos, arm64]` 共享 runner 池调度。
  - 已把 `package.json` 的 `test:ci` 恢复为固定 `--maxWorkers=2`，移除 `VITEST_MAX_WORKERS` 实验入口。
- 验证：
  - `npm run check:ci-workflows` 通过。
  - `actionlint -ignore 'label ".*" is unknown' .github/workflows/sonar.yml` 通过。
  - YAML 解析通过。

## 2026-07-08 00:47 CST - 只读排查 lemon shard 因重复 maxWorkers 参数失败

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：用户反馈 `frontend-mas` workflow run `28882843047` 中 `lemon-imac` 上的 `Frontend Tests 5/6` 和 `6/6` 直接失败。
- 影响：仅读取 GitHub Actions run 元数据、远端 runner `_diag` 日志和本地复现命令；未修改远端 runner、未重启服务。
- 结论：
  - 失败不是 runner 环境问题，而是 workflow 命令问题。
  - `package.json` 的 `test:ci` 已固定 `--maxWorkers=2`，workflow 额外追加 `--maxWorkers=1` 后，Vitest 收到两个值并立即报错：`Expected a single value for option "--maxWorkers <workers>", received [2, 1]`。
  - 在 `frontend-mas` PR 分支中已改为由 `VITEST_MAX_WORKERS` 环境变量控制，默认仍为 2，lemon shard 设置为 1，避免重复 CLI 参数。
- 验证：
  - `npm run check:ci-workflows` 通过。
  - `actionlint -ignore 'label ".*" is unknown' .github/workflows/sonar.yml` 通过。
  - 本地用 `VITEST_MAX_WORKERS=1 npm run test:ci -- --shard=6/6` 进入正常测试执行阶段，不再出现重复 `--maxWorkers` 解析错误；验证进程随后手动中断，未等待完整测试跑完。

## 2026-07-08 00:18 CST - 复测第二个 runner slot 对 frontend-mas 分片耗时的影响

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：新增 `lemon-imac-2` 后，用户重新允许 `frontend-mas` workflow run `28877788298`，需要观察两个 lemon shard 是否并发以及总耗时是否改善。
- 影响：仅读取 GitHub Actions run 元数据和远端系统状态；未修改 runner、workflow 或服务。
- 观察结果：
  - 重新跑的 workflow 最终 `completed/success`，按本轮最早 job start 到汇总 job complete 计算约 7 分 27 秒；上一轮单 lemon slot 约 9 分 36 秒。
  - `Frontend Tests 6/6 (lemon-imac)`：job 约 216 秒，测试约 163 秒。
  - `Frontend Tests 5/6 (lemon-imac)`：job 约 344 秒，测试约 291 秒。
  - `Frontend Tests 3/6 (mac-mini)` 仍是最慢 mac-mini shard：job 约 431 秒，测试约 365 秒。
  - 两个 lemon shard 这轮没有像上一轮那样串行排队；`lemon-imac-2` 在 `6/6` 完成后空闲，`lemon-imac` 继续跑较慢的 `5/6`。
- 远端状态：
  - 并发期间 `lemon-imac` load average 曾超过 20；测试后仍约 15。
  - 未见 swap in/out，但内存 compressor 使用明显，说明 8GB 内存下并发两个 Vitest job 有资源压力。
- 结论：
  - 第二个 runner slot 解决了 lemon 两片排队，但整体收益有限，主要瓶颈转为分片不均衡和机器资源竞争。
  - 继续增加 runner slot 不建议；下一步更应该优化分片策略或降低每个 job 的重复安装/启动成本。

## 2026-07-07 23:51 CST - 新增第二个 GitHub Actions runner slot

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：`frontend-mas` PR workflow 已把测试切成 6 片，其中 2 片调度到 `lemon-imac`；单 runner slot 会导致这 2 片串行排队，需要增加第二个 runner slot 做并发验证。
- 影响：
  - 新增 runner 目录：`/Users/for-konghai/actions-runner/lemon-imac-2`。
  - 新增短 work 目录：`/Users/for-konghai/gha/li2`。
  - 新增并启动 macOS LaunchAgent：`actions.runner.cypressoai.lemon-imac-2`，配置文件位于 `/Users/for-konghai/Library/LaunchAgents/actions.runner.cypressoai.lemon-imac-2.plist`。
  - GitHub 组织 `cypressoai` 新增 runner `lemon-imac-2`，runner group 为 `Default`。
  - `lemon-imac` 与 `lemon-imac-2` 共享标签：`self-hosted`、`macos`、`arm64`、`lemon-imac`、`macos-arm64`；现有 `runs-on: [self-hosted, lemon-imac]` 可同时匹配两个 slot。
  - 未安装 Docker，未修改既有 `lemon-imac` runner，未重启 iMac。
- 备份：
  - 新增安装，无既有文件需要备份。
  - 注册 token 仅在命令进程中临时使用，未写入文档或磁盘。
- 回滚方式：
  1. `cd /Users/for-konghai/actions-runner/lemon-imac-2 && ./svc.sh stop && ./svc.sh uninstall`
  2. 用 GitHub removal token 执行 `./config.sh remove --token <removal-token>`（token 可由 `gh api -X POST orgs/cypressoai/actions/runners/remove-token --jq .token` 获取）。
  3. 删除 `/Users/for-konghai/actions-runner/lemon-imac-2` 与 `/Users/for-konghai/gha/li2`。
- 变更时序：
  1. 预检确认远端不存在 `lemon-imac-2` 目录、work 目录、LaunchAgent 或 GitHub runner 记录。
  2. 复用现有 `lemon-imac` runner 目录内已下载的 `actions-runner-osx-arm64-2.335.1.tar.gz`，复制到新目录。
  3. 用 SHA-256 `e1a9bc7a3661e06fa0b129d15c2064fe65dc81a431001d8958a9db1409b73769` 校验通过后解压。
  4. 执行 `config.sh --unattended` 注册 runner，名称 `lemon-imac-2`、work folder `/Users/for-konghai/gha/li2`、标签与第一 slot 对齐。
  5. 执行 `svc.sh install` 与 `svc.sh start` 安装并启动 LaunchAgent。
- 验证：
  - GitHub API 显示 `lemon-imac` 与 `lemon-imac-2` 均为 `status=online`、`busy=false`、`os=macos`。
  - 两个 runner 的标签完全一致，均包含 `lemon-imac`。
  - 远端存在两个 `Runner.Listener run --startuptype service` 进程，分别来自 `lemon-imac` 与 `lemon-imac-2` 目录。
  - `lemon-imac-2` 日志显示 `Connected to GitHub`、`Current runner version: '2.335.1'`、`Listening for Jobs`。
- 后续：
  - 用下一轮 PR run 验证 `Frontend Tests 5/6` 与 `6/6` 是否同时落到两个 slot，以及 8GB 内存下并发是否实际缩短总时长。

## 2026-07-07 23:35 CST - 只读分析 frontend-mas PR 测试分片在 lemon-imac 上串行排队

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：用户反馈 `frontend-mas` SonarQube workflow 改成 6 片后，`lemon-imac` 只有 1 个 runner，两个 lemon shard 串行排队，整体可能更慢；需要只读确认瓶颈。
- 影响：仅读取 GitHub Actions run 元数据与远端系统状态；未新增 runner，未修改 workflow，未重启服务。
- 观察结果：
  - workflow run `28877788298` 最终 `completed/success`，总耗时约 9 分 36 秒。
  - `Frontend Tests 6/6 (lemon-imac)` 从 run 创建后约 6 秒开始，job 总耗时约 246 秒，其中测试约 130 秒。
  - `Frontend Tests 5/6 (lemon-imac)` 等待约 257 秒才开始，job 总耗时约 302 秒，其中测试约 259 秒。
  - mac-mini 四个 shard 并发开始，最慢的是 `Frontend Tests 3/6 (mac-mini)`，job 总耗时约 430 秒，其中测试约 356 秒。
  - 结论：当前新增的第 6 片没有真正并发，因为 `lemon-imac` 只有 1 个 runner slot；关键路径变成 lemon 两片串行，总体被拉到约 9.5 分钟。
- 远端状态：
  - `lemon-imac` 为 8 logical CPUs，内存 8GB。
  - 测试后系统无 swap in/out，但 compressor 使用明显；执行期间 load average 曾接近 19。
  - runner 仍为单实例 `actions.runner.cypressoai.lemon-imac`，状态正常。
- 后续建议：
  - 最稳妥的短期优化是改成 5 片：mac-mini 跑 1-4/5，lemon-imac 跑 5/5，避免 lemon 单 runner 上排队。
  - 若坚持 6 片，则需要给 `lemon-imac` 增加第二个 runner slot，但 8GB 内存下应先用一轮 PR 验证并发两个 Vitest job 是否真的变快，避免 CPU / 内存争用抵消收益。

## 2026-07-07 22:51 CST - 配置裸跑 macOS ARM GitHub Actions runner

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：将新增 iMac 接入 `cypressoai` GitHub Actions 组织级 self-hosted runner，用于后续按标签调度 macOS ARM 任务。
- 影响：
  - 新增 runner 目录：`/Users/for-konghai/actions-runner/lemon-imac`。
  - 新增短 work 目录：`/Users/for-konghai/gha/li`，避免 macOS 上部分工具因 runner 临时目录路径过长出问题。
  - 新增并启动 macOS LaunchAgent：`actions.runner.cypressoai.lemon-imac`，配置文件位于 `/Users/for-konghai/Library/LaunchAgents/actions.runner.cypressoai.lemon-imac.plist`。
  - runner 注册到 GitHub 组织 `cypressoai` 的 `Default` runner group，名称 `lemon-imac`，标签为 `self-hosted`、`macos`、`arm64`、`lemon-imac`、`macos-arm64`。
  - 未安装 Docker；该 runner 当前为裸跑模式。没有 `docker`、`backend-ci`、`frontend-sonar-ci` 标签，不会承接依赖这些标签的现有 job。
- 备份：
  - 新增安装，无既有 runner 文件需要备份。
  - GitHub 注册 token 仅在本次命令中临时使用，未写入文档或磁盘。
- 回滚方式：
  1. `cd /Users/for-konghai/actions-runner/lemon-imac && ./svc.sh stop && ./svc.sh uninstall`
  2. 用 GitHub removal token 执行 `./config.sh remove --token <removal-token>`（token 可由 `gh api -X POST orgs/cypressoai/actions/runners/remove-token --jq .token` 获取）。
  3. 删除 `/Users/for-konghai/actions-runner/lemon-imac` 与 `/Users/for-konghai/gha/li`。
- 变更时序：
  1. 通过 GitHub API 确认组织 `cypressoai` 下没有同名 `lemon-imac` runner。
  2. 从官方 `actions/runner` release 下载 `actions-runner-osx-arm64-2.335.1.tar.gz`。
  3. 用 release 公布的 SHA-256 `e1a9bc7a3661e06fa0b129d15c2064fe65dc81a431001d8958a9db1409b73769` 校验通过后解压。
  4. 执行 `config.sh --unattended` 注册 runner，指定 runner group `Default`、名称 `lemon-imac`、work folder `/Users/for-konghai/gha/li`。
  5. 执行 `svc.sh install` 与 `svc.sh start` 安装并启动 LaunchAgent。
- 验证：
  - `svc.sh status` 显示 `actions.runner.cypressoai.lemon-imac` 已启动。
  - 远端进程存在 `runsvc.sh` 与 `Runner.Listener run --startuptype service`。
  - runner 日志显示 `Connected to GitHub`、`Current runner version: '2.335.1'`、`Listening for Jobs`。
  - GitHub API 显示 `lemon-imac`：`status=online`、`busy=false`、`os=macos`、标签正确。
  - 当前 service PATH 为 `/usr/bin:/bin:/usr/sbin:/sbin`；`git`、`curl`、`tar`、`unzip`、`xcodebuild` 可用，`brew`、`node`、`npm`、`docker`、`dotnet`、`gpg` 暂不在 PATH。
- 后续：
  - 如需承接 frontend/backend Sonar 或构建任务，先补齐 Homebrew、Node/npm、GPG 等工具链，并更新 runner service 的 `.path`；验证后再加 `frontend-sonar-ci` / `backend-ci` 等共享标签。
  - 只有 workflow 用到 `container:`、`services:` 或 Docker 构建/运行时才需要安装 Docker；普通 shell、Node、Xcode、Go 等任务可以裸跑。

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

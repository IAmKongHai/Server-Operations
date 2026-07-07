# mac-mini 运维时间线

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

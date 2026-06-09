---
title: SonarQube Scanner CLI 因 4 段版本号导致 tool-cache 永不命中、每次 CI 重新下载
date: 2026-06-09
category: docs/solutions/mac-mini/integration-issues
server: mac-mini
module: iCare CI / GitHub Actions self-hosted runner (mac-mini-sonar-1..4)
problem_type: integration_issue
component: tooling
symptoms:
  - "每次 SonarQube Scan 都重新下载 Scanner CLI 7.2.0.5079（每份约 145M），浪费外网流量和时间"
  - "CI 日志永远是 'Sonar Scanner CLI cached to:'，从不出现 'Using cached Sonar Scanner CLI from:'"
  - "磁盘缓存目录存在且有 .complete 标记，但目录树 mtime 每次运行都被刷新成当次时间"
  - "pin 到上游修复 commit 后，Scanner CLI 8.1.0.6389 首次下载阶段报 'GPG is not available'"
  - "修复 PATH 后，GPG 能执行但仍可能因 runner _work/_temp 路径过深报 'File name too long' / 'gpg-agent: IPC connect call failed'"
root_cause: wrong_api
resolution_type: dependency_update
severity: medium
tags: [sonarqube, github-actions, tool-cache, semver, self-hosted-runner, mac-mini]
---

# SonarQube Scanner CLI 因 4 段版本号导致 tool-cache 永不命中、每次 CI 重新下载

## Problem

iCare 的 `backend` / `frontend-mas` 在 mac-mini self-hosted runner 上跑 SonarQube Scan 时，`SonarSource/sonarqube-scan-action@v6` 每次都重新下载约 145M 的 Scanner CLI 7.2.0.5079，浪费外网流量和构建时间。缓存目录明明存在，却从未被复用。

## Symptoms

- 每个 runner（`mac-mini-sonar-1..4`，runner v2.334.0）每次跑都重下，CI 日志恒为 `Installing Sonar Scanner CLI 7.2.0.5079 ...` + `Sonar Scanner CLI cached to: ...`。
- **从不出现** `Using cached Sonar Scanner CLI from: ...`（这才是命中标志）。
- 磁盘上 `_work/_tool/sonar-scanner-cli/7.2.0.5079/macosx-aarch64/` 存在、同级 `macosx-aarch64.complete` 标记也在，看起来"缓存已建立"。
- 但整个缓存目录树（`bin/conf/jre/lib`）的 mtime 每次运行都被刷新成当次时间 —— 证明每次都在重写，不是复用。

## What Didn't Work

- **怀疑 4 个 runner 不共享 tool cache**：每个 runner 有独立 `_work/_tool`，最初以为配 `AGENT_TOOLSDIRECTORY` 共享即可。但这只能省"首次 × 4"，救不了"同一 runner 每次都重下"，对真正根因无效。复查发现同一 runner 昨天下过、今天仍重下，直接推翻该假设。
- **怀疑 `_work` 被 job 清理**：核实 `_tool` 目录本身 mtime 停留在初次创建日期，没被整体清掉，只有版本子目录被刷新。排除。
- **怀疑 `toSemVer` 版本格式错配**（写入和查询用了不同 action 版本）：检查发现大家用的都是同一个已发布 tag v6.0.0，且 v6.0.0 的 `dist/index.js` 根本没有 `toSemVer` 函数。排除。

## Solution

把两个仓库 `.github/workflows/sonar.yml` 里的 action 从可变 tag `@v6` pin 到上游修复 commit 的完整 SHA：

```yaml
# 改前
uses: SonarSource/sonarqube-scan-action@v6

# 改后（pin 到 SQSCANGHA-135 修复 commit）
uses: SonarSource/sonarqube-scan-action@358113921641f7f7c0e0d1291c4177001d2a8aaf
```

- `backend/.github/workflows/sonar.yml`：1 处（SonarQube Scan）
- `frontend-mas/.github/workflows/sonar.yml`：2 处（PR Scan + Branch Scan）

该 commit（SQSCANGHA-135 "Fix scanner binaries always re-downloaded due to incompatible 4-part version" #250，2026-06-08 合入 master）用 `toSemVer` 把 4 段号 `7.2.0.5079` 转成合法 SemVer `7.2.0-build.5079` 再交给 tool-cache，使 `find()` 能正常命中。

**兼容性已确认**（升级后内置 Scanner 变为 8.1.0.6389）：

- Server 为 SonarQube Community Build v26.3.0.120487（= 日历版 2026.3）；Scanner CLI 8.1.0.6389 官方兼容 2026.3。
- Scanner CLI 8.x 内置 JRE 为 Java 21，正好对齐官方"2026.4（7 月）起 Scanner 强制 Java 21"的要求（旧 7.2.0.5079 内置 Java 17 是将被淘汰侧）。
- 8.0 / 8.1 changelog 均为基础设施维护（JRE、依赖、代理认证修复），**无**影响报告产出的 behavior change、无 breaking change。注意 v8.0.0 把 `skipSignatureVerification` 默认改为 `false`（默认开启 GPG 校验）。mac-mini 已安装 `gpg 2.5.18` + `dirmngr`，但 runner service 的 PATH 还需要显式暴露 Homebrew 目录，见下一节。

## Follow-up: GPG is not available

pin 到 `358113921641f7f7c0e0d1291c4177001d2a8aaf` 后，`backend` 和 `frontend-mas` 的 Sonar job 首次下载 Scanner CLI 8.1.0.6389 时失败：

```text
Error: Action failed: GPG is not available. Install GPG or set skipSignatureVerification: true
```

这不是 mac-mini 没装 GPG。SSH 登录 shell 里能看到：

```bash
command -v gpg
# /opt/homebrew/bin/gpg
gpg --version | head -n 1
# gpg (GnuPG) 2.5.18
```

真正问题是 4 个 GitHub Actions runner 以 launch agent service 方式运行，实际进程 PATH 来自各自 runner 目录下的 `.path`：

```text
/Users/konghai/.cargo/bin:/Users/konghai/.volta/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

这里没有 `/opt/homebrew/bin`。而上游 action 的签名校验只执行命令名 `gpg --version`，不会查 `/opt/homebrew/bin/gpg`，所以 CI 环境里找不到 GPG。

修复应落在 runner 全局环境，而不是在每个业务仓 workflow 里加 `GITHUB_PATH` workaround。

### Step 1: 暴露 Homebrew GPG 到 runner service PATH

按用户确认后的全局修法执行：

1. 备份 4 个 runner 的 `.path`：

```text
/Users/konghai/actions-runner/mac-mini-sonar-1/.path.bak.20260609-140142
/Users/konghai/actions-runner/mac-mini-sonar-2/.path.bak.20260609-140142
/Users/konghai/actions-runner/mac-mini-sonar-3/.path.bak.20260609-140142
/Users/konghai/actions-runner/mac-mini-sonar-4/.path.bak.20260609-140142
```

2. 把 4 个 `.path` 从：

```text
/Users/konghai/.cargo/bin:/Users/konghai/.volta/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

改为：

```text
/opt/homebrew/bin:/Users/konghai/.cargo/bin:/Users/konghai/.volta/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

3. 重启 4 个 runner service。重启前 `mac-mini-sonar-3` 有 `Runner.Worker` 正在跑，所以先重启空闲的 `1/2/4`，等 `3` 空闲后再重启，避免中断正在执行的 CI。

4. 验证 4 个 `Runner.Listener` 进程的实际 PATH 都包含 `/opt/homebrew/bin`，且以该 PATH 执行 `command -v gpg` 均返回 `/opt/homebrew/bin/gpg`。

### Step 2: 缩短 runner workFolder，避免 GnuPG socket 路径过长

PATH 修复后，`frontend-mas` 仍出现另一类 GPG 失败：

```text
gpg: can't connect to the gpg-agent: IPC connect call failed
Action failed: Failed to import SonarSource public key from all keyservers
```

进一步在 mac-mini 上复现发现，问题来自 Sonar action 用 `RUNNER_TEMP` 创建临时 `GNUPGHOME`。原默认路径形如：

```text
/Users/konghai/actions-runner/mac-mini-sonar-1/_work/_temp/gpg-home-1780986085108-41704/S.gpg-agent
```

该 socket 路径长度约 99，接近 macOS Unix domain socket 路径限制；同样的 `gpg --homedir ... --recv-keys` 在这个深路径下可复现 `File name too long` / IPC 失败，而放到短路径下返回 0。

最终继续在 runner 层修复：备份 4 个 runner 的 `.runner`，把 `workFolder` 从 `_work` 改到短路径：

```text
/Users/konghai/actions-runner/mac-mini-sonar-1/.runner.bak.20260609-142350 -> workFolder: /Users/konghai/gha/s1
/Users/konghai/actions-runner/mac-mini-sonar-2/.runner.bak.20260609-142350 -> workFolder: /Users/konghai/gha/s2
/Users/konghai/actions-runner/mac-mini-sonar-3/.runner.bak.20260609-142350 -> workFolder: /Users/konghai/gha/s3
/Users/konghai/actions-runner/mac-mini-sonar-4/.runner.bak.20260609-142350 -> workFolder: /Users/konghai/gha/s4
```

短路径下同类 socket 路径长度约 68：

```text
/Users/konghai/gha/s1/_temp/gpg-home-1780986085108-41704/S.gpg-agent
```

改完后重启 4 个 runner service。验证结果：

- `backend` PR SonarQube Scan 重跑成功，日志显示 `gpg` 从 `/opt/homebrew/bin/gpg` 执行，签名校验通过，Scanner CLI 缓存到 `8.1.0-build.6389`。
- `frontend-mas` PR SonarQube PR Scan 重跑成功；该 run 的 `Frontend Tests` 仍在跑时，Sonar job 已完成通过。

## Why This Works

根因在 `sonarqube-scan-action@v6.0.0` 的 `dist/index.js`：它用**原始 4 段版本号** `7.2.0.5079` 直接调 `@actions/tool-cache` 的 `tc.find(TOOLNAME, "7.2.0.5079", flavor)`。

`tool-cache` 的 `find()` 要求 SemVer 格式（`x.y.z`）：

1. `7.2.0.5079` 是 4 段，不是合法 SemVer → `isExplicitVersion()` 返回 `false`；
2. 于是进入 `findAllVersions()` + `evaluateVersions()` 的"范围匹配"分支；
3. 但磁盘目录名 `7.2.0.5079` 同样非法，`findAllVersions` 里的 `isExplicitVersion(child)` 也对它返回 `false`、**直接跳过、不计入候选**；
4. 匹配失败 → `versionSpec` 变空 → `find()` 返回空字符串 → action 判定"未缓存" → **每次重下**。

而写入路径用 `cacheDir()` → `_createToolPath()`，**不校验 SemVer**，所以能以 4 段名落盘成功 —— 这就是"缓存目录在、却永不命中"的完整机制。上游 `toSemVer` 修复把版本号转成 `7.2.0-build.5079`（合法 SemVer），读写两端格式一致，`find()` 才能命中。

## Prevention

- **诊断 tool-cache 是否命中，不要只看"缓存目录是否存在"**：要看 ① action 日志里有没有打出"命中"那句（如本例的 `Using cached ... from:`），② 缓存目录 mtime 是否每次被刷新（被刷新 = 实际在重写 = 没命中）。
- **4 段版本号（`x.y.z.build`，SonarScanner 这类工具常见）与 `@actions/tool-cache` 的 SemVer 要求不兼容**是个隐蔽坑：`cacheDir` 写得进、`find` 读不出。遇到"某工具每次 CI 重下"先怀疑版本号格式。
- **macOS self-hosted runner 的 service PATH 不等于 SSH 登录 shell PATH**：Homebrew 工具即使已安装在 `/opt/homebrew/bin`，后台 runner 也可能看不到。需要用 `ps eww -p <Runner.Listener PID>` 或 workflow 里 `command -v gpg` 验证 runner 实际环境。
- **macOS GnuPG 对临时 homedir 路径长度敏感**：Sonar action 会在 `RUNNER_TEMP` 下建 `gpg-home-*`，如果 runner `workFolder` 太深，`S.gpg-agent` / `S.dirmngr` socket 可能超过 macOS 限制。runner 放在长目录名下时，应把 `.runner` 的 `workFolder` 改到短路径。
- **验证生效标志**：合并后首次跑出现 `Installing Sonar Scanner CLI 8.1.0.6389` + `cached to:`（下载一次新版，正常）；**第二次同一 runner 跑出现 `Using cached Sonar Scanner CLI from:`** —— 此句首次出现即代表缓存终于命中。
- **后续维护**：当前是 pin 到 master 临时 commit。等 SonarSource 发布含 SQSCANGHA-135 的正式 release（预计 v8.2+）后，把三处升回稳定 tag。关注 https://github.com/SonarSource/sonarqube-scan-action/releases 。

## Related Issues

- 上游修复：[SonarSource/sonarqube-scan-action#250](https://github.com/SonarSource/sonarqube-scan-action/pull/250)（SQSCANGHA-135）
- 同属 mac-mini runner 流量优化主题：[../workflow-issues/github-actions-runner-vpn-traffic-optimization-2026-05-20.md](../workflow-issues/github-actions-runner-vpn-traffic-optimization-2026-05-20.md)
- SonarQube 服务迁移与配置背景：[../sonarqube-migrated-from-dev-cypresso-2026-05-13.md](../sonarqube-migrated-from-dev-cypresso-2026-05-13.md)、[./sonarqube-github-oauth-callback-after-migration-2026-05-13.md](./sonarqube-github-oauth-callback-after-migration-2026-05-13.md)

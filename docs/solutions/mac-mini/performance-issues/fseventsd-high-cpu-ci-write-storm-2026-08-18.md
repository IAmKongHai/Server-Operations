---
title: fseventsd 在本机 EAS / CI 写盘洪峰时占满 CPU
date: 2026-08-18
category: docs/solutions/mac-mini/performance-issues
server: mac-mini
module: mac-mini / FSEvents / Colima virtiofs / GitHub Actions
problem_type: performance_issue
component: tooling
symptoms:
  - "活动监视器里 fseventsd 瞬间占满一核甚至更高，load 跟着上去"
  - "CI 或 eas build --local 一结束，fseventsd 立刻回到 0%，不是常驻空转"
  - "Spotlight 已关、mds 接近 0，但 fseventsd 仍会在解压 / 编译窗口飙"
root_cause: resource_exhaustion
resolution_type: config_change
severity: medium
related_components:
  - fseventsd
  - colima-virtiofs
  - github-actions-runner
  - eas-local-ios
tags:
  - mac-mini
  - fseventsd
  - colima
  - virtiofs
  - eas
  - deriveddata
  - github-actions
---

# fseventsd 在本机 EAS / CI 写盘洪峰时占满 CPU

## Problem

`fseventsd` 是 macOS 的文件系统事件守护进程。它自己几乎不产生负载，但会把每个 create / unlink / rename 扇出给所有订阅者。构建本身在 **macOS 宿主**（`eas build --local` → 本机 Xcode / 本机 Android SDK，加上 runner 的 `pnpm`），**不在 Colima 容器里**。Colima 用 `virtiofs` 挂了整个 `/Users/konghai`，只是这些写盘的旁路订阅者，可能把 `fseventsd` 再抬一截。

这和 2026-07-21 那次 **Spotlight `mds` 索引** 不是同一条因果链。整卷索引已经关掉；现在的峰值发生在 job 的写盘窗口，job 一结束 CPU 归零。

## Symptoms

- `fseventsd` 在 CI / 本机构建期间飙到几十～近 100%，空闲采样连续为 0.0%，`TIME` 不再增长
- `mdutil -s /` 与 Data 卷是 `Indexing and searching disabled`，`mds` 合计接近 0
- 同期能数到大量新文件：`~/Library/Developer/Xcode/DerivedData`、`/private/var/folders/.../T/`（RN codegen）、`~/gha/s*` 的 `node_modules`
- Colima 当时只有 sonarqube / sub2api / richer 等常驻容器，没有构建容器；`colima.yaml` 的 `virtiofs` 挂了整个 `/Users/konghai`（另外还挂了 `/Users/hon`）

## What Didn't Work

- 只看 `top -l 1` 会得到 0%。macOS 第一次采样不可信，要用 `top -l 2` 或连续 `ps -o %cpu,time`。
- 把锅再扣给 Spotlight。索引关了之后 `mds` 不再是放大器；`fseventsd` 仍会在写盘洪峰里忙。
- 杀 `fseventsd`。launchd 会拉起来，洪峰还在就会再飙，还可能让 IDE / virtiofs 丢事件。

## Diagnosis

2026-08-18 16:16 CST 接到时 load 15 分钟均值 6.6，1 分钟已落到 2.x。对照 runner 日志：

| 时间 (CST) | 谁 | 写了什么 |
| --- | --- | --- |
| 16:01–16:09 | `mac-mini-mobile-1` Preview APK (local) | `~/gha/m1` + Android 构建树 |
| 16:09–16:17 | 同 slot Preview IPA (local)，`eas build --local` | DerivedData `iCare-*` + `/var/folders` codegen |
| ~16:14–16:15 | `mac-mini-sonar-1/2` Jest / pnpm | `~/gha/s2` 约 1.2 万个 `node_modules` 文件 |

约 20 分钟 mtime 计数：DerivedData **20849**、`/private/var/folders` **21215**、`~/gha` **12193**。这些路径都在 Colima 的 `/Users/konghai` virtiofs 下面（`/var/folders` 不在家目录，但仍走宿主 `fseventsd`）。

开机以来 `fseventsd` 累计约 32 分钟 CPU，和「整天反复本机 EAS + 多 slot 解压」相符，不是守护进程卡死。

## Solution

先把预期讲清楚：**Xcode / `pnpm` 自己那几万次 create 消不掉**，那段窗口 `fseventsd` 一定会干活。能彻底拿掉的是两层写放大：

1. Colima virtiofs 把整个 `/Users/konghai`、`/Users/hon` 挂进 VM（每个宿主写盘多一次扇出）
2. `eas build --local` 没清干净的工作树 + 堆积的 DerivedData（同一份工程写很多遍还留着）

### 做不到的

- 本机 `xcodebuild archive` 期间让 `fseventsd` 保持 0%
- 杀 `fseventsd`、关 FSEvents、再关一遍已经 disabled 的 Spotlight

### A. 收窄 Colima virtiofs（主方案，需重启 VM）

2026-08-18 实测：VM 里只有这两条 virtiofs：

- `/Users/konghai` → 整家目录
- `/Users/hon` → 整家目录

容器真正 bind 的宿主路径只有：

| 容器 | 需要的宿主路径 |
| --- | --- |
| sub2api / postgres / redis | `/Users/konghai/stacks/sub2api/{data,postgres_data,redis_data}` |
| sonarqube | `/Users/konghai/stacks/sonarqube/sonarqube-web` |
| richer-grafana | `/Users/hon/richer/deployments/grafana/{dashboards,provisioning}` |
| 其余 | named volume，在 `/mnt/lima-colima`，不走家目录 |

`~/.colima/default/colima.yaml` 改成：

```yaml
mounts:
  - location: /Users/konghai/stacks
    writable: true
  - location: /Users/hon/richer/deployments/grafana
    writable: true
```

然后 `colima restart`（sonarqube / sub2api / richer 会短暂停）。本机 lima.yaml 是 Colima 生成的，不要手改，restart 会重写。

**已于 2026-08-18 17:54 CST 执行。** 备份 `colima.yaml.bak.20260818-1754`。`findmnt` 只剩 `stacks` 与 grafana；7 个容器自动拉起，Sonar / sub2api / Grafana 健康检查通过。同日清掉 EAS 工作树 14G 和 11 个旧 `iCare-*` DerivedData（38G → 13G），日维护脚本已加隔夜 prune。

验证：

```bash
colima ssh -- findmnt -t virtiofs
# 只应看到 /Users/konghai/stacks 和 grafana 那条，不应再有整个 /Users/konghai
docker ps
curl -sf http://127.0.0.1:9000/api/system/status
```

以后 Docker 只能 bind 这两棵树下面的路径。`~/gha`、`~/Library/Developer`、Desktop 不再进 VM，CI / Xcode 写盘不再被 virtiofs 订阅。

动 `hon` 的 `colima-multica` 不在本方案里。

### B. 清 EAS / DerivedData 残留（磁盘写放大）

同日实测残留：`/var/folders/.../T/eas-build-local-nodejs` **14G**（约 7 次 × 1.5G）、`~/Library/Developer/Xcode/DerivedData` **38G**。

- 保持 `eas build --local` 默认清理，不要在 CI 长期开 `EAS_LOCAL_BUILD_SKIP_CLEANUP=1`
- 维护脚本定期删 1 天前的 `eas-build-local-nodejs/*`，DerivedData 只留最近一份 `iCare-*`
- 删之前仍须确认（生产守则：不擅自删目录）

### C. 错开写盘窗口（调度）

不要让 `mac-mini-mobile-1` 的本机 EAS 和 `mac-mini-sonar-*` 的 `pnpm` / Jest 叠在同一十几分钟。这减的是峰值，不是放大器。

### 验收

下一次只跑 IPA、且 A 已落地时：

- 构建窗口 `fseventsd` 仍可能到几十 %，但应明显低于「整家目录 virtiofs + 双槽 pnpm」叠在一起
- 构建结束后 1 分钟内回到 0%，`TIME` 不再涨
- `colima ssh -- findmnt -t virtiofs` 仍没有整个 `/Users/konghai`

## Prevention

- 再看到 `fseventsd` 先对表 runner 日志和 DerivedData / `~/gha` / `/var/folders` 的 mtime，而不是先改系统守护进程。
- Colima 加新 bind 之前先问：这条路径是不是 CI workFolder 或 Xcode 输出。默认不要挂家目录。
- 7 月的对照：Spotlight 开着时瓶颈是 `mds` / `mds_stores`；关索引之后 Vitest 稳态下 `fseventsd` 接近 0，只有解压 / Xcode 窗口才会再冒出来。

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
resolution_type: configuration_needed
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

先确认是不是洪峰而不是卡死：

```bash
# 连续采样，不要信 top -l 1
for i in 1 2 3 4 5; do
  date "+%H:%M:%S"
  ps -axo pid,%cpu,time,command | grep '[f]seventsd'
  sleep 2
done

mdutil -s / ; mdutil -s /System/Volumes/Data

# 已知写盘热点
for d in ~/gha ~/Library/Developer/Xcode/DerivedData /private/var/folders; do
  echo -n "$d "
  find "$d" -type f -mmin -20 2>/dev/null | wc -l
done
```

若采样已经是 0%、`TIME` 不再涨：不用动。那是刚跑完的 job。

若要压峰值（需停 Colima，先确认容器可中断）：

1. 把 `~/.colima/default/colima.yaml` 的 `mounts` 从整个 `$HOME` 收成 Docker 真正要 bind 的目录，排除 `~/gha`、`~/Library/Developer`、`~/Library/Caches`。
2. `colima restart` 后 `docker ps` 确认容器还在。
3. 本机 EAS 和 sonar / frontend `pnpm` 尽量错开。

不要为了这个关 Spotlight（已经关了），也不要日常重启 `fseventsd`。

## Prevention

- 再看到 `fseventsd` 先对表 runner 日志和上面三个目录的 mtime，而不是先改系统守护进程。
- Colima 家目录整盘 virtiofs 是默认值，加新 bind 之前先问「CI workFolder 会不会被 VM 订阅」。
- 7 月的对照：Spotlight 开着时瓶颈是 `mds` / `mds_stores`；关索引之后 Vitest 稳态下 `fseventsd` 接近 0，只有解压 / Xcode 窗口才会再冒出来。

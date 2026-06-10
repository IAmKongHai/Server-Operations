---
title: frontend-mas docker build 阶段 vite build 撞 Node 默认 ~2GB 堆上限 OOM
date: 2026-06-10
category: docs/solutions/mas-go-dev/build-errors
server: mas-go-dev
module: mas-go-dev / iCare-frontend-mas CI 部署
problem_type: build_error
component: development_workflow
severity: medium
symptoms:
  - "GitHub Actions `Deploy to mas-go-dev` job 在 `Build local Docker image` 步骤失败，exit code 1"
  - "`RUN npm run build`（tsc -b && vite build）报 FATAL ERROR: Ineffective mark-compacts near heap limit Allocation failed - JavaScript heap out of memory"
  - "进程以 exit code 134（Aborted, core dumped）结束"
root_cause: config_error
resolution_type: config_change
related_components:
  - vite
  - node-24-alpine
  - docker-build
  - github-actions-self-hosted-runner
tags: [vite-build, node-heap, oom, max-old-space-size, docker-build, mas-go-dev, frontend-mas]
---

# frontend-mas docker build 阶段 vite build 撞 Node 默认 ~2GB 堆上限 OOM

## Problem

`iCare-frontend-mas` 的 `Deploy to mas-go-dev` job（self-hosted runner，跑在 `mas-go-dev` VM 上）在 `Build local Docker image` 步骤失败。Dockerfile build stage 的 `RUN npm run build`（`tsc -b && vite build`）触发 Node.js OOM，docker build 以 exit code 134 中断，部署未发生。

失败示例：run `27260917984`（CYP-882 add approve billing invoice frontend, #658）。

## Symptoms

```text
[19:0x7fa07c55e000]  63338 ms: Mark-Compact (reduce) 2042.1 (2059.7) -> 2036.2 (2046.4) MB ...
FATAL ERROR: Ineffective mark-compacts near heap limit Allocation failed - JavaScript heap out of memory
Aborted (core dumped)
ERROR: process "/bin/sh -c npm run build" did not complete successfully: exit code: 134
```

关键特征：V8 堆在 **~2046 MB** 处撞顶后崩溃。

## What Didn't Work / 容易误判的方向

- **怀疑"docker 容器分配到的内存太小"**：方向不对。docker build 没有给 build 容器设内存 limit；崩溃发生在 ~2GB，而 VM 当时 available 内存有 4.6 GiB。撞的是 **Node 自身的默认 old-space 堆上限（约 2GB）**，不是 cgroup/容器限制，也不是 VM 物理内存不足。
- 据此去 PVE 给 VM 加内存解决不了问题——Node 不调参就是不肯用超过 ~2GB。

判别方法：看崩溃时的堆大小。如果在 ~2GB 附近且 `free -h` 显示机器还有富余，就是 V8 默认堆上限；如果进程被 OOM killer 直接 `Killed`（exit 137）且 dmesg 有 oom-kill 记录，才是真的内存不够。

## Solution

在 `iCare-frontend-mas` 仓库 `Dockerfile` 的 build stage、`RUN npm run build` 之前提高 Node 堆上限：

```dockerfile
ENV VITE_USE_MOCK=${VITE_USE_MOCK}

# vite build 内存峰值超过 Node 默认 ~2GB 堆上限，会在 mas-go-dev 上 OOM（exit 134）
ENV NODE_OPTIONS=--max-old-space-size=4096

RUN npm run build
```

容量判断（2026-06-10）：

- 崩溃点 ~2046 MB，实际需求只是略超 2GB，4096 已是两倍余量
- `mas-go-dev` VM：7.7 GiB 总内存 / 4.6 GiB available / 无 swap，4096 装得下，无需动 PVE
- `ENV NODE_OPTIONS` 只作用于 build stage，最终 nginx 镜像不携带

## Why This Works

Node.js 默认的 V8 old-space 上限约 2GB（在该容器环境下未按宿主内存放大）。前端随功能迭代膨胀（本次是 CYP-882 让 build 内存峰值刚好越过 2GB），`vite build` 的内存峰值超过默认上限时 V8 反复 Mark-Compact 无效后直接 abort。`--max-old-space-size=4096` 把上限提到 4GB，峰值落在限内即可正常完成。

## Prevention

- 前端 build 在 CI 上以 exit 134 + "JavaScript heap out of memory" 失败时，先看崩溃堆大小是否贴着 ~2GB（或当前设定值），再决定是调 `NODE_OPTIONS` 还是真的加机器内存
- 若日后 build 峰值逼近 4GB，再到 PVE 给 `mas-go-dev` VM 扩内存，并同步把 `--max-old-space-size` 提到 6144；不要提前预留
- VM 无 swap，给 Node 的堆上限要留出系统与其它容器（api/worker/azurite/redis/runner）的余量，不要设到接近物理内存总量

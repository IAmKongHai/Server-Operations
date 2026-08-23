---
title: 新 UAT burst runner 未预建 /var/cache/buildx，镜像构建在 Prepare cache 秒失败
date: 2026-08-23
last_updated: 2026-08-23
category: docs/solutions/icare-uat-runner-2/workflow-issues
server: icare-uat-runner-2
module: iCare Azure UAT / GitHub Actions self-hosted runner (icare-2-uat-runner-2)
problem_type: workflow_issue
component: tooling
symptoms:
  - "iCare-frontend-mas Deploy MAS Azure UAT 的 Wait for backend UAT (same tag) 秒失败，gha=completed:failure"
  - "真正挂点是 iCare-backend Build Azure UAT Images 的 Prepare backend build cache"
  - "CI 日志：mkdir: cannot create directory '/var/cache/buildx': Permission denied"
  - "同一份 workflow 在 icare-2-uat-runner 上一直成功，第一次派到 icare-2-uat-runner-2 才炸"
root_cause: missing_config
resolution_type: config_change
severity: high
tags: [github-actions, self-hosted-runner, azure-uat, buildx, docker-cache, icare-2-uat, cyp-2046, cyp-2263]
---

# 新 UAT burst runner 未预建 `/var/cache/buildx`，镜像构建在 Prepare cache 秒失败

## 现象

`iCare-frontend-mas` 的 `Deploy MAS Azure UAT`（例如 [run 32628980560](https://github.com/cypressoai/iCare-frontend-mas/actions/runs/32628980560/job/97169083529)）挂在 `Wait for backend UAT (same tag)`。该 job 本身健康：

- runner `icare-2-uat-wait` 能 curl UAT API（当时 runtime 仍是上一版 tag）
- 跨仓 token 能读到 backend workflow `completed:failure`

真正失败在 `iCare-backend` `Build Azure UAT Images` 的 `Prepare backend build cache`：

```text
mkdir: cannot create directory '/var/cache/buildx': Permission denied
```

Docker / Azure login / Buildx setup 都已成功，镜像还没开始 build。后续 migrate/roll 被 skip。

## 根因

`build-azure-uat-images.yml`（CYP-2046）把 Buildx local cache 固定在 `/var/cache/buildx`，由 runner 用户自己 `mkdir -p`。`/var/cache` 是 `root:root` `755`，非 root 用户不能在下面建目录。

这是运维预建约定，不是业务代码回归：

| 机 | GitHub runner | `/var/cache/buildx` |
|----|---------------|---------------------|
| `icare-2-uat-ci-runner`（`ssh icare-uat-runner-1`） | `icare-2-uat-runner` | 已有，属主 `icareadmin`，含三份 `*-uat` cache；`v2026-08-23.02` 成功 |
| `icare-2-uat-ci-runner-2` | `icare-2-uat-runner-2` | **不存在**；CYP-2263 临时 D8s_v5 burst 机，label / group 与原机相同 |

两台都在 runner group `icare-2-uat`，GitHub 把 `v2026-08-23.03` 第一次派到 runner-2。

## 解决

在 burst 机上按原机对齐预建（runner 用户是 `icareadmin`，不要抄 mas-go-dev 的 `actions-runner`）：

```bash
ssh icare-uat-runner-2
sudo mkdir -p /var/cache/buildx
sudo chown icareadmin:icareadmin /var/cache/buildx
sudo chmod 755 /var/cache/buildx
```

不需要重启 runner。然后重跑 backend `Build Azure UAT Images`，成功后再重跑 frontend `Deploy MAS Azure UAT`。

## 新 UAT runner 上线必做

只要把机器加进 group `icare-2-uat`（或贴 `azure`/`uat` 并会接到镜像构建 job）：

1. 预建 `/var/cache/buildx`，属主 = 跑 `Runner.Listener` 的用户（这两台是 `icareadmin`）
2. 权限对齐原机 `755`（workflow 不需要组写）
3. 确认该用户在 `docker` 组，且 `docker version` 无需 sudo
4. 不要假设「原机有的目录新机也有」——burst 机磁盘是空的

## 不要误判成

- frontend 代码 / `icare-2-uat-wait` runner 故障（wait job 是正确的 fail-fast）
- tag 源码编不过（Prepare cache 在 `docker build` 之前）
- 磁盘满（该机当时根盘约 88G 空闲）

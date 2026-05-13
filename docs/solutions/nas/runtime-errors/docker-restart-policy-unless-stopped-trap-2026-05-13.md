---
title: Docker 容器宿主重启后未自动拉起——unless-stopped 的"上次手动停过"陷阱
date: 2026-05-13
category: docs/solutions/nas/runtime-errors
server: nas
module: nas / Docker 容器（mas-old-sql2022-fts-nas、mas-old-windows）
problem_type: runtime_error
component: container_orchestration
severity: medium
symptoms:
  - 多个容器在同一秒 `Exited (255)`，`OOMKilled=false`，`Error` 为空
  - NAS 重启后部分容器没有自动启动，需手动 `docker start`
  - RestartPolicy 明明设置为 `unless-stopped`，预期应该自动拉起
root_cause: config_error
resolution_type: configuration_change
tags: [docker, restart-policy, unless-stopped, always, container-lifecycle, nas]
---

# Docker 容器宿主重启后未自动拉起——`unless-stopped` 的"上次手动停过"陷阱

## Problem

NAS 重启后，两个本应自动恢复的容器仍处于 `Exited` 状态：

```
NAMES                     STATUS                      STATE     IMAGE
mas-old-sql2022-fts-nas   Exited (255) 14 hours ago   exited    mas-old-sqlserver-2022-fts:nas
mas-old-windows           Exited (255) 14 hours ago   exited    dockurr/windows
```

两个容器的 `FinishedAt` 几乎完全同步（毫秒级），明显是宿主机层面的事件而非容器自身故障。

```
ExitCode:    255
OOMKilled:   false
Error:       (空)
RestartPolicy: unless-stopped
```

`last reboot` 显示宿主机确实在 `FinishedAt` 时刻重启了。但 `unless-stopped` 不是应该自动拉起吗？

## Root Cause

**Docker 的 `unless-stopped` 策略不是"无论如何都重启"。** 它会**记住容器上次是否被 `docker stop` 手动停过**：

- 上次是 docker daemon 重启/宿主 reboot 导致的退出 → 下次启动自动拉起
- **上次是有人 `docker stop` 手动停的 → 即使 docker daemon 重启，容器也不会自动拉起**

`always` 没有这个"记忆"——daemon 启动后**一定**拉起所有 always 策略的容器。

如何区分场景：

| 你的需求 | 应该用 |
| --- | --- |
| "宿主机重启，所有关键容器必须自己回来" | `always` |
| "我手动停的容器就让它停着，宿主重启不要自作主张拉起" | `unless-stopped` |

NAS 重启场景下，**`always` 才是符合直觉的选择**。

## Resolution

```bash
docker update --restart=always <container1> <container2> ...
docker start <container1> <container2>   # 当前轮先手动起来一次
```

副作用 / 注意：

- 之后 `docker stop` 手动停掉的容器，在 daemon 没重启之前**不会**自己再起来——但下次 daemon/宿主 reboot 时**仍然会**被拉起
- 长期停掉某个容器：`docker update --restart=no <name>` 或直接 `docker rm`
- **不要**用 `--no-verify` / `--no-gpg-sign` 之类绕过钩子的写法

## Verification

```bash
docker inspect <container> --format '{{.HostConfig.RestartPolicy.Name}}'
# 期望输出：always
```

下次 NAS 重启或 docker daemon 重启后，容器应自动出现在 `docker ps`。

## 关键经验

1. **多个容器在同一秒 `Exited(255)` + OOMKilled=false + Error 空 = 宿主机或 docker daemon 重启**，不是各自的故障。先查 `last reboot`、`journalctl -u docker`。
2. **`unless-stopped` 不等于"总是重启"**，有"上次是不是手动停的"这个隐藏状态。
3. **`always` 适用于"必须始终在线"的服务**（数据库、关键 web 服务）；`unless-stopped` 适用于"我可能手动停掉做维护，宿主重启不要给我自动起回来"的容器。
4. **同一项目下所有容器最好用同一策略**，避免一部分起来一部分没起、应用启动顺序混乱。

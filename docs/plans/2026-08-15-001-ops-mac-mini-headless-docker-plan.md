---
title: 把 mac-mini 的 Docker 从 Desktop 换成无 GUI 登录也能拉起的引擎
type: ops
date: 2026-08-15
---

# 把 mac-mini 的 Docker 从 Desktop 换成无 GUI 登录也能拉起的引擎

## Summary

mac-mini 上的容器现在跑在 **Docker Desktop 4.82.0** 里。Desktop 是 Electron 图形应用，引擎活在 `konghai` 的 Aqua（图形登录）会话里。结果是：

- 整机重启后如果没人登录 `konghai`，容器全部起不来
- 2026-08-13 `WindowServer` 被内核杀掉、三个 GUI session 被强制注销时，SSH 还在，但 Desktop 和容器一起没了
- Desktop 自己还开着 UI，Linux VM 又分了 **8 vCPU / 24 GiB**，在 32 GiB 的宿主机上偏狠

目标：把 mac-mini 尽量当服务器用——**开机解锁磁盘之后，不依赖有人守着图形桌面，容器和 CI runner 都能起来；图形会话退出或 WindowServer 再崩，也不应带走容器。**

本计划只覆盖评估与推荐路径。真正换引擎、迁 volume、卸 Desktop、改 LaunchDaemon 必须用户确认后再做。

## Current State（2026-08-15 01:05 CST 只读）

| 项 | 现状 |
| --- | --- |
| 引擎 | Docker Desktop 4.82.0（Engine 29.6.1），context `desktop-linux` |
| socket | `~/.docker/run/docker.sock`；`/var/run/docker.sock` 由 `com.docker.socket` 链过去，给 `hon` 等 `docker` 组成员共用 |
| Desktop 设置 | `AutoStart=true`（登录后自启）、`OpenUIOnStartupDisabled=false`（会弹出 GUI）、`UseResourceSaver=true` |
| VM 配额 | 8 CPU / 24576 MiB RAM / 虚拟盘 `Docker.raw` 稀疏约 926G、实际占用约 174G |
| FileVault | **开着**。冷启动必须有人在登录窗解锁磁盘，这和 Docker 无关，关不掉除非关 FileVault |
| 自动登录 | 未开 |
| 正在跑 | `sonarqube` + `sonar-postgres`（healthy）、`richer-grafana`、`richer-postgres` |
| 有 restart policy 但重启后没起来 | `acquilang-postgres`（`always`，后来又自己退了）、`multica-*`、`cypresso-okr-*`（`unless-stopped`） |
| 明确停用 | `icare-sql-edge`（`restart=no`，2026-06 为给 runner 腾内存） |
| 其它用户 | `hon` 的 Multica compose 在 `/Users/hon/multica/multica/docker-compose.selfhost.yml`，依赖系统 docker socket |
| runner | `mac-mini-sonar-1..4` 是 **LaunchAgent**（`ProcessType=Interactive`），同样绑 GUI 会话；08-13 也一起掉线 |

## Why Docker Desktop cannot do this

Docker Desktop 没有受支持的 headless / LaunchDaemon 模式。`com.docker.vmnetd` 和 `com.docker.socket` 这两个系统守护进程只是辅助，**真正的 `dockerd` 在用户图形会话的 LinuxKit VM 里**。图形会话没了，引擎就没了。远程 `open -a Docker` 也要求已经有 Aqua session，SSH  alone 拉不起来。

所以「继续用 Desktop，再配几个开机脚本」解决不了 08-13 那种 WindowServer 崩溃，也解决不了「人不登录」的重启。

## FileVault 边界（先讲清楚）

Apple Silicon + FileVault：**解锁磁盘和登录是同一步**。停电后必须有人在登录窗输入密码，机器才会继续往下引导。

这不是 Docker 能绕开的。可选：

- **保持 FileVault（推荐）**：接受冷启动要人摸一下键盘。解锁之后，后面的容器/runner 应由 LaunchDaemon 拉起，不再依赖桌面一直挂着。
- **关 FileVault**：才能做到「通电就起、完全没人碰」。家用机器、多用户、里面有 Sonar / 业务库，不建议。
- **计划内重启**可用 `sudo fdesetup authrestart`，重启后自动解锁，不必盯着屏幕。意外掉电仍要人。

## Options

### A. 换成 Colima + LaunchDaemon（推荐）

用 Homebrew 的 `colima`（底下是 Lima + Apple Virtualization，和现在 Desktop 用的是同一套虚拟化）替换 Docker Desktop。

- CLI 还是 `docker` / `docker compose`，现有 compose 文件不用改
- 不跑 Electron UI
- 做成 `/Library/LaunchDaemons`，以 `konghai` 跑，**不依赖 Aqua**
- WindowServer 再崩、有人注销登录，容器应继续在
- VM 内存可以先收到 **10–12 GiB**（Sonar + richer PG + grafana + acquilang PG 够用；现在 24 GiB 是 08-15 重启后 `sonarqube` 吃 137 的重要背景）
- `/var/run/docker.sock` 继续指到新引擎的 socket，`hon` 的 Multica 不用改调用方式

代价：

- Desktop 的 named volume **不能**直接挂到 Colima，必须导出/导入有状态卷
- 镜像要在新 VM 里重新 `pull` / `load`（本地镜像不少，但真正要迁的有状态卷就那几个）
- 需要一段停机窗口（建议先迁 Sonar + richer，再迁 acquilang / Multica）
- 要保留 Desktop 几天做回滚，确认稳定后再卸

必须迁的有状态卷：

| volume | 用途 |
| --- | --- |
| `sonar_pg_data` / `sonarqube_data` / `sonarqube_extensions` / `sonarqube_logs` | SonarQube（团队 CI 依赖） |
| `richer_grafana_data` + richer postgres 卷 | DDRicher 监控 |
| `acquilangai_postgres_data` | AcquiLang 库 |
| `multica_pgdata` / `multica_backend_uploads` | hon 的 Multica |

`icare-sql-edge-data`、telegram-bot、旧 redis/pgadmin 卷按现状保留备份即可，不必开机自启。

### B. 只做 Desktop 减负（不换引擎，治标）

立刻能做、风险低，但 **解决不了「不登录 / WindowServer 崩」**：

- `OpenUIOnStartupDisabled=true`，登录后只起引擎、不弹窗口
- 把 VM 内存从 24 GiB 降到 10–12 GiB，降低和 4 个 runner 抢内存导致 137 的概率
- 确认 `konghai` 登录项里 Docker 自启（已经 `AutoStart=true`）

适用：暂时不想迁，只想少浪费点 GUI / 少 OOM。

### C. 自动登录 `konghai` + 保持 Desktop

看起来省事，实际：

- FileVault 开着时自动登录基本用不上（解锁已经是登录）
- 不修 WindowServer 崩溃这条路径
- GUI 还在，资源浪费还在
- 物理接触机器就进桌面，多用户机器不合适

**不推荐。**

### D. 把容器搬到 PVE 上的 Linux VM

最像「真服务器」，但 Sonar / richer / acquilang 的地址、备份、Tailscale 入口都要改；mac-mini 的 10 核 / 32G 就是为这些服务留的。比 A 工程量大一个数量级。除非同时想把 mac-mini 只留给 runner，否则不走这条。

OrbStack 更轻，但官方同样不支持无登录 headless，和 Desktop 同一类限制。

## Recommended sequence（方案 A，用户确认后执行）

1. **窗口**：先通知 Sonar / richer / Multica 会短暂停。选 CI 低峰。
2. **备份**：对上述 named volume 做 `docker run --rm -v vol:/data -v $PWD:/backup alpine tar czf ...`；Sonar 再加一份 `pg_dump`。
3. **装新引擎（Desktop 先别卸）**：`brew install colima docker docker-compose`；`colima start --vm-type vz --vz-rosetta --mount-type virtiofs --cpu 6 --memory 12 --disk 100`。
4. **切 context**：`docker context use colima`；验证 `docker info` 指向 Colima。
5. **导入卷 + compose up**：先 `sonarqube`，验证 `http://mac-mini:9000/api/system/status` = UP；再 richer；再 acquilang；最后跟 hon 约 Multica。
6. **系统 socket**：把 `/var/run/docker.sock` 指到 `~/.colima/default/docker.sock`（或 Colima 的 docker context 默认位置），保证 `hon` 和现有脚本不用改 `DOCKER_HOST`。
7. **LaunchDaemon**：`/Library/LaunchDaemons/com.konghai.colima.plist`，`UserName=konghai`，`RunAtLoad` + `KeepAlive`，`colima start --foreground`（或等价的 lima 前台进程）。注销 / WindowServer 重启后抽查容器仍在。
8. **runner（同一目标，可第二步）**：把 `mac-mini-sonar-1..4` 从 LaunchAgent 改成 LaunchDaemon，否则「当服务器用」只解决了一半——08-13 的 runner 掉线还会再发生。
9. **浸泡 3–7 天**：Desktop 留着但不开机自启。确认 CI、Sonar、richer、Multica 都稳。
10. **卸载 Docker Desktop**：收回 174G 数据目录和 24 GiB 配额；删掉 `com.docker.vmnetd` / `com.docker.socket` 以免和 Colima 抢 socket。

回滚：停 Colima → 再开 Desktop → context 切回 `desktop-linux`。volume 以第 2 步的 tar / dump 为准，不要假设两套引擎能看见同一份数据。

## Out of scope unless asked

- 关闭 FileVault
- 启用自动登录
- 现在就启动/停止任何容器
- 卸载 Docker Desktop
- 改 runner LaunchAgent（建议跟 A 一起做，但单独确认）

## Success criteria

- FileVault 解锁后，**不必再点 Docker 图标**，`docker ps` 能通，Sonar `UP`
- `konghai` 注销图形会话后，Sonar / richer 仍监听原端口
- 模拟 WindowServer 不可用（或仅注销）时，SSH 仍能 `docker ps`，容器不是 `Exited`
- Desktop GUI 不再常驻；Colima VM 内存明显低于现在的 24 GiB
- `hon` 仍能用 `/var/run/docker.sock` 管 Multica

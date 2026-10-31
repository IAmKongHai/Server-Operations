---
artifact_contract: "ce-handoff/v1"
created_at: "2026-10-31T08:52:23Z"
title: "mac-mini colima 迁 team-svc 的剩余事项"
summary: "迁移主体已完成；剩 cmm-api 生产部署被腾讯云备份订单卡住、moo-ocr 私有模块凭据、P5 七天后清理和 moo 转发端口撤除"
keywords: ["team-svc", "mac-mini", "colima", "P5", "cmm-api", "moo-ocr", "khmini", "forwarders"]
cwd: "/Users/konghai/Code/Project/Server"
resume_focus: "跟进迁移收尾：cmm-api 重跑生产部署、moo-ocr 凭据、2026-11-07 前后的 P5 清理"
repository: "Server (personal ops notes repo)"
repo_root_sha: "105e22b22e8936b9788d571dd0dd845a4cf8424d"
branch: "main"
head: "191f67ae13b4c2ec1b9aacb71e3bbb45afccbe0a"
---

# mac-mini colima → PVE team-svc：剩余事项

## 背景与目标（用户意图）

用户要腾出 mac-mini 内存跑本地 AI 模型。10-31 已把 colima `team` / `moo` 的全部服务、moo-app、需要 Docker 的 CI 迁到 PVE VM 150 `team-svc`（`192.168.2.23`，tailnet `100.80.124.63`，6C/12G）。用户 10-31 下午的决定（用户原话归纳）：
- 需要 Docker 的 CI 直接放 team-svc 跑（不走远程 `DOCKER_HOST`），PR 由 agent 开，旧地址保留转发。
- moo-app 搬到 PVE，"部署都搬过去了，留点尾巴意义不大"。

三个 PR（`caimiamiao/cmm-api#14`、`IAmKongHai/qingfan#59`、`cypressoai/moo-decision#84`）用户已合并；用户已用 root 停掉 khmini runner 和 `com.cypressoai.colima-team` LaunchDaemon，并 `colima stop -p team`。mac-mini 现在没有常驻 colima VM，`memory_pressure` 空闲 90%（迁移前 55%）。

## 先读这些（权威来源）

- `docs/plans/2026-10-31-0010-ops-mac-mini-vms-to-pve-plan.md` 第 22–30 行：执行进度，只有 P5 未勾；第 113 行起 P5 步骤；"回滚"一节。
- `docs/operations/mac-mini.md` 顶部 15:31 和 14:40 条目：做了什么、回滚方式、"留待以后"清单。
- `docs/operations/team-svc.md` 顶部 15:31（PR 合并后流水线，含 cmm-api 失败详情）和 14:40（runner、moo-app 迁入、moo-ocr 模块）。
- `docs/operations/pve.md` 14:31：VM 150 vCPU 4→6，备份 `/root/150.conf.bak.20261031-cpu`（PVE 上，machine-local）。
- `team-svc/README.md` 的 "CI runner" 和 "moo-app" 两节：runner 表、隔离规则、moo-ocr 私有模块说明。
- `AGENTS.md` 服务器表 `mac-mini` / `team-svc` 行，以及 mac-mini 目录约定里 runner、团队服务、colima、moo-app 几条 bullet。
- `scripts/mac-mini-team-svc-forwarders.sh`：mac-mini 转发器源码（部署在 hon 的 `~/.local/bin/team-svc-forwarders`）。
- 本会话提交：`d0b405f`、`f01934e`（Server 仓库）。`191f67a` 是另一会话（mas-sit）的提交，与本事无关。

## 未完成事项

### 1. cmm-api 生产部署失败——阻塞在用户侧（腾讯云）

- 合并 #14 后，main 的 `verify` 在 team-svc 通过；生产部署 job（GitHub 托管 `ubuntu-latest`）卡在 `Back up production PostgreSQL`。
- 腾讯云返回 `OperationDenied.InstanceStatusLimitError`：实例 `postgres-fifcu565` 的备份订单处于隔离状态，不允许获取备份下载链接。10-21 那次部署这一步还正常；我推测是欠费或订单过期（未核实）。
- 迁移、切换、冒烟都被跳过，**生产仍是旧镜像**，未受影响。修好之前 cmm-api 每次合并都会停在这一步。
- 用户处理完腾讯云订单后：重跑 run `41180587296`，或 `workflow_dispatch`。cmm-api 约定：merge 到 main = 生产部署，需谨慎。
- 状态：已告知用户，等待用户处理。没有 agent 侧动作。

### 2. moo-ocr 私有模块的长期凭据——等用户决定

- team-svc 的 moo-decision runner 没有 GitHub 凭据，`cypressoai` 组织禁用了 deploy key（加 key 时报 "Deploy keys are disabled for this repository"）。
- 现状是临时方案：把 `go.mod` 锁定版本手工放进 `~actions-runner/go/pkg/mod/cache/download/`（从 mac-mini hon 的模块缓存拷来，ziphash 与 go.sum 一致），runner `.env` 设 `GOPRIVATE=github.com/cypressoai/*`（备份 `.env.bak.20261031`）。
- **风险**：moo-decision 一旦升级 moo-ocr 版本，SIT 构建（`deploy-sit.yml`）就会失败。
- 已备好但未生效：`~actions-runner/.ssh/moo-ocr-deploy`（公钥 `.pub`）、ssh 别名 `github-moo-ocr`、git `insteadOf` 规则。
- 选项（互斥，用户选）：
  - a) 组织开放 deploy key → 把上面的公钥加到 moo-ocr（只读）。我给用户的建议是这个。
  - b) fine-grained 只读 token 写进 runner 环境（不要写进仓库或文档）。
  - c) 继续手工拷缓存，每次升级手动补。

### 3. P5 清理——计划 2026-11-07 前后，删除前必须经用户确认

都在 mac-mini 上，多数需要 root（用户自己执行或给 sudo）：
- colima `team` / `moo` 的磁盘（`/Users/hon/.colima/_lima/_disks/colima-*` 一带，删前先 `ls` 确认实际路径和大小）。这是回滚的唯一依据，删了就没法回滚到 mac-mini。
- `/Users/hon/actions-runner/khmini`（449M）和 workFolder `/Users/hon/gha/khm1`（500M）；还有 `gha/cache/go-build-khm1`（AGENTS.md 里列出的 per-slot 缓存，大小未查）。
- `/Library/LaunchDaemons` 下两个已 bootout + disable 的 plist：khmini runner（`actions.runner.cypressoai-moo-decision.khmini`）和 `com.cypressoai.colima-team`。
- 两个维护 LaunchDaemon（`com.cypressoai.gha-runner-maintenance{,-weekly}`）plist 里 `WORK_DIRS`（以及 GOCACHE 相关列表，如有）去掉 `khm1`；源码 `scripts/install-mac-mini-team-services-daemons.sh` 也要同步。
- 完成后：勾掉计划 P5，更新 `AGENTS.md`（runner workFolder 列表里的 `khm1`、per-slot 缓存列表、colima bullet、moo-app bullet 里"目录还没删"），追加 `docs/operations/mac-mini.md` 条目并提交。
- 另：mac-mini `~/moo-app`（旧 darwin 回滚包、备份、日志，plist 目录 `launchd.disabled-20261031`）也可以一并清理，但用户没提过，需另行确认。

### 4. moo 的 6 个回环转发端口——等开发机改连

- `team-svc-forwarders` 里 `127.0.0.1` 上的 15432、16379、19000、9092、8083、19094，给经 `ssh khmini` 建隧道的开发机用。
- 等开发机都直连 team-svc 后，从 `scripts/mac-mini-team-svc-forwarders.sh` 的 `forwards` 删掉，部署到 hon 的 `~/.local/bin/team-svc-forwarders`，`kill` supervisor 后重新拉起（会让其它端口断几秒）。没有截止时间，触发条件由用户判断。

## 不要重走的路

- 不要用 socat 做 mac-mini 转发：应用防火墙会拦未签名程序的外部入站；用 `/usr/bin/ssh -N -L`。
- 不要在 mac-mini 用 `tailscale serve` 做 18188：需要 root，hon 用不了；现在由转发器直接绑 tailnet IP（Tailscale 没起来时 60 秒后重连补上）。
- 不要再启动 mac-mini 上的 `~/moo-app`：会出现两个 worker。
- 不要给 mac-mini 的 runner 恢复 Docker 依赖：plist 里残留的 `DOCKER_HOST` 已失效，需要 Docker 的 job 写 `runs-on: [self-hosted, team-svc]`。
- team-svc 上 CI 和 SonarQube、开发库共用一个 Docker：workflow 里不能写 `docker system prune`、`docker rm -f $(docker ps -aq)` 这类全局命令。
- 不要试图给 moo-ocr 加 deploy key，组织策略不改就会一直失败。

## 已验证

- qingfan PG 测试在 team-svc 真跑了（随机端口，只绑 127.0.0.1）；cmm-api `-race` 测试 + Quality Gate 通过。
- moo-app：新 http、https（tailscale serve 443）、旧 mac-mini 地址都返回 200，家里内网访问不到；worker consumer group Stable；SIT `release-commit` = `a65a87f`（当时的 develop）。
- GitHub 上 khmini runner（id 21）已删，moo-decision 只剩 `team-svc` runner。
- mac-mini 无 Virtualization / colima 进程。

## 约束提醒

- 中文沟通；Server 仓库只在 `main` 上工作，每次变更都要提交；运维动作自动追加 `docs/operations/<server>.md` 时间线并提交。
- 删除、重启、改 crontab / LaunchDaemon 等危险动作先征得用户确认。
- `rm` 只写字面完整路径；不要用 `timeout` 命令；不要把密码 / token 写进文档或提交。

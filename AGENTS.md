# Agent 工作约定

这是一个运维笔记仓库，不是应用代码仓。绝大多数任务是：
- 通过 SSH 登录服务器排查问题
- 把解决方案沉淀进 `docs/solutions/`
- 维护命名约定与目录结构

## 语言

始终使用中文沟通。

## Git 分支约定

本仓库是个人运维笔记仓库，后续所有操作都只在 `main` 分支上进行。

- 不创建 feature/dev/topic 分支
- 不切换到非 `main` 分支工作
- 开始改文件前先确认当前分支是 `main`
- 如果当前不在 `main`，先切回 `main`，不要在其它分支继续提交
- 每次执行任务后，如果工作区有变更，必须用中文写清楚变更目的并提交 `git commit`，提交完成才算任务完成
- 提交信息应保持规范：优先沿用仓库已有风格；没有明确风格时使用 Conventional Commits，例如 `docs: 记录 dev-cypresso 容器停用时间线`

## 生产服务器操作守则

**`nyh-prod` 是生产服务器**。其它任何被纳入本仓库的服务器，默认都按生产对待，除非 README 明确标注是测试环境。

操作前：
1. 说清楚要做什么、预期影响、能否回滚
2. 改动配置/服务前先备份当前状态（`cp file file.bak.YYYYMMDD` 或读出当前值留在对话里）
3. 危险动作（重启、删除、改防火墙、改数据库）必须先征得用户确认，不要"顺手"做掉

不允许在没有用户确认的情况下：
- 重启进程、服务、面板
- 删除文件、目录、备份
- 修改 crontab、防火墙规则、SSH 配置
- 改动数据库 schema 或数据

可以自由做的事：
- 只读查询（`ls`、`cat`、`ps`、`openssl x509 -noout`、`systemctl status` 等）
- 在用户工作目录下创建/修改文档文件

## 故障文档约定（`docs/solutions/`）

详见 `docs/solutions/README.md`。要点：

- 路径：`docs/solutions/<server>/<category>/<slug>-<YYYY-MM-DD>.md`
- 文件名 slug 用小写、英文、连字符；末尾带日期方便排序
- frontmatter 字段遵循 ce-compound 的 schema，外加一个本仓库扩展字段 `server:`
- 类别枚举沿用 ce-compound 标准：`integration-issues`、`runtime-errors`、`performance-issues`、`security-issues`、`database-issues`、`workflow-issues`、`best-practices` 等

写文档时**优先用 `/ce:compound`**（lightweight 模式即可），它会自动按 schema 校验字段。

## 运维时间线约定（`docs/operations/`）

日常服务器操作记录写入 `docs/operations/<server>.md`，按时间倒序持续追加。

适合记录：
- 停止/启动容器、改 restart policy、迁移服务
- 调整配置、磁盘、备份、计划任务
- 一次性维护动作及其验证结果

每条记录至少写清：
- 时间（`YYYY-MM-DD HH:mm CST`）
- 原因
- 影响
- 回滚方式
- 做了什么
- 验证结果

如果一次操作暴露出可复用经验或故障复盘，再另写 `docs/solutions/`。

### 自动追加时间线并自动提交（无需询问）

对已经完成的服务器运维动作（含只读排查、装工具、改配置、启停容器等），**默认自动**把记录追加进 `docs/operations/<server>.md` 并 `git commit`，**不要**反过来问用户"要不要记录 / 要不要提交"：

- 新条目置于文件顶部（时间倒序），字段沿用本文件既有条目风格（时间 / 操作人 / 原因 / 选型或影响 / 备份 / 回滚方式 / 变更时序 / 验证）。
- 记录写完直接 `git commit`（在 `main` 分支，遵循上文「Git 分支约定」的提交信息规范）。
- 边界：本条只免除"记录与提交"这一步的询问，**不改变**上文「生产服务器操作守则」——服务器上的危险动作（重启、删除、改防火墙 / crontab / SSH、改库 schema/data）**仍须先征得用户确认**再执行，确认后再按本条自动记录+提交。

## 服务器连接

所有服务器走 `~/.ssh/config` 别名：

| 别名           | 用途                                                                                   | 是否按生产对待                    |
| -------------- | -------------------------------------------------------------------------------------- | --------------------------------- |
| `nyh-prod`     | 南亚汇（NYH）生产、AcquilangAi 生产、DDRicher 测试 / 生产；宝塔面板端口 10463          | **是**                            |
| `dev-cypresso` | iCare 项目集成测试服务器                                                               | 否（测试环境，但仍需备份后再改）  |
| `tizi`         | 主代理服务器                                                                           | **是**（挂了影响日常翻墙）        |
| `rao-tizi`     | `tizi` 的备用代理                                                                      | 是                                |
| `tizi-cyp`     | 新代理服务器（`89.208.242.203`，AlmaLinux 9.7）                                        | **是**（代理节点，按生产对待）    |
| `mac-mini`     | 家里的 Mac mini                                                                        | 否                                |
| `umacbook-pro` | Tailscale 网内 MacBook Pro（`100.113.23.49`，主机名 `UdeMacBook-Pro.local`），计划跑 GitHub Actions self-hosted runner；`ssh umacbook-pro` 以 `for-konghai` 登录 | 否（CI runner 机，改 runner / LaunchAgent 前仍需确认） |
| `nas`          | 家用 NAS，跑 `mas-old-sql2022-fts-nas`（SQL Server）、`mas-old-windows` 等 Docker 容器 | **是**                            |
| `pve`          | Proxmox VE 虚拟化宿主，计划承载开发测试 VM；当前可通过 `ssh pve` 以 root 密钥登录    | 否（测试环境，但仍需备份后再改）  |
| `mssql-ref`    | PVE 上的 Ubuntu VM，运行 MAS 老系统 MSSQL 参考数据库；当前可通过 `ssh ubuntu@192.168.2.20` 登录 | 否（参考/测试数据库，改库前仍需备份确认） |
| `mas-go-dev`   | PVE 上的 Amazon Linux 2023 VM（`192.168.2.22`，原裸 IP 访问），承载 MAS Go 重构版开发/集成测试环境，跑后端容器与 self-hosted GitHub Actions runner；`ssh mas-go-dev` 以 `ec2-user` 登录 | 否（开发测试环境，但改 Docker / runner 前仍需备份确认） |

注意：
- `nyh-prod` 上同时跑着多个项目的生产数据库与站点，任何重启 / 配置改动都要先想清楚波及哪些项目
- 宝塔面板的 entrance 路径（URL 里 `/100c682f` 这一段）相当于第二道密码，不要写进 commit 信息或公开文档
- `dev-cypresso` 虽是测试，但 iCare 团队会用，破坏性操作前仍需确认
- `nas` 上的 SQL Server 容器承载历史业务数据库（`medicalassistance` 等），关键容器统一用 `--restart=always` 而非 `unless-stopped`，避免 NAS 重启后不自动拉起
- `pve` 当前定位为开发测试虚拟化宿主；PVE 网络、存储、VM 等基础设施改动仍按“先备份、再改动、可回滚”执行
- `mssql-ref` 不是生产数据库，但承载 MAS 老系统完整参考数据；重启 SQL Server、改 schema/data、恢复备份前仍需先备份并确认
- `mas-go-dev` 是 MAS 老系统 Go 重构版的开发测试 VM，过往文档常以 `192.168.2.22` 指代；同时跑着 self-hosted GitHub Actions runner，停机或重启容器会影响 CI
- `mas-go-dev` 上的目录约定：
  - `/opt/mas-go-dev/backend/` — iCare backend 部署目录，每次 PR 由 runner 同步 `backend.compose.yaml`、构建镜像并滚动 `api` + `worker` 容器；`.env.docker` 在此本地维护（600 权限），仓库内对应 `backend/.env.docker.example`
  - `/opt/mas-go-dev/frontend-mas/` — iCare frontend-mas 部署目录，同上由 runner 维护
  - `/opt/mas-go-dev/infra/` — iCare 集成测试基础设施目录，承载 `infra.compose.yaml`（`icare-backend-infra` compose project），跑 `azurite` + `redis` 两个常驻容器供 worker / api 经 `shared-services` 网络通过 DNS 名 `azurite` / `redis` 访问。**不由 runner 自动管理**，仅在仓库内 `backend/infra.compose.yaml` 变更或手动调整基础设施时执行 `sudo -u actions-runner docker compose -f infra.compose.yaml up -d`；容器使用 `restart: always`，VM 重启后自动拉起
  - `/opt/mas-go-dev/logs/` — 运维日志归档

## 检索历史方案

下次接到类似问题前先看 `docs/solutions/`：

```bash
# 按服务器
grep -rl "server: nyh-prod" docs/solutions/

# 按关键词
grep -ri "宝塔\|baota\|bt-panel" docs/solutions/

# 按 tag
grep -r "tags:.*ssl-cert" docs/solutions/
```

`CONCEPTS.md` 记录项目内有特定含义的共享术语（实体、命名流程、状态概念），适合在梳理运维背景或讨论领域概念前快速对齐词义。

## 文档风格

- 中文为主，技术名词、命令、路径、配置项保留英文原文
- 命令块用 fenced code block 标注语言（```bash、```nginx 等）
- 给出"做了什么"和"为什么"，避免只贴命令不解释
- 不要在文档里写明文密码、token、私钥

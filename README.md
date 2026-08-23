# Server 运维笔记

这个仓库用于记录我名下各台服务器的运维变更、故障处理、配置约定。

## 目录结构

```
server/
├── README.md            # 本文件，仓库说明
├── AGENTS.md            # 给 AI agent 的工作约定
├── CLAUDE.md            # → AGENTS.md（别名，Claude Code 默认读取）
├── docs/
│   ├── operations/      # 日常运维操作时间线，按服务器持续追加
│   │   └── <server>.md
│   └── solutions/       # 故障解决方案与最佳实践，按服务器 + 类别组织
│       └── <server>/<category>/<slug>-<date>.md
└── <server>/            # 每台服务器的私有资料（连接信息、备份脚本备份等）
    └── nyh-prod/
```

## 已纳入的服务器

| 名称           | 类型              | 用途                                                                                            |
| -------------- | ----------------- | ----------------------------------------------------------------------------------------------- |
| `nyh-prod`     | 生产 / 多项目共用 | 南亚汇（NYH）生产、AcquilangAi 生产、DDRicher 测试 / 生产；装有宝塔面板（端口 10463）            |
| `dev-cypresso` | 测试              | iCare 项目集成测试服务器                                                                         |
| `tizi`         | 代理              | 主代理服务器                                                                                     |
| `rao-tizi`     | 代理（备用）      | `tizi` 的备用代理                                                                                |
| `tizi-cyp`     | 代理              | 新代理服务器（`89.208.242.203`，AlmaLinux 9.7）                                                  |
| `tizi-ddy`     | 代理              | 代理节点（`80.251.215.131`，Debian 13，3x-ui 面板）                                              |
| `mac-mini`     | 本地              | 家里的 Mac mini                                                                                  |
| `lemon-imac`   | 本地 / 测试       | Tailscale 内网 iMac（8 核 / 8GB），跑 self-hosted runner `lemon-imac-1/2`                          |
| `umacbook-pro` | 本地 / 测试       | Tailscale 内网 MacBook Pro（`100.113.23.49`，M1 / 8GB），跑 self-hosted runner `umacbook-pro-1/2`  |
| `nas`          | 本地 / 数据       | 家用 NAS，跑 SQL Server（`mas-old-sql2022-fts-nas` 等）及历史业务数据库                          |
| `pve`          | 本地 / 测试       | Proxmox VE 虚拟化宿主，计划承载开发测试 VM                                                       |
| `mssql-ref`    | 本地 / 数据       | PVE 上的 Ubuntu VM，运行 MAS 老系统 MSSQL 参考数据库（`192.168.2.20`）                            |
| `mas-go-dev`   | 本地 / 测试       | PVE 上的 Amazon Linux 2023 VM（`192.168.2.22`），承载 MAS Go 重构版开发/集成测试环境与 GH Actions runner |
| `fnos-nas`     | 本地 / 存储       | PVE 上的飞牛 fnOS VM（VMID 140，`192.168.2.9`），存放可重新下载的影视资源，不承诺数据可恢复       |
| `km-landui`    | 本地              | 内网设备，纳入例行安全扫描清单                                                                    |
| `home-router`  | 本地 / 网络       | 家里路由器，Web 管理端口经 `mac-mini` SSH 跳板访问                                                |
| `office-router`| 本地 / 网络       | 办公室路由器，原托管的 GitHub Actions runner 已于 2026-06-30 移除                                 |
| `cursor-box`   | 云端 / 临时       | Cursor Cloud Agent 沙箱（`100.102.171.1`，Tailscale 名 `3x-ui`）；不是 3x-ui 代理面板             |
| `icare-uat-runner-1` | Azure UAT / 发版 | 原 UAT 构建 VM（`10.30.6.4`，`Standard_B2s`）；`ssh icare-uat-runner-1`（兼容 `icare-uat-runner`） |
| `icare-uat-runner-2` | Azure UAT / burst | CYP-2263 临时 D8s_v5（`10.30.6.5`）；`ssh icare-uat-runner-2`；必须预建 `/var/cache/buildx` |

> 详细的服务运行清单、域名、端口、备份策略等，按需在 `<server>/` 子目录或 `docs/solutions/<server>/` 下补充。
>
> `fnos-nas` / `km-landui` / 路由器只有运维时间线，无 `docs/solutions/` 条目；`fnos-nas` 曾出现 SSH 超时不可达（见 `docs/operations/lemon-imac.md` 2026-08-07 条目）。

## 常用工作流

- **记录新故障/解决方案**：在 Claude Code 里运行 `/ce:compound`，agent 会按 `docs/solutions/` 的约定写入
- **记录日常运维操作**：追加到 `docs/operations/<server>.md`，按时间倒序记录操作原因、影响、回滚方式和验证结果
- **检索历史方案**：`grep -r "<关键词>" docs/solutions/` 或按 frontmatter 检索 `grep -rl "server: nyh-prod" docs/solutions/`
- **SSH 连接**：所有服务器都通过本机 `~/.ssh/config` 的别名连接，例如 `ssh nyh-prod`

## 安全约定

- 仓库不存放任何明文密码、私钥、token；如需引用敏感信息，仅记录其位置（如"见 1Password 条目 X"或"见服务器 /root/.something"）
- 操作生产服务器前先在文档里写清楚预期影响和回滚方法

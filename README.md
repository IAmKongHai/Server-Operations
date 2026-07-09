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
| `mac-mini`     | 本地              | 家里的 Mac mini                                                                                  |
| `lemon-imac`   | 本地 / 测试       | Tailscale 内网 iMac，作为 macOS ARM GitHub Actions self-hosted runner                             |
| `nas`          | 本地 / 数据       | 家用 NAS，跑 SQL Server（`mas-old-sql2022-fts-nas` 等）及历史业务数据库                          |
| `pve`          | 本地 / 测试       | Proxmox VE 虚拟化宿主，计划承载开发测试 VM                                                       |
| `mssql-ref`    | 本地 / 数据       | PVE 上的 Ubuntu VM，运行 MAS 老系统 MSSQL 参考数据库（`192.168.2.20`）                            |
| `mas-go-dev`   | 本地 / 测试       | PVE 上的 Amazon Linux 2023 VM（`192.168.2.22`），承载 MAS Go 重构版开发/集成测试环境与 GH Actions runner |

> 详细的服务运行清单、域名、端口、备份策略等，按需在 `<server>/` 子目录或 `docs/solutions/<server>/` 下补充。

## 常用工作流

- **记录新故障/解决方案**：在 Claude Code 里运行 `/ce:compound`，agent 会按 `docs/solutions/` 的约定写入
- **记录日常运维操作**：追加到 `docs/operations/<server>.md`，按时间倒序记录操作原因、影响、回滚方式和验证结果
- **检索历史方案**：`grep -r "<关键词>" docs/solutions/` 或按 frontmatter 检索 `grep -rl "server: nyh-prod" docs/solutions/`
- **SSH 连接**：所有服务器都通过本机 `~/.ssh/config` 的别名连接，例如 `ssh nyh-prod`

## 安全约定

- 仓库不存放任何明文密码、私钥、token；如需引用敏感信息，仅记录其位置（如"见 1Password 条目 X"或"见服务器 /root/.something"）
- 操作生产服务器前先在文档里写清楚预期影响和回滚方法

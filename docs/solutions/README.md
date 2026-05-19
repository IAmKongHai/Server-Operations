# docs/solutions/

按服务器 + 类别组织的运维解决方案知识库。

## 目录约定

```
docs/solutions/
├── <server>/                # 服务器别名，对应 ~/.ssh/config 里的 Host
│   └── <category>/          # ce-compound schema 的标准类别
│       └── <slug>-<YYYY-MM-DD>.md
└── best-practices/          # 跨服务器通用经验，不绑具体 host
    └── <slug>-<YYYY-MM-DD>.md
```

例：

```
docs/solutions/nyh-prod/integration-issues/baota-panel-stale-ssl-cert-in-memory-2026-05-11.md
docs/solutions/best-practices/sqlcmd-shell-pitfalls-2026-05-13.md
```

顶层 `best-practices/` 是唯一允许不挂在 `<server>/` 下的目录，用于跨多台机器都适用的通用经验（shell 陷阱、命令模式、流程模板等）。其他类别仍按 `<server>/<category>/` 组织。

## 类别枚举（沿用 ce-compound）

Bug 类（出了问题并修复）：

- `build-errors/`
- `test-failures/`
- `runtime-errors/`
- `performance-issues/`
- `database-issues/`
- `security-issues/`
- `ui-bugs/`
- `integration-issues/` —— 第三方服务、面板、证书续签等协同问题
- `logic-errors/`

Knowledge 类（最佳实践、流程）：

- `best-practices/`
- `workflow-issues/`
- `developer-experience/`
- `documentation-gaps/`

## 文件命名

- slug 全小写，英文，连字符分隔，描述问题本身（不是解法）
- 文件名末尾带 `-YYYY-MM-DD`，方便同类问题多次发生时按时间排序
- 一个文件聚焦一个具体问题；如果是泛化的最佳实践，归 `best-practices/` 并省略日期亦可

## Frontmatter

完整 schema 见 ce-compound 插件的 `references/schema.yaml`。本仓库扩展一个字段：

| 字段              | 必填 | 说明                                                          |
| ----------------- | ---- | ------------------------------------------------------------- |
| `title`           | 是   | 简明中文标题                                                  |
| `date`            | 是   | `YYYY-MM-DD`                                                  |
| `category`        | 是   | 例如 `docs/solutions/nyh-prod/integration-issues`             |
| `server`          | 是   | **本仓库扩展**：服务器别名，例如 `nyh-prod`，便于跨目录检索   |
| `module`          | 是   | 受影响模块，例如 `nyh-prod / 宝塔面板`                        |
| `problem_type`    | 是   | schema 枚举，例如 `integration_issue`                         |
| `component`       | 是   | schema 枚举，运维类常用 `tooling`                             |
| `severity`        | 是   | `critical` / `high` / `medium` / `low`                        |
| `symptoms`        | bug  | 1-5 条可观察症状                                              |
| `root_cause`      | bug  | schema 枚举                                                   |
| `resolution_type` | bug  | schema 枚举                                                   |
| `tags`            | 否   | 关键词，小写连字符                                            |

## 写新文档

优先用 Claude Code 的 `/ce:compound`（lightweight 模式即可）：
- 它会按 schema 校验 frontmatter
- 写完后告诉它"按本仓库约定改成 `docs/solutions/<server>/<category>/` 路径，并在 frontmatter 加 `server:` 字段"

## 检索

```bash
# 某台服务器的所有方案
grep -rl "server: nyh-prod" docs/solutions/

# 关键词
grep -ri "ssl\|证书" docs/solutions/

# 按 tag
grep -r "tags:.*baota" docs/solutions/
```

## 现有文档

- [nyh-prod / 宝塔面板加载内存中过期 SSL 证书](nyh-prod/integration-issues/baota-panel-stale-ssl-cert-in-memory-2026-05-11.md) — 2026-05-11
- [nyh-prod / 宝塔 Docker 反代域名 SSL 证书未自动续期](nyh-prod/integration-issues/baota-ssl-acme-challenge-routing-fix-2026-05-19.md) — 2026-05-20
- [dev-cypresso / GitHub Actions 部署失败，磁盘被 Docker 老镜像占满](dev-cypresso/integration-issues/docker-image-buildup-fills-disk-2026-05-14.md) — 2026-05-14

---
title: mssql-scripter 对某库稳定卡死在 0 字节，改用 INFORMATION_SCHEMA 直连做结构对比
date: 2026-06-22
category: docs/solutions/mssql-ref/workflow-issues
server: mssql-ref
module: mssql-ref / MAS 老系统参考库结构对比
problem_type: workflow_issue
component: tooling
severity: medium
symptoms:
  - mssql-scripter 导出某个库的结构脚本时输出文件长期停在 0 字节
  - 进程 STAT=S（睡眠）、%CPU=0.0，挂了 20+ 分钟仍无产出，但不退出
  - 同一条命令导另一个库（表更少）几分钟就正常完成，仅特定库复现
  - macOS 上没有 timeout/gtimeout，无法简单给导出加超时保护
root_cause: tooling_limitation
resolution_type: workaround
tags: [sql-server, mssql, mssql-scripter, schema-diff, information-schema, sqlcmd, macos]
---

# mssql-scripter 对某库稳定卡死，改用 INFORMATION_SCHEMA 直连做结构对比

## Problem

需要逐表逐字段对比 `medicalassistance_replicated`（388 表）与 `medicalassistance_preprod`
（428 表）的结构。先尝试用 `mssql-scripter` 把两库导成格式一致的 DDL 脚本再对比：

```bash
mssql-scripter -S 192.168.2.20 -U sa -P "$PW" -d <db> \
  --script-create --target-server-version 2016 --exclude-use-database -f out.sql
```

- `medicalassistance_replicated` 几分钟导完（389 建表，正常）。
- `medicalassistance_preprod` **稳定卡死**：输出文件始终 0 字节，主进程
  `STAT=S`、`%CPU=0.0`，子进程 `sqltoolsservice`（.NET）在但无产出，挂 26 分钟仍不退出。
  重试一次，依旧 0 字节卡死——不是偶发，是该库稳定复现。

## Root Cause

`mssql-scripter` 底层的 `sqltoolsservice`（.NET）在脚本化 `_preprod` 库时挂起，
推测被库内某个特定对象定义卡住（该库相对 replicated 多了 Go 重构新增的
`casbin_rule`/`schema_migrations`/`sys_*` 等表）。具体哪个对象未深究——
因为结构对比本就不必依赖 scripter。

附带坑：macOS 自带没有 `timeout`/`gtimeout`，给 scripter 加超时保护这条路也不顺。

## Solution

放弃 scripter，**直接连库查 `INFORMATION_SCHEMA.COLUMNS`**，两库用同一条 SQL、
同一口径输出列元数据，再用脚本逐表逐字段比对。这比"导脚本再正则解析"更精确
（直接读 SQL Server 自己记录的类型/长度/精度/可空性），且零格式噪音、不会卡死。

导出列元数据（对每个库各跑一次）：

```sql
SET NOCOUNT ON;
SELECT
    t.TABLE_SCHEMA + '.' + t.TABLE_NAME AS tbl,
    c.ORDINAL_POSITION AS pos,
    c.COLUMN_NAME AS col,
    c.DATA_TYPE
      + CASE
          WHEN c.DATA_TYPE IN ('varchar','char','varbinary','binary','nvarchar','nchar')
            THEN '(' + CASE WHEN c.CHARACTER_MAXIMUM_LENGTH = -1 THEN 'max'
                            ELSE CAST(c.CHARACTER_MAXIMUM_LENGTH AS varchar(12)) END + ')'
          WHEN c.DATA_TYPE IN ('decimal','numeric')
            THEN '(' + CAST(c.NUMERIC_PRECISION AS varchar(12)) + ',' + CAST(c.NUMERIC_SCALE AS varchar(12)) + ')'
          WHEN c.DATA_TYPE IN ('datetime2','time','datetimeoffset')
            THEN '(' + CAST(c.DATETIME_PRECISION AS varchar(12)) + ')'
          ELSE ''
        END AS coltype,
    c.IS_NULLABLE AS is_nullable
FROM INFORMATION_SCHEMA.TABLES t
JOIN INFORMATION_SCHEMA.COLUMNS c
  ON c.TABLE_SCHEMA = t.TABLE_SCHEMA AND c.TABLE_NAME = t.TABLE_NAME
WHERE t.TABLE_TYPE = 'BASE TABLE'
ORDER BY tbl, pos;
```

```bash
sqlcmd -S 192.168.2.20 -U sa -P "$PW" -C -d "$DB" -h -1 -W -s $'\t' -i dump_cols.sql -o cols_$DB.tsv
```

对比时把两边类型表达归一后逐字段 diff，几个必须处理的**口径差异**（否则全是假差异）：

- `numeric(6)` 与 `numeric(6,0)` 等价 → 统一补 `,0`
- 不同导出工具会带/不带 `DEFAULT`、`NOT FOR REPLICATION`、`IDENTITY` 种子 → 对比核心结构时剥离
- 大小写、`[]` 包裹、长度括号内空格 → 全部归一

## Verification

- 两库各导出 5943 / 6419 行列元数据，对比得 50 表差异 + 105 列差异，结果干净可解释。
- 交叉验证：同一库前后两天的两份 SSDT 导出（replicated 新旧）归一后 diff = 0，
  证明解析与归一化对多种格式完全对齐。

## Prevention / 复用要点

- **结构对比首选直连 `INFORMATION_SCHEMA`，不要先导脚本再解析**——更准、更快、不挂。
  scripter/SSMS 脚本只在需要索引、约束、默认值、触发器等完整 DDL 时才用。
- scripter 卡死先看 `ps -o pid,stat,%cpu,etime`：`S` + `0.0%CPU` + 文件 0 字节 = 挂起，
  别傻等，杀掉 `mssql-scripter` 与 `sqltoolsservice` 进程重来或换路。
- macOS 给命令加超时：自带无 `timeout`，需 `brew install coreutils` 用 `gtimeout`，
  或后台跑 + 自己监控文件增长。
- 相关产物与脚本见 `mssql-ref/sql/`（`columns_*.tsv`、`schema_diff_*.tsv`、`import_into_preprod_*.sql`）。

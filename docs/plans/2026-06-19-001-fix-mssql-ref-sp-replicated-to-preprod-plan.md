---
title: 修复 mssql-ref 各库 SP 中 medicalassistance_replicated 跨库引用改名为 _preprod
server: mssql-ref
status: in-progress
created: 2026-06-19
tags:
  - mssql
  - stored-procedure
  - cross-database-reference
  - database-issues
---

# 修复 mssql-ref 各库 SP 跨库引用 `medicalassistance_replicated` → `medicalassistance_preprod`

## 背景

`mssql-ref`（`192.168.2.20`，PVE 上 Ubuntu VM，承载 MAS 老系统参考数据库）上，
多个业务库的存储过程（SP）定义里以三段式 `库名.dbo.表名` 跨库引用了
**`medicalassistance_replicated`** 这个库。

但该 VM 当前库列表里**并不存在** `medicalassistance_replicated`，只存在
`medicalassistance_preprod`（即老的 `medicalassistance` 库改名后的结果）。
因此这些跨库引用在本机执行时会因找不到目标库而**断链失败**。

> 排查纠偏记录：最初用 `LIKE '%medicalassistance%' AND NOT LIKE '%..._preprod%'`
> 统计「裸名 medicalassistance」，得到 insular 70 / masprepaid 14 / preprod 21 / maswebkit 13。
> 抽样后发现这些命中**全部是 `medicalassistance_replicated`**（子串包含 `medicalassistance`），
> 真正裸名三段式引用（`medicalassistance.` / `[medicalassistance]`）逐库统计**均为 0**。
> 故本工程的真实目标不是「裸名→_preprod」，而是「`_replicated`→`_preprod`」。

## 目标终态

把全部 SP 定义里的 `medicalassistance_replicated` 替换为 `medicalassistance_preprod`，
与 `maswebkit` 库中已经改好的 469 处保持一致，消除断链。

- **环境**：就在 `mssql-ref`（`192.168.2.20`）上直接改，改完即生效。按生产对待：先备份、可回滚。
- **范围**：3 个库共 **97 个 SP**（见下表；`medicalassistance_preprod` 库自身已为 0，无需改）。
- **替换规则**：子串 `medicalassistance_replicated` → `medicalassistance_preprod`。
  同时覆盖带方括号写法 `[medicalassistance_replicated]`（核心子串一致，直接替换子串即可）。

## 待改清单（按库，命中 SP 数）

| 库 | 引用 `_replicated` 的 SP 数 | 状态 |
| --- | :-: | --- |
| `insularsalesportal` | 70 | 待改 |
| `masprepaid` | 14 | 待改 |
| `maswebkit` | 13 | 待改 |
| **合计** | **97** | |

> 注：以上为「定义中含 `medicalassistance_replicated` 的 SP 个数」；
> 单个 SP 内可能有多处引用，实际替换次数 > 97。

## 已确认的事实

- 引用形态统一为 `medicalassistance_replicated.dbo.<tbl*>` 三段式；存在个别 `[medicalassistance_replicated].dbo.` 方括号写法。
- 真正裸名引用（`medicalassistance.` / `[medicalassistance]`）逐库均为 0。
- 目标库 `medicalassistance_preprod` 存在 384 张 `tbl*` 表，抽查的 `tblagents/tblcompany/tbldoctors/tblmembers/tblusers` 均存在。
- SA 密码在 VM 内 `/root/mssql-secrets.env`（`sudo cat`）。sqlcmd 路径 `/opt/mssql-tools18/bin/sqlcmd`，需 `-C` 跳过证书校验。

## 执行步骤

### 阶段 0：备份（前置，必做）

- [ ] 用 `bcp` 或脚本导出 3 个库全部待改 SP 的当前定义到 VM 内备份目录
      （文件名带日期，例如 `/restore/backup/sp-replicated-fix-20260619/<db>/<proc>.sql`），
      作为回滚源。
- [ ] 或对 3 个库做一次完整数据库备份（`BACKUP DATABASE`）留底（确认磁盘空间足够，老库文件在 `/restore` 第二块盘）。
- [ ] 把备份位置和清单记录到本 plan / `docs/operations/mssql-ref.md`。

### 阶段 1：生成精确清单与替换脚本

- [ ] 逐库导出含 `medicalassistance_replicated` 的 SP 完整名单（schema.name），核对计数 = 70/14/13。
- [ ] 对每个命中 SP，用 `OBJECT_DEFINITION` 取定义，
      字符串 `REPLACE(definition, 'medicalassistance_replicated', 'medicalassistance_preprod')`，
      生成 `ALTER PROCEDURE` 脚本（保留原 SP 头，仅替换库名子串）。
- [ ] 人工抽查若干生成脚本，确认：
  - 只替换了库名，未误伤其它含该子串的字面量；
  - 方括号写法被正确处理；
  - 没有把注释 / 字符串里本应保留的内容改掉（理论上无，但需确认）。

### 阶段 2：分批执行替换

- [ ] 先改 **`maswebkit`（13 个）** 作为试点——量最小、且该库已有 469 处改好的先例可比对。
- [ ] 验证试点（见阶段 3）通过后，再改 `masprepaid`（14）、`insularsalesportal`（70）。
- [ ] 每批执行前确认当前在 `mssql-ref`，执行后立即跑该批的验证查询。

### 阶段 3：验证

- [ ] 重新统计：3 个库中 `medicalassistance_replicated` 命中数应全部 = 0。
- [ ] 统计 `medicalassistance_preprod` 命中数应相应增加。
- [ ] 抽查若干改过的 SP，确认能成功编译（`ALTER` 成功即语法通过）。
- [ ] 抽选 1~2 个只读 SP 实际执行，确认能跨库取到 `medicalassistance_preprod` 的数据、不再断链。
- [ ] 核对被引用的 `tbl*` 表在 `medicalassistance_preprod` 中均存在（阶段 1 清单里收集到的表名逐一比对）。

### 阶段 4：收尾

- [ ] 在 `docs/operations/mssql-ref.md` 追加本次操作记录（时间 / 原因 / 影响 / 回滚 / 做了什么 / 验证结果）。
- [ ] 如有可复用经验或踩坑（如「子串统计误把 `_replicated` 当裸名」），另写 `docs/solutions/mssql-ref/`。
- [ ] 更新本 plan `status: done`。

## 回滚方式

- 任一 SP 改坏：用阶段 0 备份里对应的原始 `.sql` 重新 `ALTER`（或 `DROP`+`CREATE`）还原。
- 整库层面：用阶段 0 的 `BACKUP DATABASE` 还原（仅在确需且确认不影响其它使用方时）。
- 因仅改 SP 定义、不动表结构与数据，回滚风险低。

## 待确认 / 风险

- [ ] `medicalassistance_replicated` 与 `medicalassistance_preprod` 是否确为同一套数据？
      若两库 schema 有差异（列名/表名不同），仅改库名可能导致 SP 引用到不存在的列。
      → 阶段 1 收集表名后，与目标库实际表/列比对。
- [ ] 是否还有 SP 之外的对象（视图 / 函数 / 触发器）也引用了 `medicalassistance_replicated`？
      → 本 plan 目前只覆盖 `sys.procedures`，需补查 `sys.sql_modules` 全量（含 view/function/trigger）。
- [ ] 这些库的 SP 是否还有别处（IIS 应用、其它 VM）以无后缀 / `_replicated` 维护的"权威源"？
      若有，VM 上直接改可能被后续部署覆盖。→ 需向用户确认 SP 的维护来源。

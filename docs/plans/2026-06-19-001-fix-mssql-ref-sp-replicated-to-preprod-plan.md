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

## 待改清单（按库，命中对象数）

> 2026-06-19 第 1 步只读核对后更新：补上原先漏算的 1 个标量函数；
> 总对象数从 97 修正为 **98**（97 SP + 1 函数）。

| 库 | 引用 `_replicated` 的对象 | 数量 | 状态 |
| --- | --- | :-: | --- |
| `insularsalesportal` | SP | 70 | 待改（含 1 个 B 类例外，见下） |
| `masprepaid` | SP | 14 | 待改 |
| `maswebkit` | SP 13 + 标量函数 `GetTotalIBNR` 1 | 14 | 待改 |
| **合计** | | **98** | |

> 注：以上为「定义中含 `medicalassistance_replicated` 的对象个数」；
> 单个对象内可能有多处引用，实际替换次数 > 98。

### 分两批处理

| 批次 | 对象数 | 处理 |
| --- | :-: | --- |
| **A 类·可直接改** | 97（96 SP + 1 函数）| 引用的表在目标库均存在，`_replicated` → `_preprod` 即修复 |
| **B 类·需先决策** | 1 | `insularsalesportal.sp_getretailfranchisingdetails`，引用了目标库**不存在**的表 `tblprovidertemplate`，改名解决不了，先搁置待用户决策 |

## 执行进度（2026-06-19 实际改库）

| 库 | 结果 | 说明 |
| --- | --- | --- |
| `maswebkit` | ✅ 14/14 成功 | `_replicated` 残留 0；改过对象对 `_preprod` 的 9689 处引用全部解析 OK |
| `masprepaid` | ⚠️ 13/14 成功 | 1 个失败 → 见 C 类 |
| `insularsalesportal` | ✅ 66/66 成功 | 66 个 A 类全部 ALTER 改名成功，残留 `_replicated` = 4（即 1 缺表 + 3 缺列例外）；只读 SP `sp_getmasagents` 实测跨库取数 OK |

### insularsalesportal 全量预检结论（2026-06-19）

为避免再逐个撞 ALTER 错误，对 70 个对象做了**全量试编译预检**：游标取每个 SP 的
`OBJECT_DEFINITION`，`_replicated`→`_preprod` 替换后，在事务里 `DROP PROCEDURE` + 用改名
定义 `CREATE`，捕获错误后 `ROLLBACK`（库零改动，验证后 `_replicated` 计数仍 70、SP 总数仍 147）。

结果：**66 净改 + 1 缺表（B 类）+ 3 缺列（C 类）**。

| 类别 | 数量 | 对象与缺失项 |
| --- | :-: | --- |
| **A 类·可直接改** | 66 | 引用表/列全在目标库，改名即修复 |
| **B 类·缺表** | 1 | `sp_getretailfranchisingdetails` → `tblprovidertemplate` 不存在 |
| **C 类·缺列** | 3 | `sp_getiortapayordetails`（`tblagents.franchisecode`）、`sp_getproducttypes`（`tblproductlines.iorta`）、`sp_getroomaccommodation`（`tblbenefitsa.iorta`） |

**重要发现——试编译只抓缺列、抓不到缺表**：SQL Server 对**跨库三段式引用的表**走延迟名称
解析，缺表在 ALTER/CREATE 编译期**不报错**（运行时才断链），故 B 类 `sp_getretailfranchisingdetails`
在试编译里反而通过（计入 67 个 OK）；缺**列**则编译期立即报 Msg 207。
因此另补了一道**缺表核对**：把 insular 70 SP 引用的 29 张去重表与目标库逐一比对，
确认只有 `tblprovidertemplate` 1 张缺失，无新增缺表。

> 全三库例外汇总（B 缺表 / C 缺列，单纯改库名解决不了，均需补表/补列或改写 SP）：
> - **B 类（缺表）** ×1：`insularsalesportal.sp_getretailfranchisingdetails` → `tblprovidertemplate`
> - **C 类（缺列）** ×4：
>   - `masprepaid.sp_checkprepaidcancellationdate` → `tblcompanyclasses.cancellationdays`
>   - `insularsalesportal.sp_getiortapayordetails` → `tblagents.franchisecode`
>   - `insularsalesportal.sp_getproducttypes` → `tblproductlines.iorta`
>   - `insularsalesportal.sp_getroomaccommodation` → `tblbenefitsa.iorta`
> 缺失列经查在目标库 `medicalassistance_preprod` 整库均不存在，非单表偶缺。

### 新增 C 类·目标库缺列（改名后编译失败）

- `masprepaid.sp_checkprepaidcancellationdate`：第 32 行 `SELECT DATEADD(DAY, cancellationdays, ...) FROM medicalassistance_replicated.dbo.tblcompanyclasses`。
  目标库 `medicalassistance_preprod.dbo.tblcompanyclasses` 存在（56 列），但**无 `cancellationdays` 列** → ALTER 报 Msg 207，已跳过未改，保持原 `_replicated` 定义。
- **教训**：第 1 步只比对了"表是否存在"，未比对"列是否存在"。`maswebkit` 凑巧列全（9689 引用全 OK），`masprepaid` 撞上缺列。`insularsalesportal`（70 个、引用面更广）执行前必须先做**列级差异全量核对**。

> 至此例外分三类：
> - **B 类（缺表）**：`insularsalesportal.sp_getretailfranchisingdetails` → `tblprovidertemplate` 不存在
> - **C 类（缺列）**：`masprepaid.sp_checkprepaidcancellationdate` → `tblcompanyclasses.cancellationdays` 不存在
> - 两类都需补表/补列或改写 SP，单纯改库名解决不了。

## 已确认的事实

- 引用形态统一为 `medicalassistance_replicated.dbo.<tbl*>` 三段式；存在个别 `[medicalassistance_replicated].dbo.` 方括号写法。
- 真正裸名引用（`medicalassistance.` / `[medicalassistance]`）逐库均为 0。
- 目标库 `medicalassistance_preprod` 存在 384 张 `tbl*` 表，抽查的 `tblagents/tblcompany/tbldoctors/tblmembers/tblusers` 均存在。
- SA 密码在 VM 内 `/root/mssql-secrets.env`（`sudo cat`）。sqlcmd 路径 `/opt/mssql-tools18/bin/sqlcmd`，需 `-C` 跳过证书校验。

### 第 1 步只读核对结论（2026-06-19）

- **对象总数 98**：97 SP + maswebkit 标量函数 `GetTotalIBNR`（补查 view/function/trigger 发现，原 plan 只统计 SP 漏掉了它）。其它库非 SP 对象无引用。
- **被引用表共 40 个去重表名**，与目标库 `medicalassistance_preprod` 实际表比对：**39 个存在，1 个缺失**。
- **缺失表 `tblprovidertemplate`**：目标库无此表，也无名字相近表（已查 `tblprovider*` 18 张，无 template）。唯一引用者为 `insularsalesportal.sp_getretailfranchisingdetails` → 列为 B 类。
- 风险点「两库 schema 是否一致」已就表名维度验证完毕（仅 1 张缺失）；列级差异尚未逐一比对，但 39 张表既存在，盲改风险已大幅降低。

## 执行步骤

### 阶段 0：备份（前置，必做）

- [x] 已导出 3 个库全部待改 SP 原始定义到 `/restore/backup/sp-replicated-fix-20260619/<db>/<proc>.sql`
      （insular 70 + masprepaid 14 + maswebkit 14），作为回滚源。insular 的 ALTER 即由这批备份
      经 `sed`（CREATE→ALTER + 库名替换）生成。
- [ ] （未做）整库 `BACKUP DATABASE`——因仅改 SP 定义、不动表与数据，单 SP 备份已足够回滚，故略。
- [x] 备份位置记录在本 plan 与 `docs/operations/mssql-ref.md`。

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

- [x] `maswebkit` 14 个全成（试点，先例 469 处可比对）。
- [x] `masprepaid` 13 个成（1 个 C 类缺列跳过）。
- [x] `insularsalesportal` 66 个成（A 类全成；4 个 B/C 类例外跳过）。
- [x] 每批执行后立即跑验证查询，全部通过。

### 阶段 3：验证

- [x] 重新统计：3 个库中 `medicalassistance_replicated` 命中数 = **5**（不可改的例外：1 缺表 + 4 缺列），A 类全部清零。
- [x] 统计 `medicalassistance_preprod` 命中数相应增加（insular 改后 = 74）。
- [x] 改过的 SP 全部成功 ALTER（编译通过）：maswebkit 14 + masprepaid 13 + insular 66 = 93。
- [x] 只读 SP 实际执行验证跨库取数：insular `sp_getmasagents` 实测返回数据、不再断链。
- [x] 被引用表存在性核对：insular 29 张引用表仅 `tblprovidertemplate` 缺失（B 类），其余均存在。

### 阶段 4：收尾

- [x] 在 `docs/operations/mssql-ref.md` 追加本次操作记录（时间 / 原因 / 影响 / 回滚 / 做了什么 / 验证结果）。
- [x] 踩坑「试编译只抓缺列不抓缺表（延迟名称解析）」已沉淀：`docs/solutions/mssql-ref/database-issues/sp-recompile-precheck-misses-missing-tables-2026-06-19.md`。
- [x] A 类全部改完，B/C 类例外按用户决策**全部跳过**，本工程主体完成；status 保持 in-progress 直到例外待办闭环（补表/补列）。

## 遗留待办例外清单（B 缺表 / C 缺列，5 个对象，按用户决策暂跳过）

这 5 个 SP 保持原 `medicalassistance_replicated` 定义不动（本就断链，改库名也修不了），
待后续从源库同步 schema（补表 / 补列）后再统一改名。逐个待办：

| 库 | SP | 类别 | 缺失项（在目标库 `medicalassistance_preprod`） |
| --- | --- | --- | --- |
| `insularsalesportal` | `sp_getretailfranchisingdetails` | B·缺表 | `tblprovidertemplate` 整表不存在 |
| `insularsalesportal` | `sp_getiortapayordetails` | C·缺列 | `tblagents.franchisecode` |
| `insularsalesportal` | `sp_getproducttypes` | C·缺列 | `tblproductlines.iorta` |
| `insularsalesportal` | `sp_getroomaccommodation` | C·缺列 | `tblbenefitsa.iorta` |
| `masprepaid` | `sp_checkprepaidcancellationdate` | C·缺列 | `tblcompanyclasses.cancellationdays` |

闭环条件（任一）：
- 从权威源库把 `tblprovidertemplate` 表、以及 `franchisecode`/`iorta`/`cancellationdays`
  列补进 `medicalassistance_preprod` → 再对这 5 个 SP 跑改名（脚本已就绪，去掉跳过名单即可）。
- 或确认这些 SP 在新系统已废弃 → 直接丢弃，不再维护。

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

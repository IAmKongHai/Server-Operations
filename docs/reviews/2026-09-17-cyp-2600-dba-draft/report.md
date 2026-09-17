# CYP-2600 DBA 审核草案本地审查

## Scope and intent

范围：Terraform `169de0eeabf64e27bcaf11414a30cc338d09b9fc` 后本轮新增的 SQL 审核包及三仓交接状态更新；不重审或改写上一轮 backend/Terraform 运行时代码。用户明确要求“最终镜像未选定，先准备审核草案”，禁止执行生产写入。

依据 Server 实施计划 U1/U3、R1/R2/R3/R8/R9/R10，按 ce-code-review 检查正确性、权限边界、误执行/回滚失败情景和仓库规范。遵循用户 AGENTS.md 的“Subagent / Parallel 在主线程顺序执行”映射，全部在主线程完成；没有独立 reviewer、跨模型外传或二审，不宣称多方一致。

## Actionable Findings

本轮交付范围内无未修复问题。核对时纠正 diagram 执行上下文描述：原始值为 principal_id=1（dbo），不是 -2（OWNER）；module-evidence 保留原值。仅凭该上下文不能证明模块可被滥用，正文和有效权限继续待 DBA 审核。

下列问题属于已明确保留的生产门禁，不因草案通过静态审查而消失：

| 门禁 | 证据与处理 |
|---|---|
| O1 最终版本 | digest 未选定；matrix version_signed_off=false，源码 SHA 仅候选 |
| O2 对象与依赖 | 两张 SUP 表在带过滤的 inventory 中缺失，未生成 GRANT；模块/动态 SQL/密钥链与全部列权限需签收 |
| O2 继承与归属 | 7 login / 同名 user 在快照缺失；执行窗口仍要复查，旧 user/owner 全量映射未闭合；35 项 diagram DENY 仅候选 |
| U3/U6 执行验证 | 只读补证 SQL 尚未运行，变更 SQL 是全注释草案；真实受限 SQL、重复执行、部分失败回滚未验证 |
| O3/O4/U7 | KV/RBAC、SUP mTLS、ACA 路径、发布窗口及生产写入批准仍未闭合 |

## Coverage

- 数据来源：重新计算 ZIP/六 JSON/原 SQL SHA-256；验证 ZIP CRC、manifest 字节数、102 个结果集和各集实际行数；原执行 SQL 与仓库 inventory.sql 字节一致。
- 98 行权限矩阵逐行匹配 schema/object/type；96 行匹配、2 行暂扣；5 行指定列均存在；10 行模块需求的依赖仍 pending；23 个模块 hash/context 记录与原始快照一致。
- 两个变更 SQL 去除注释后均只有无条件 THROW，无 GO；全部 96 组对象 GRANT 有对应逆序 REVOKE；7 个 CREATE LOGIN、9 个 CREATE USER 不涉及 MAS/UAT 主体。快照缺失不作为执行时幂等判断。
- 35 项 diagram DENY 均对应所需库的实际 public EXECUTE；回滚保留主体时不撤 DENY，避免重新继承 public 能力。DROP 仅为“回执证明本次新建 + SID 一致 + 无漂移/消费者 + 已批准”的候选。
- 不含 db_owner / 全库角色 / schema 授权 / ALTER USER / ALTER LOGIN / 改库 / 旧主体清理；不授 sys_app_settings 或 tblpushemailnotification。OAuth / SUP 姓名查询 / 企业单列 UPDATE / OUTPUT(detno) 窄权限已检查。
- 补证 SQL 静态扫描仅 SELECT/SET/IF/THROW，未含业务 DML、DDL、EXEC、SELECT *、密码 hash、crypt_property 或模块正文投影；补查未使用 is_ms_shipped 排除条件。SQL Server 2017 实际解析/运行尚未验证。
- 源码补查确认 MemberPassword 无主键返回属性，franchisingagents 为 map Create；未猜加 SELECT(detno)。没有把此静态证据当成最终驱动生成 SQL 的测试。
- 无应用行为改动，因此不新增或重跑应用/Terraform 单元测试；替代验证为上述离线完整性、结构与差异检查。生产 SQL / TCP / ACA / 密钥与业务语义仍未测。
- Server main、iCare develop、Terraform 已有 CYP-2600 分支分别按归属提交；原始受控 JSON 不入库，既有无关修改不纳入提交。无远端操作、push 或 PR。

## Verdict

**Ready to merge（仅本轮审核材料）；生产 Not ready。** 用户要求的审核草案已齐全，可以交 DBA 逐项审阅；U3 最终可执行交付及整个 U1–U8 计划尚未完成。没有以缺少生产批准为由执行写入，也没有把草案当作完成上线。

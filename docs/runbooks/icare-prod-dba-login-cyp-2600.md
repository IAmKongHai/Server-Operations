# CYP-2600：PROD SQL login DBA 执行清单

整理日期：2026-09-16；更新：2026-09-17。状态：**原始元数据盘点已完成；待 DBA 依赖/有效权限审核、映射确认及写入批准，尚未执行建号**。完整结果和执行身份见[盘点回执](../operations/ihc-db-uat.md)。

用户已选择由 DBA 执行清单。此选择确定执行分工，不代表批准下文待定账号、权限、KV 调整或上线。本文没有密码，也不包含可直接批量执行的写入脚本。

**2026-09-17 盘点后审核包：** 用户确认最终镜像尚未选定，先制作审核草案。入口在 `/Users/konghai/Code/Project/iCare/terraform/.worktrees/terraform-cyp2600-public-db-isolation/docs/deployment/sql/cyp-2600-public-logins/README.md`（隔离工作区，尚未合并）。请先读 `metadata-review.md` 与 `followup-findings.md`，再审 `permission-matrix.json`、`create-and-grant.sql`、`rollback.sql`；变更语句全为注释且文件开头无条件 THROW，禁止直接执行。

**2026-09-22 补证：** VPN TCP 以 `mas_ref_owner`（db_owner，非 sysadmin）跑完 followup SELECT 批次。两张暂扣表确认不存在，matrix 改为 `object_absent_do_not_grant`。官方脚本 sysadmin THROW 仍未满足，执行窗口须用获准 DBA 身份复查 owner login 映射。

**2026-09-22 列收口：** 全部业务表 SELECT/UPDATE 已按候选源码写入列清单（含 SUP 39 张）；INSERT/DELETE 仍表级。两张缺表不 GRANT。草案仍禁止执行。

**2026-09-22 sysadmin owner 映射：** Azure Run Command 确认非 sa 库 owner 为 `dcandaya` / `eapelegrino` / `ihc-db-uat\ihcadmin`。不得接管这些主体。七个候选 login 仍缺失。

本机复核 102 个结果集通过；七候选 login 在 server 级均缺失，同名 user 在六库也均缺失。98 行权限需求中 96 行匹配对象；主库 `tblprovidertemplate`、`tblretailquotationbenefitclass` 因原查询带 `is_ms_shipped` 过滤尚待补证，不能直接判定表不存在或创建新表。主库和 WebKit 的 public 可执行七个以 dbo（execute_as_principal_id=1）运行的 diagram 例程；草案提出仅对新 user 的 DENY，待 DBA 审核，不能全局撤销 public 权限。模块 hash、密钥名称与 CALLER 元数据已收录，动态 SQL、密钥链和最终有效权限仍未签收。

审核包本地提交：Terraform `f1c6513`。本轮静态检查与边界见 [草案审查记录](../reviews/2026-09-17-cyp-2600-dba-draft/report.md)；未执行补证 SQL、建号或授权。

2026-09-16 补充：[五个公网 profile 的对象与动作取证](icare-prod-public-db-permissions-cyp-2600.md)。代码核对已发现 SUP 主库写入及邮件凭据读取冲突；先审阅该报告，再收口最终授权，不能直接照旧共享账号清单执行。

公网账号隔离的实施顺序、配置拆分、验收及回滚以[实施计划](../plans/2026-09-16-1440-fix-cyp-2600-public-db-isolation-plan.md)为准。本清单中 MAS 与 Operations 的交付另计，不能因公网计划完成一并记为通过。

## 1. 目标与影响

为 iCare PROD 建立独立于 UAT 的 SQL login，并使用 PROD Key Vault 中对应的密码。登录成功后只验证连接和权限，不运行 seed/migrate，不写业务数据。

| 项目 | 范围 |
| --- | --- |
| SQL 实例 | `ihc-db-uat`，`10.100.0.4:1433`，交接记录为 SQL Server 2017 |
| 业务 catalog | `medicalassistance_preprod`、`maswebkit_preprod`、`insularsalesportal_preprod`、`masprepaid_preprod`、`authprovidermasuat` |
| 运维 catalog | `operations`；是否存在、可用须 DBA 复核，不能用业务库代替 |
| PROD Key Vault | `icare2-prod-icare2-kv`，通过现有私网路径访问 |
| 连接加密配置 | 当前 tfvars 为 `disable`；本次不修改 TLS 配置 |
| 明确排除 | 现网 SQL `10.0.0.5` / `172.0.0.6`；修改 UAT principal；恢复数据库；业务 schema/data 变更；Terraform apply |

五个业务库同时被旧 preprod、UAT 和未来 PROD 使用。新增身份不应改变现有会话或业务数据；修改已有账号密码、SID、权限会影响已有使用者，不能顺带执行。发生同名冲突时停止并确认归属。

2026-09-16 整理时仅核对本地资料，未重新连接 SQL、runner 或 KV。先前交接记录中 `.env.preprod` 账号能连接，但 `sysadmin`、`ALTER ANY LOGIN`、`CONTROL SERVER`、`VIEW ANY DEFINITION` 均为 0；该账号查询未见目标 login，**不能证明 login 不存在**。2026-09-17 的 sysadmin 盘点结论另见本清单末尾。

## 2. 当前映射与必须先解决的缺口

以下是本地 Terraform `2769f44753834b99db205ed3d854a49043d2709f` 的声明，不代表已部署状态。`prod.workloads.tfvars` 和 `prod.operations.tfvars` 均未填写 `key_vault_secret_uris`；下表 secret 名来自模块绑定和 9 月 10 日写入记录，最终 PROD URI 尚待闭合。

| 消费方 / 连接 | 当前 login | catalog | 模块密码引用 | 写入前处理 |
| --- | --- | --- | --- | --- |
| MAS api / worker 主库 | `mas_prod_owner` | `medicalassistance_preprod` | `db-password` | 保留为 MAS 专用候选；名称含 owner 不代表应授 `db_owner` |
| MAS WebKit | `mas_prod_owner` | `maswebkit_preprod` | `webkit-db-password` | 与主库同一 login，须统一密码来源或拆分 login |
| MAS SalesPortal | `mas_prod_owner` | `insularsalesportal_preprod` | `salesportal-db-password` | 同上 |
| ecom 业务 | `mas_prod_owner` | 主库连接及跨库访问 `masprepaid_preprod` | `db-password` | 改为 ecom 独立最小权限身份 |
| sup 业务 | `mas_prod_owner` | 主库、SalesPortal；replicated 实际也指主库 | `db-password`、`salesportal-db-password` | 改为 sup 独立身份，相关连接须使用该身份一致的密码 |
| public app / hr / map | `mas_prod_owner` | `maswebkit_preprod` | `webkit-db-password` | 每个 profile 独立身份，只授 WebKit 必需对象权限，不持有 MAS 通用身份 |
| ecom OAuth | `ecom_oauth_reader_prod` | `authprovidermasuat` | `ecom-auth-db-password` | 核对 `dbo.oauth_clients`，只授所需读取权限 |
| sup OAuth | `sup_oauth_reader_prod` | `authprovidermasuat` | `sup-auth-db-password` | 同上；与 ecom reader 保持独立 |
| Operations API | `operations_owner` | `operations` | `key_vault_secret_uris["db_password"]` | PROD URI 未配置；不能把容器 secret 别名 `db-password` 当成 MAS 密码来源 |
| Operations edge / switch | `operations_edge_reader_prod` | `operations` | `operations-edge-db-password` | 待库交付及实际读取对象清单 |

同一 SQL 实例的 login 密码属于服务器级，不能按 catalog 配三个不同密码。历史记录称三个密码分别生成，但本轮未读取或比较值，**不将其必然不同写成已验证事实**。

`backend/AGENTS.md` 要求每个公网 profile 独立、最小权限账号，禁止复用主库通用账号；现有 Terraform 与 DBA 基线尚未满足。只修正密码一致性不能解决账号权限边界。

推荐由部署负责人确认以下映射，再交 DBA 写入：

- MAS 保留 `mas_prod_owner`，其各 catalog 连接统一引用一个已选定的 PROD 密码；优先调整引用，避免无必要地轮换现有 secret。
- ecom、sup 和 public 三个 profile 各自独立 login / secret；具体名称、对象权限和变量映射由应用负责人填齐，DBA 不自行猜定。
- 两个 OAuth reader 保持现有独立名字和 secret 引用。若单独交付这两项，须单独批准，不能据此宣告业务连接已就绪。
- `operations_owner` 位于另一实例时同名不等于共用身份；本目标实例若已有同名 login，先确认归属。写账号必须明确独立密码 URI，不能复用 edge 的只读身份。

交付表每行必须填齐：`profile → host:port → login → catalog/user → 对象及操作权限 → 完整 KV secret URI/版本 → 配置变更引用 → 审批人`。未确定的行保持待办，不纳入批量执行。

## 3. DBA 现在可执行的只读盘点

使用获准的 DBA 身份连接目标实例，先确认身份、主机和 metadata 可见性。下列查询不读取业务行或密码；结果按内部运维资料保管。不要导出 `sys.sql_logins.password_hash`。

```sql
SELECT @@SERVERNAME AS server_name,
       SERVERPROPERTY('ProductVersion') AS product_version,
       CONNECTIONPROPERTY('local_net_address') AS local_net_address,
       CONNECTIONPROPERTY('local_tcp_port') AS local_tcp_port,
       ORIGINAL_LOGIN() AS original_login,
       DB_NAME() AS current_database,
       IS_SRVROLEMEMBER('sysadmin') AS is_sysadmin,
       HAS_PERMS_BY_NAME(NULL, NULL, 'ALTER ANY LOGIN') AS can_alter_login,
       HAS_PERMS_BY_NAME(NULL, NULL, 'VIEW ANY DEFINITION') AS can_view_definition;

SELECT name, state_desc, user_access_desc, is_read_only,
       HAS_DBACCESS(name) AS current_account_has_access
FROM sys.databases
WHERE name IN (N'medicalassistance_preprod', N'maswebkit_preprod',
               N'insularsalesportal_preprod', N'masprepaid_preprod',
               N'authprovidermasuat', N'operations');

-- 最终批准的新账号名也须加入此过滤列表。
SELECT name, type_desc, is_disabled, default_database_name,
       CONVERT(varchar(170), sid, 1) AS sid_hex
FROM sys.server_principals
WHERE name IN (N'mas_prod_owner', N'ecom_oauth_reader_prod',
               N'sup_oauth_reader_prod', N'operations_owner',
               N'operations_edge_reader_prod');

SELECT r.name AS server_role, m.name AS member_name
FROM sys.server_role_members AS rm
JOIN sys.server_principals AS r ON r.principal_id = rm.role_principal_id
JOIN sys.server_principals AS m ON m.principal_id = rm.member_principal_id
ORDER BY r.name, m.name;

SELECT p.name AS grantee, sp.state_desc, sp.permission_name,
       sp.class_desc, sp.major_id
FROM sys.server_permissions AS sp
JOIN sys.server_principals AS p ON p.principal_id = sp.grantee_principal_id
ORDER BY p.name, sp.class_desc, sp.major_id, sp.permission_name;
```

在每个目标 catalog 分别运行以下查询，保存 user/SID、角色关系和显式权限快照；不要把新登录用户映射到旧系统已有 user。连接工具显示的实例和 catalog 必须与交付表一致。

```sql
SELECT DB_NAME() AS catalog_name, name, type_desc, default_schema_name,
       CONVERT(varchar(170), sid, 1) AS sid_hex
FROM sys.database_principals
WHERE type IN ('S', 'U', 'G', 'R')
ORDER BY name;

SELECT r.name AS database_role, m.name AS member_name
FROM sys.database_role_members AS rm
JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals AS m ON m.principal_id = rm.member_principal_id
ORDER BY r.name, m.name;

SELECT u.name AS grantee, p.state_desc, p.permission_name,
       p.class_desc, p.major_id, p.minor_id,
       CASE WHEN p.class = 1 THEN OBJECT_SCHEMA_NAME(p.major_id) END AS object_schema,
       CASE WHEN p.class = 1 THEN OBJECT_NAME(p.major_id) END AS object_name
FROM sys.database_permissions AS p
JOIN sys.database_principals AS u ON u.principal_id = p.grantee_principal_id
ORDER BY u.name, p.class, p.major_id, p.minor_id, p.permission_name;
```

元数据可见性受当前身份限制，空结果不能直接当成不存在。显式权限视图不包含固定角色的全部权限；DBA 还须核对角色继承、`public`/`guest`、对象/库所有权及有效权限，不能仅凭上述权限行批准写入。参见 Microsoft 的 [login 元数据可见性](https://learn.microsoft.com/ga-ie/sql/relational-databases/system-catalog-views/sys-server-principals-transact-sql?view=sql-server-ver15)、[有效权限说明](https://learn.microsoft.com/en-us/sql/relational-databases/security/authentication-access/determining-effective-database-engine-permissions?view=sql-server-ver17)。

## 4. 写入前必须返回并确认的材料

- [ ] DBA 姓名、执行窗口、审批人、目标实例核验结果。
- [ ] 每个 login 的“缺失 / 已存在且归属明确 / 冲突待查”状态，以及 user/SID 映射。
- [ ] 第 2 节交付表完整；部署负责人已给出对应配置修正，账号、密码引用与实际消费者一致。
- [ ] 应用负责人提供逐对象权限清单。OAuth reader 的候选为 `authprovidermasuat.dbo.oauth_clients` 的 `SELECT`；其余对象不能从旧账号宽泛角色照搬。
- [ ] MAS 所需 PII SP/UDF 和密钥访问已列入审核；只保留已批准的基础设施加解密原语，不因旧依赖清单出现业务 SP 就批量授 EXECUTE。
- [ ] 保存变更前的身份、SID、角色、权限、对象所有权快照及恢复脚本；确认所涉数据库有效恢复点和恢复负责人。备份/恢复不得影响三方共享库，本文不授权恢复数据库。
- [ ] KV 管理员确认读取路径、目标 secret 状态和版本；密码只在受控内存或批准的保密执行工具内使用，不进工单、脚本仓库、命令行参数、终端记录或聊天。
- [ ] 已审核实际建号、建 user、授权及反向操作清单，并获用户明确写入批准。最终名称和对象权限未定前不生成“一键建全部账号”脚本。

## 5. DBA 获批后的执行顺序

1. 重新核对主机、catalog 和执行身份，确认期间没有新增同名 login/user。备份快照必须对应本次窗口。
2. 读取已批准的 PROD secret，记录 URI/版本即可。不得拷贝 UAT 密码，不自动给现有应用账号提权；KV 值变更由另外的已批准操作完成。
3. 只为交付表中缺失的账号创建 SQL login，并按已批准的密码策略设置。已有 login 不自动重置密码、删除重建或改 SID，需先核实归属及批准范围。
4. 只在所需 catalog 建独立 user，绑定正确 login/SID，再按对象权限清单授权。不给应用账号 `sysadmin`、`CONTROL SERVER`、建号权限或默认 `db_owner`。最小权限清单不足时停止，不以全库权限临时顶替。
5. OAuth 两个 reader 仅交付批准的读取权限；ecom 的跨库访问必须沿其实际连接身份验证。不得为省授权开启 `TRUSTWORTHY` 或跨库所有权链。
6. 逐行完成第 6 节验收，记录成功、失败和未测项。`operations` 未交付时单独标记 not-Ready，不建库补洞，不将其连接指向 UAT SQL MI。

## 6. 验收和回执

- [ ] 每个最终 login 使用自己的密码建立真实连接，核实 `ORIGINAL_LOGIN()`、`DB_NAME()` 和 user/SID；管理员模拟身份不能替代密码登录验收。
- [ ] 从 PROD 工作负载路径验收目标 catalog。VPN 本机和 runner 成功只作为阶段证据；ACA 尚未部署时明确记“工作负载路径未验收”，不为验收擅自部署。
- [ ] 以最终账号检查对象有效权限。OAuth reader 可用 `SELECT TOP (0) id FROM dbo.oauth_clients` 验证读取授权，不取回 client secret；同时验证没有 INSERT/UPDATE/DELETE 权限。
- [ ] 验证写权限用有效权限查询，不以真实 INSERT/UPDATE/DELETE 测试。连接成功不等于业务功能验收通过。
- [ ] 核对各公网 profile 无 MAS 主库通用身份、无多余 catalog 权限；PII 原语权限使用批准的无业务数据测试方式验证，业务记录互读另走发布验收。
- [ ] 账号和权限调整未改动旧 preprod/UAT 的 principal、密码或 SID。
- [ ] seed 保持关闭；Firebase、备份恢复演练及 U4 部署门禁单独验收，不能因 login 完成一并勾选。

DBA 回执使用以下格式，不附密码或完整连接串：

| 时间（YYYY-MM-DD HH:mm CST） | 执行人 / 审批引用 | login / catalog | 操作和权限差异 | secret URI/版本 | 验证来源 / 结果 | 未完成项 / 回滚记录 |
| --- | --- | --- | --- | --- | --- | --- |
| 待填写 | 待填写 | 待填写 | 待填写 | 待填写 | 待填写 | 待填写 |

实际变更回填 iCare 根仓 `docs/deployment/prod-ops-log.md`（`develop`，提交含 CYP-2600）；通过 Server 仓开展的服务器操作另按约定记 `docs/operations/`。本文的建号与授权部分仍是待执行清单；已完成的只读盘点见末尾回执链接。

## 7. 回滚

只回滚本次变更，不恢复整库来撤销建号。先停止继续授权，记录已执行步骤与原因。若账号已被运行中应用使用，先与部署负责人确认影响和凭据切回方案，不能直接停用或删除。

按变更前快照撤销本次新增授权和角色成员关系；确认新 user 不拥有 schema/对象后，才按获批的反向清单删除本次新 user 和 login。已有身份、SID、角色关系和旧系统账号保留。密码或 KV 版本如需回退，必须另有批准和可用旧版本，不在此次建号操作中临时轮换。

## 8. 依据与核验边界

以下路径相对独立的 iCare 根仓，**不在 Server 仓内**。整理时 iCare HEAD 为 `c6d026a56c00225591b3baa3e18aa022926c30d0`，Terraform HEAD 见第 2 节；执行前复核最新配置。

- `terraform/docs/deployment/prod-dba-handoff.md`：目标实例、五库、独立 login、备份与连接池基线；共享账号部分存在本清单指出的冲突。
- `terraform/environments/prod.workloads.tfvars`、`prod.operations.tfvars`：PROD 账号及 catalog；部署开关仍关闭。
- `terraform/workloads/modules/container_apps/main.tf`：`database_env`、`ecom/sup_runtime_env`、secret bindings、`public_webkit_db_env` 是实际映射依据。
- `terraform/operations/backend.tf`、`variables.tf`：Operations 密码从输入 URI map 读取，默认空 map 不能当作已配置。
- `backend/AGENTS.md` 公网红线：每个 profile 独立账号、只授必要对象；主库与公网边界。
- `docs/deployment/prod-ops-log.md`：2026-09-10 secret 写入记录；不等于本次已验证 secret 值。
- `docs/deployment/mas-production-go-live-checklist.md`：共享库恢复点、连接预算、PII 和完整上线验收。

本清单最初仅在本地静态核对。2026-09-17 已执行交接包的只读 `inventory.sql`；实际权限设计、依赖与恢复点仍须 DBA 审核，见后附盘点进度。

## 2026-09-16 实施准备进度（未执行生产操作）

后端 SUP 内网通知已提交 `c2c5d6b6`、`0268903a`（隔离 worktree，尚未发布）。Terraform 每 profile 的 SQL 绑定与专属 UAMI 准备提交为 `169de0e`，96 项测试通过。iCare 根仓验收回执：`docs/deployment/prod-public-db-acceptance-cyp-2600.md`；Terraform DBA 包在本地 `terraform/.worktrees/terraform-cyp2600-public-db-isolation/docs/deployment/sql/cyp-2600-public-logins/README.md`，尚未合并到原工作区。

DBA 可先运行包内 `inventory.sql` 做元数据盘点；它不读业务行、密码 hash 或模块正文。最终 `create-and-grant.sql` / `rollback.sql` 等 O1/O2 完成后再生成，当前没有可批准的一键建号授权脚本。所有账号与线上权限仍为待核验，未改 SQL/KV/RBAC、未 apply 或切流。

完整审查与未完成要求见 [本地实施审查](../reviews/2026-09-16-cyp-2600-public-db-isolation/report.md)。SUP 的接收侧 mTLS 和先 MAS 后 SUP 的发版顺序仍须实测，不能直接把新镜像放入尚未配置通道的 UAT/PROD。

2026-09-17 14:48 CST 已只读核验：PROD 尚无 Container Apps，五个专属 runtime UAMI 尚未在该 RG 创建；KV 禁用公网且私有端点已批准，但当前终端列 secret 元数据被网络边界拒绝。历史导入镜像来自 8 月构建，不是本次整改的最终版本。见 [现场核验与版本追溯](../operations/icare-prod.md)。当时 DBA 元数据回执待交付，未生成最终写脚本；原始盘点已在下述 15:17 条目更新。

## 2026-09-17 15:17 CST 元数据盘点进度

用户授权通过 Azure CLI 执行后，已在 `ihc-db-uat` 的 `master` 及五个批准 catalog 完成原始 `inventory.sql`，各保留 17 个完整结果集。通过 VM Run Command 使用既有 `WORKGROUP\ihc-db-uat$` 身份，本机 Shared Memory 连接，实测 sysadmin 和 `VIEW ANY DEFINITION` 均为 1；未授予权限。七个计划新建的业务/OAuth login 及 `mas_prod_owner` 在本次 server principal 快照中缺失。

完整归档在源 VM 的受限目录，初次盘点时因私网 SSH 超时仅有本地索引。**15:30 CST 用户接通 VPN 后，已通过 UAT runner 跳板下载并解压到本机**：`_backups/cyp2600-inventory/20260917T071312Z/results/`；同级 `README.md` 为交接入口，`inventory-complete.zip` 为原归档。归档及六个 JSON 的 SHA-256、ZIP CRC、102 个结果集和所有行数全部通过。原始结果被 Git 忽略，目录 `0700`、文件 `0600`。

详见[执行时间、归档位置、SHA-256 与核验边界](../operations/ihc-db-uat.md)。此进度更新的是原始元数据交付，不是 DBA 对模块/密钥依赖、有效权限和已有 user 归属的签收，也不是 TCP/ACA 连接验收；最终写脚本仍未生成，生产数据库权限与业务数据未改。

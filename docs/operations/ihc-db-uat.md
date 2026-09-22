# ihc-db-uat 运维时间线

## 2026-09-22 08:23 CST — CYP-2600 sysadmin 补 owner login 映射

- **操作人：** Grok；用户已 `az login`，要求按计划用 Azure 补 owner 映射。
- **原因：** 01:17 db_owner 补证拿到三库 owner SID 但看不到 server principal 名。
- **影响：** Azure Run Command + Shared Memory + `WORKGROUP\ihc-db-uat$` 只读查询 `sys.databases`/`sys.server_principals`。未建号、授权、改 schema/data。
- **结果：** 主库/WebKit owner=`sa`；`insularsalesportal_preprod`=`dcandaya`；`masprepaid_preprod`=`eapelegrino`；`authprovidermasuat`=`ihc-db-uat\ihcadmin`。TRUSTWORTHY/chaining 仍为 false。七个候选 login 仍缺失。
- **本地归档：** `/Users/konghai/Code/Project/Server/_backups/cyp2600-inventory/20260922T002329Z/`（gitignore）。

## 2026-09-22 01:17 CST — CYP-2600 补充只读盘点（db_owner TCP）

- **操作人：** Grok；用户接通 VPN，要求按计划继续补证。未向助手提供新密码，使用本机已有 `.env.preprod` 的 `mas_ref_owner`。
- **原因：** 跑 `inventory-followup.sql` 的 SELECT 批次，核对两张暂扣表、密钥保护、未过滤触发器与 owner SID。
- **影响：** 只查询五个业务 catalog 元数据。未建号、授权、改 schema/data、改 Azure 或网络。官方脚本要求 sysadmin，本次 `IS_SRVROLEMEMBER('sysadmin')=0`，THROW 未执行。
- **身份：** `ihc-db-uat` / `14.0.3550.4` / TCP `10.100.0.4:1433` / `mas_ref_owner` / 五库 `db_owner=1`。Azure 管理面 MFA 过期，未能走上次 sysadmin Run Command。
- **结论：** `tblprovidertemplate`、`tblretailquotationbenefitclass` 在五个 catalog 均不存在；前者旧约束挂在 `tblprovidergroups`。不建表、不 GRANT。密钥为 AES_256 口令保护。主库仅有复制 DDL 触发器。
- **本地归档：** `/Users/konghai/Code/Project/Server/_backups/cyp2600-inventory/20260921T171320Z/`（gitignore）。审核摘要在 Terraform 实施工作区 `docs/deployment/sql/cyp-2600-public-logins/followup-findings.md`。
- **未做：** 生产写入、建号、sysadmin 原样脚本、模块正文审阅、列收口签收。

## 2026-09-17 15:30 CST — CYP-2600 完整盘点归档下载本机并校验

- **操作人：** Codex；用户接通 VPN，并明确允许使用 UAT runner VM 作跳板。
- **原因：** 将 15:17 完成的六库元数据盘点结果交付到本地，供后续 DBA 权限审核使用。
- **影响：** 仅传输既有 `538622` bytes 归档，未重新连接或查询 SQL。新增一个私有 Blob container/归档副本和本地文件；未修改数据库、runner、Docker、网络或服务配置。
- **备份：** 源 VM 的原始 JSON、manifest 和归档全部保留。
- **回滚方式：** 下载不改源文件，无业务回滚需求；源归档及私有中转副本保留，本轮未删除文件或容器。本地文档可通过 Git 还原。
- **变更时序：** VPN 恢复后 SSH 连通 `icare-uat-runner-1` → 确认其解析 Blob 到 `10.30.5.9` → 源 VM 将既有归档上传私有 Blob → runner 经 HTTPS 读取并通过 SSH 流式回传 → 本机校验后保存并解压。runner 未落盘归档。
- **中转位置：** `icare2uaticare2st/cyp2600-inventory-20260917t071312z/inventory-complete.zip`；storage account 保持 `publicNetworkAccess=Disabled`，新 container 无匿名访问。HTTPS SAS 仅针对这个 blob：上传 create/write 至 15:48 CST、下载 read 至 15:50 CST，不含 list/delete；token 不写入 Git 或回执，本地上传脚本中的 token 已遮盖。
- **本地归档：** `/Users/konghai/Code/Project/Server/_backups/cyp2600-inventory/20260917T071312Z/inventory-complete.zip`。
- **本地结果目录：** 同目录 `results/`，包含 `inventory.sql`、`manifest-final.json` 和六份 `<catalog>.json`；同目录 `README.md` 为交接入口，`download-verification.json` 为本地验证回执。
- **验证：** 归档 SHA-256 为 `26dd61799a87390e67ea096fc1ee462089741efc96415ce25208f80162d39b3a`，与源 VM 一致；ZIP CRC、原始 SQL、六个结果 JSON 的 SHA-256、102 个结果集及所有行数全部通过。目录权限 `0700`、文件 `0600`，原始结果由 `_backups/` gitignore 规则排除。
- **交付状态：** 完整盘点结果已在本地，可直接交接下一 session；DBA 对依赖、有效权限及主体归属的审核仍待完成。

## 2026-09-17 15:17 CST — CYP-2600 完成六库只读元数据盘点

- **操作人：** Codex；用户明确要求通过 Azure CLI 执行交接包的只读盘点。Azure 操作身份为本机现有登录 `byang@icare.com.ph`，SQL 实际身份为既有 `WORKGROUP\ihc-db-uat$`。
- **原因：** 为公网 profile 独立账号的权限设计提供实例、对象、身份及权限快照。
- **影响：** 在 `master` 和批准的五个业务库顺序执行原始 `inventory.sql`，仅查询元数据，不读取业务行、密码 hash、密钥材料或模块正文。未建号、授权、修改 schema/data、重启服务或改网络；新增受限结果文件及 Azure Run Command 正常执行日志。
- **备份：** 无业务或配置变更，不需变更前备份；保存了原始 SQL、六库完整 JSON 结果、文件 SHA-256 和归档。
- **回滚方式：** SQL 查询无需回滚。结果文件保留，未执行删除；本地文档可通过 Git 还原。
- **变更时序：** 读取交接包 → Azure 网卡定位实例 → 集成身份预检 → 六库顺序查询 → 核验结果集数量、行数与文件 SHA-256 → 压缩归档并核验目录 ACL。

### 实例与身份核验

| 项目 | 实查结果 |
| --- | --- |
| Azure 订阅 | `e026db6e-ee32-47f1-b49c-da9e5f0441b8`，不是 iCare 2.0 UAT/PROD 所在的 `408f1434-...` |
| Resource group / VM | `ihc-uat-RG` / `ihc-db-uat` |
| 目标地址 | Azure 网卡与 Windows 本机 IPv4 均确认 `10.100.0.4` |
| SQL 实例 / 版本 | `ihc-db-uat` / `14.0.3550.4` |
| 执行入口 | `az vm run-command invoke --command-id RunPowerShellScript` |
| OS / SQL 身份 | `NT AUTHORITY\SYSTEM` / `WORKGROUP\ihc-db-uat$` |
| 元数据权限 | `IS_SRVROLEMEMBER('sysadmin')=1`，`VIEW ANY DEFINITION=1` |
| 实际 SQL 传输 | `lpc:localhost`，Shared Memory；各库均校验 `@@SERVERNAME` 和 sysadmin 身份 |
| TCP 尝试 | 最初连接 `tcp:10.100.0.4,1433` 的集成登录报 `ANONYMOUS LOGON`，随后使用同 VM 上既有的本机集成身份，未授予权限 |
| 原始 SQL SHA-256 | `77f33080ae26c9bf877791f59b9ee00ea4fbb0ddf18f1457aed14a101e8207ec` |

实际走本机 Shared Memory，结果中的 `local_net_address` / `local_tcp_port` 为 NULL。本次证明的是目标实例的元数据可见性，**不证明 TCP、应用密码登录或 ACA 路径通过**。Azure Run Command 退出码为 0 也可能包含脚本错误，本轮额外检查了脚本状态和落盘文件。

### 结果完整性

每库均有 **17 个结果集**；每个结果集保留列名、类型、行数及完整行值，空结果集也保留。远端重新读取全部 JSON，核对结果集数量、实际行数和文件 SHA-256，全部通过。

下表时间来自每库首个结果集，时区均为 CST（UTC+8）；对象等计数仅指原脚本筛选范围。

| catalog | 采集时间 | 对象 | 列 | 模块 | 表达式依赖 |
| --- | --- | ---: | ---: | ---: | ---: |
| `master` | 15:16:59 | 0 | 0 | 0 | 0 |
| `medicalassistance_preprod` | 15:16:59 | 8582 | 6797 | 1648 | 6197 |
| `maswebkit_preprod` | 15:17:04 | 1820 | 963 | 894 | 3365 |
| `insularsalesportal_preprod` | 15:17:06 | 542 | 374 | 149 | 443 |
| `masprepaid_preprod` | 15:17:07 | 62 | 36 | 24 | 43 |
| `authprovidermasuat` | 15:17:07 | 42 | 58 | 1 | 1 |

本次具有 sysadmin 元数据可见性，指定的九个候选/对照 login 中仅查到 `mas_ref_owner`。以下八个 **server login 在此次快照中缺失**：`ecom_runtime_prod`、`sup_runtime_prod`、`public_app_runtime_prod`、`public_hr_runtime_prod`、`public_map_runtime_prod`、`ecom_oauth_reader_prod`、`sup_oauth_reader_prod`、`mas_prod_owner`。这不自动证明库内没有同名 user，也不代表已完成已有主体归属签收。

脚本范围内的模块 `definition_sha256` 均非 NULL；这仍不能证明没有动态 SQL、签名或密钥依赖。建号前继续由 DBA 核对模块/触发器正文、密钥关系、有效权限与主体归属，并结合最终镜像源码审核授权。

### 受控文件位置

- **完整归档（服务器）：** `ihc-db-uat` 上 `C:\ProgramData\iCare\CYP2600\20260917T071312Z\inventory-complete.zip`。
- **大小 / SHA-256：** `538622` bytes / `26dd61799a87390e67ea096fc1ee462089741efc96415ce25208f80162d39b3a`。
- **目录 ACL：** 禁用继承，仅 SYSTEM 与本机 Administrators FullControl；SDDL 为 `O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)`。
- **归档内容：** 原始 `inventory.sql`、六份 `<catalog>.json`、`manifest-final.json`。首次压缩缺少显式加载 `System.IO.Compression`，六库查询已成功；补加载后只读取结果文件重新打包，未重跑 SQL。manifest 保留该归档错误及恢复说明。
- **本地回执：** `/Users/konghai/Code/Project/Server/_backups/cyp2600-inventory/20260917T071312Z/README.md` 与 `receipt.json`，目录 `0700`、文件 `0600`，由现有 `.gitignore` 排除。
- **15:17 时的下载状态：** 当时本地仅保存回执、原始 SQL 和执行记录，尚非完整六库结果。原私网跳板 `icare-uat-runner-1`（`10.30.6.4:22`）SSH 超时；现有 Bastion 为 Basic，未启用 native tunneling。当时未创建 Blob container/SAS，亦未开公网、修改防火墙或升级 Bastion。**15:30 已完成本地下载，见顶部记录。**

### 后续边界

原始盘点已完成，不能继续把“DBA 尚未运行 inventory.sql”作为阻塞原因。**DBA 依赖/有效权限审核、同名 user 归属、最终源码与镜像签收、精确建号/授权/回滚脚本、隔离 SQL Server 验证及写入批准仍待完成**；本次不生成或执行授权脚本。

关联：[DBA 执行清单](../runbooks/icare-prod-dba-login-cyp-2600.md)、[PROD 时间线](icare-prod.md)。

# CYP-2600：五个公网 profile 的数据库权限取证

日期：2026-09-16。状态：**代码静态核对完成，停在说明与审阅阶段；未建号、未授权、未改代码或部署配置。**

**2026-09-17 续审：** 上述状态及正文描述的是 9 月 16 日取证基线。后续 backend 已完成本地 SUP 整改（见文末），实际六库元数据现已交付；最新候选源码为 backend `0268903a`、public-backend `03abb25d`，最终镜像未选定。按用户要求已生成禁止执行的 DBA 审核草案，入口见 [DBA 清单](icare-prod-dba-login-cyp-2600.md)。98 行对象动作需求中 96 行匹配 dbo 对象，另两行 SUP 表仍待无过滤补证；不存在“所有对象和权限均已验证”的结论。

当前窄列建议为 OAuth SELECT(id,secret)、SUP tblusers SELECT(userno,username)、tblcorporatelibrary UPDATE(franchised)、App tblsendimagedetails SELECT(detno)（OUTPUT 返回列）。tblmemberpassword 模型不返回主键，tblfranchisingagents 是 map Create，暂不猜加 SELECT。其余表级候选、模块/动态 SQL/密钥链、public 继承及真实受限身份验收仍须 DBA 签收。

配套：[DBA 执行清单](icare-prod-dba-login-cyp-2600.md)。本文件列明现有代码需要哪些访问，不等于批准其中全部访问，也不等于已经通过真实 SQL Server 权限测试。

## 核验口径

- Backend：`88ab59e591eb784c2f2a68a2a20b55dbdbb7e9c4`；public-backend：`03abb25d0f57be86598ed7db444fe0401f61f4bf`。读取时两个工作区无未提交改动。
- 从 profile 装配、实际路由注册、handler/service 追到 repository，核对 GORM、原生 SQL、动态表名和 `TableName()`；排除测试代码、旧 SP 注释及未挂载功能。图索引部分符号已落后，相关证据以磁盘源码为准。
- catalog 对应 Terraform `2769f44753834b99db205ed3d854a49043d2709f` 的 PROD tfvars。`replicated` 在此配置中仍指 `medicalassistance_preprod`，不是第六个业务库。
- 未连接数据库、KV 或 runner，未读取业务行、密码。表的 schema、触发器、同义词、密钥授权与现有角色继承仍由 DBA 核对。
- 这是上述源码版本的访问清单；此前准备的 ACR 镜像 digest 未在本轮反查源码版本。交付账号前必须与实际拟部署镜像对齐，不把本地最新代码当成旧镜像内容。

下文 `S/I/U/D` 分别表示查询、新增、修改、删除。只列实际动作，不给全库 reader/writer 或 `db_owner`。`I` 中使用 `OUTPUT INSERTED` 返回字段的语句，还需 DBA 核对返回列的 SELECT 权限；不能把“没有单独 SELECT”理解成只授 INSERT 一定能运行。列级权限尚未逐列形成最终 GRANT 脚本。

## 1. 大白话结论

每个公网 profile 用自己的业务账号；ecom 和 sup 再各有一个 OAuth 只读账号，即本次范围建议 **5 个业务身份 + 2 个 OAuth 读取身份**。MAS 和 Operations 另计。一个 login 可以在多个 catalog 映射 user，但密码仍只有一个。

| profile | 实际直连范围 | 主要行为 |
| --- | --- | --- |
| ecom | 主库 + Prepaid；独立 OAuth 连接 | 主库查产品、会员及资格；Prepaid 买卡、登记、修改卡资料 |
| sup | 主库 + SalesPortal；独立 OAuth 连接 | SalesPortal 代理商与申请业务读写；主库查参考数据，并确有申请写入和企业标记更新 |
| app | 仅 WebKit | 注册、改密、通知已读、邮箱、报销、预约、健康记录、删号 |
| hr | 仅 WebKit | 企业账号登录/注册认领/改密、公司切换、权限读取、删除未同步会员修订 |
| map | 仅 WebKit | 会员注册、登录、改密和联系信息维护，附件分类读取 |

App/HR/MAP 的主库业务通过 MAS Internal API 完成，不能因此给它们主库 SQL 权限。账号属于服务，不属于每位会员；SQL 表权限不能代替代码中的会员/公司行级归属校验。App 和 MAP 会访问同一张会员表，独立账号不会自动把这张表按用户切开。

## 2. ecom：业务表权限范围较小

| catalog | 对象 | 动作 | 作用 |
| --- | --- | --- | --- |
| `medicalassistance_preprod` | `tbllocations` | S | 卡资料城市、省份名称 |
| 同上 | `tblcompanyclasses`、`tblproductlines` | S | SKU/计划、年龄、激活期限校验 |
| 同上 | `tblcompanybenefitplan`、`tblgentables`、`tblmembers` | S | 注册卡时核对已有会员、服务重叠 |
| `masprepaid_preprod` | `tblprepaidcards` | S/I/U | 买卡、登记、修改、查询；未发现对该表 DELETE |
| 同上 | `tblstatus` | S | 卡状态名称及注册判断 |
| `authprovidermasuat` | `oauth_clients` 的 `id`、`secret` | S | 独立 `ecom_oauth_reader_prod`；不读写 OAuth token 表 |

注册代码调用主库 `dbo.decodercontains`；局部临时表 `#claimservices` 不构成对业务库建表权限的需求。没有因初始化了 audit writer 就给 ecom `sys_audit_logs` INSERT：公网路由未挂 MAS 审计写入链。

实际挂载的 7 个 endpoint 是 token、checkout、register、三类卡查询和 update。cities/provinces/status 三个独立字典入口，以及两个 notification 入口在 manifest 中 `ready: false`，不因绑定存在就算成开放功能；上述字典表仍被已开放卡业务使用。

证据（路径相对 iCare/backend）：

- `internal/modules/ecom/runtime.go`、`module.go`、`contract/manifest.yaml`：实际 ready 路由。
- `internal/modules/ecom/card/repository.go`：`Checkout`、`UpdateCard`、`cardQuery`。
- `internal/modules/ecom/card/register_repository.go`：`Register`、`applicableServices`、`updateRegisteredCard`。
- `internal/platform/externalaccess/database_client_store.go`：OAuth 仅读 `id, secret`，探针 `WHERE 1 = 0`。

## 3. sup：权限最多，不能按“主库只读”交付

### SalesPortal：`insularsalesportal_preprod`

| 对象 | 动作 | 作用 |
| --- | --- | --- |
| `tblagentaccreditations`、`tblagentdetails` | S/I/U | 代理商/经纪人注册、资料、密码、登录活动 |
| `tblagentjournals` | S/I | 注册说明及日志展示 |
| `tblagentworkexperiences`、`tblagentsalesorientation` | S/I/U/D | 工作经历、销售培训明细维护 |
| `tblagentattachments` | S/I/U | 附件元数据；对象存储文件删除不等于 SQL DELETE |
| `tblstatus`、`tblgentables`、`tblfranchisingjournal` | S | 状态、字典、加盟日志 |
| `tblfranchising` | S/I/U | 企业加盟资料、状态 |
| `tblfranchisingagents` | I | 新加盟关联代理人；没有据此追加全表 SELECT |
| `tblfranchisingcontacts`、`tblfranchiserequirements` | S/I/U/D | 联系人及材料维护 |
| `tblfranchisinglogin`、`tblextensionrequests`、`tblcompanyaccreditations` | S/I/U | 健康计划选项、延期申请、公司认证 |
| `tblretailfranchising` | S/I/U | 零售申请暂存、状态和主库 applicationcode 回填 |
| `tblretailfranchisingfees` | S/I/U/D | 附加费用；修改时确有删除旧明细再写入的路径 |

### 主库：`medicalassistance_preprod`

以下分组均为代码引用的具体表，不代表允许 schema 级 SELECT。

| 对象 | 动作 | 作用 |
| --- | --- | --- |
| `tblagents`、`tblbenefitsa`、`tblfees`、`tblgentables`、`tbllocations`、`tblmembertypes`、`tblproductlines`、`tblprovidergroups`、`tblproviders`、`tblprovidertemplate`、`tblstatus`、`tblusers` | S | 代理人、地址、产品、参考字典及人员名称 |
| `tblcompanybenefitfees`、`tblcompanybenefitlimits`、`tblcompanybenefitplan`、`tblcompanybenefitservices`、`tblcompanyclasses`、`tblcompanyclassesbilling`、`tblcompanycontractyears`、`tblcompanymodalfactor`、`tblcompanypremiummember`、`tblcompanypremiums` | S | 计划、费率、账期和适用条件 |
| `tblmembers`、`tblsoaretailaccounts`、`tblretailquotationbenefitclass`、`tblsettingsfranchising` | S | 保单/账单、可选福利类别、加盟配置 |
| `tblapplications` | S/I/U/D | Portal For Approval V2 将申请从 SalesPortal 写入主库；失败补偿代码含 DELETE |
| `tblcorporatelibrary` | S/U | 企业查询；部分加盟状态操作写 `franchised` 列，UPDATE 可进一步限定此列 |
| `tblpushemailnotification` | S，涉及待整改邮件链 | 查询通知接收人，关联 `tblusers.emailadd`；与下述 SMTP 问题一起审阅 |
| `sys_app_settings` | **现代码会 S，暂不纳入直接授权建议** | 包含通信凭据，见下文冲突 |

`replicated` 连接指向同一个主库，权限应与其实际引用合并，不能以连接名字另造一份“副本库权限”。OAuth 另用 `sup_oauth_reader_prod`，仅读 `authprovidermasuat.oauth_clients(id, secret)`。

特殊调用：SalesPortal 的 `dbo.decoder` 用于账号口令编码；主库读写使用 `sp_opensymmetric` / `sp_closesymmetric`、`dbo.Decrypt`、`dbo.Encrypt`、`dbo.decodercontains` 及 `ENCRYPTBYKEY`。这些原语的有效调用与密钥权限须 DBA 结合现有定义检查，不能因用到加解密就授数据库管理员。

### 已核实的配置/规范冲突：SUP 能读邮件凭据

真实调用链为：`server.registerExternalRoutes` → `sup.NewRuntime(MailSettings)` → `NewGroupSMTPProvider(..., SysMailKeys())` → `appsettings.Service.GetMany` → `Repository.All`。

`Repository.All` 实际从 `sys_app_settings` 取回整表 `setting_key, value`，之后才在 Go 里筛选需要的键。给 SUP 此表 SELECT 会使该进程能读取表内其它配置及凭据；“业务只要几个邮件键”没有形成 SQL 访问限制。这与公网进程不持有 SMTP 口令的规范冲突。

建议把邮件交由内网服务发送后再定权限。本次只发现并记录，不改代码；如果只拒绝该表读取而保持现代码，邮件功能可能失败，不能称已完成无损切换。DBA 不应为让功能跑通直接给全表 SELECT。

证据（路径相对 iCare/backend）：

- `internal/modules/sup/runtime.go`、`module.go`：canonical 路由仅以 `runtime_disabled` 排除，**不是所有 `ready: false` 都未开放**。不能套用 ecom 的 ready 逻辑。
- `internal/modules/sup/retail/legacy_handler.go:445`：Portal `ForApprovalV2` 的真实调用；IORTA 同名生产 alias 已撤回，但 Portal canonical 路径仍在。
- `internal/modules/sup/retail/legacy_stage_repository.go:85`：主库事务写申请，`failLegacyStage` 失败补偿删除。
- `internal/modules/sup/corporate/mutation_repository.go:624`：`TagStatus` 更新主库 `tblcorporatelibrary.franchised`。
- `internal/modules/sup/{accreditation,user,corporate,retail,common,salesresource}/*repository.go`：SalesPortal 写入及主库查表。
- `internal/modules/appsettings/repository/repository.go:44`、`service/service.go:77`：全表读取后在应用中筛选。

## 4. app：仅 WebKit，但含真实删除与多类写入

以下对象均在 `maswebkit_preprod`。

| 对象 | 动作 | 作用 |
| --- | --- | --- |
| `tblsubscriptionmembers` | S/I/U/D | 注册、登录活动、改密、TFA/PIN、手机号/邮箱、设备 token、自助删号 |
| `tblmemberpassword` | I | 注册与改密追加密码历史；无全表查询/清理需求 |
| `tblsubscriptionmemberemail` | S/I/U | 备用邮箱、激活 |
| `tblnotificationoutbox` | S/U | 通知列表、角标、已读；生产不需要测试派发的 INSERT |
| `tblannouncement` | S | 公告 |
| `tblrequestloa` | S/U | LOA 列表及删号时取消排队请求 |
| `tblmemberproviderfavorites` | S/I/D | 医疗机构收藏与取消收藏 |
| `tblsendimages` | S/I/U | 报销建单、取消、附件计数、讨论状态 |
| `tblsendimagediscussions` | S/I | 报销讨论 |
| `tblsendimagedetails` | I/U | 报销附件元数据及生成后的文件名回填 |
| `tblsubscriptionhospitals`、`tblsubscriptionliaison` | S | 展示讨论参与者 |
| `tblusernotifications` | S/I/U | 报销通知，查询去重后新增/更新 |
| `tblcallrequest` | S/I/U | 回拨预约、改期、取消及删号联动 |
| `tblmemberbloodpressure`、`tblmembercholesterol`、`tblmemberglucose`、`tblmemberweight` | S/I/U | 健康指标；删除是更新 `isdeleted`，不应给 DELETE |
| `tblgentables`、`tblsettings`、`tblcorporatelinks` | S | 分类、提示文案、Sleep Better 资源 |

Wellness 使用 `sys.sp_getapplock` 做事务内并发互斥。默认 `public` principal 的调用不要求把账号提升到 `db_owner`，须在最终账号下验证现有权限，参见 [Microsoft 文档](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-getapplock-transact-sql?view=sql-server-ver17)。

证据（路径相对 iCare/public-backend）：`internal/server/routes_app.go`；`internal/modules/auth/{model,repository}`；`membersettings`、`memberdetails`、`memberemail`、`membersubscription`、`notifications`、`loa`、`reimbursement`、`callbackappointment` 的 repository；`wellness/wellnessdb/repository.go`；`sleep/repository/repository.go`；`internal/platform/websettings/disclaimers.go`。

`notifications` 的 `SaveOutbox` 仅被开发/SIT 的 test-dispatch 调用；`routes_app.go` 用 `IsLocal() || IsSIT()` 限定，生产权限不据此追加 INSERT。是否按正确 APP_ENV 部署需与最终镜像/配置一起验收。

## 5. hr：仅 WebKit，企业账号与会员修订

| `maswebkit_preprod` 对象 | 动作 | 作用 |
| --- | --- | --- |
| `tblsubscriptioncompany` | S/U | 注册是认领预置行后 UPDATE；登录/锁定/激活、改密、公司切换、联系信息 |
| `tblsubscriptionmultiplecompany` | S | 允许切换的公司集合 |
| `tblmoduleaccess`、`tbluseraccess` | S | 功能权限读取 |
| `tblwebcompanymembers` | S/D | 查看及删除本公司未同步的 amendment；未发现此直连路径 INSERT/UPDATE |
| `tblgentables` | S | 受养人保险类别投影 |

会员修订读路径使用 WebKit `sp_opensymmetric` 与 `dbo.Decrypt`。不能把这些权限授到 MAS 主库。HR 登录口令编码在本地 helper 中完成，不能仅因注释提到旧 `dbo.decoder` 就追加该 UDF 权限。

证据：`internal/server/routes_hr.go`；`internal/modules/auth/repository/company_*.go`（尤其 `RegisterCompanyAccount`）；`internal/modules/hrenrollment/repository/amendment.go`（`List`、`Remove`、`withSymmetricKey`）。

## 6. map：仅 WebKit，当前直连范围最小

| `maswebkit_preprod` 对象 | 动作 | 作用 |
| --- | --- | --- |
| `tblsubscriptionmembers` | S/I/U | 注册、登录/SSO、改密、TFA、邮箱/手机号、确认信息 |
| `tblmemberpassword` | I | 注册与改密追加密码历史 |
| `tblgentables` | S | MEMBER ATTACHMENT 分类 |

当前 MAP 路由已开放注册、OTP、SSO、重置密码；`routes_map.go` 内“尚未开放”的旧注释落后于 `auth/delivery/http/map/handler.go`。本清单按实际挂载算入 I/U。

没有挂 App 的删号、健康记录、备用邮箱和报销 repository，不把这些表权限复制给 MAP。依赖 MAS 的头像、福利、账单、受养人等功能不需要 MAP SQL 账号直连主库。

证据：`internal/server/routes_map.go`；`internal/modules/auth/delivery/http/map/handler.go:79`；`internal/modules/mapaccount/module.go`；`memberdetails/repository/repository.go`；`mapattachments/repository/repository.go`。

## 7. 哪些事情查清了，哪些仍留待下一步

已完成代码侧对象和动作核对，可以据此解释每个服务需要什么；五个 profile 不能共用同一份授权，也不能把所有业务账号都设成只读。没有生成或执行 GRANT。

后续实施前的待审事项：

1. **SUP 邮件链冲突**：是否安排改为内网发送；未整改前不能声称该服务达到当前公网凭据规范。
2. **对齐发布版本**：以真正拟部署镜像对应源码复核差异，再由 DBA 确认目标库对象、触发器、SID 与 UDF/密钥有效权限。本轮没有证明这些生产对象都存在。
3. **收口最终授权**：按本表细化 UPDATE/SELECT 列、`OUTPUT` 返回列及被调用 UDF 的权限，检查 `public`、角色、guest 和所有权带来的额外权限。表级账号也不会自动实现会员或公司行隔离。
4. **修改配置并验收**：以后获准实施时，Terraform 须拆分业务 username/secret 引用，保留两个独立 OAuth reader；每个 login 的多 catalog 连接密码一致，再从 PROD 路径验证。只在 SQL 建账号不会改变服务当前仍引用 `mas_prod_owner` 的事实。

本次到此停止。数据库状态与部署状态没有变化；本报告不是建号或部署批准。

## 实施分支差异（2026-09-16，尚未部署）

后端首批提交 `c2c5d6b6` 将 SUP SMTP 模板、配置读取和通知名单读取移入 MAS 内网 notifications 模块。此前报告描述的是基线版本，不应据此给新 SUP 继续授 `sys_app_settings` 或 `tblpushemailnotification`。

新 SUP 不再因邮件链需要 `tblusers.emailadd`；`tblusers` 仍有 journal、corporate、retail 的 `userno/username` 查询，不能整表撤权。最终列清单待 DBA 对照实际部署镜像签收。邮箱解析现在是 MAS 内网权限，由专属 `sup` caller 的窄接口触发；未证明生产 mTLS 接收端已强制验证，SUP 发布仍须通过通道门禁。

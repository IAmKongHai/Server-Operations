# CYP-2600 本地实施审查

日期：2026-09-16。范围：backend `89825778` 至本次实施工作区；Terraform `2769f447` 至本次实施工作区；配套 DBA 与验收文档。目标为执行 `docs/plans/2026-09-16-1440-fix-cyp-2600-public-db-isolation-plan.md`。

审查后本地提交：backend `c2c5d6b6`、`0268903a`；Terraform `169de0e`。两个实施分支均未推送。

按 ce-code-review 检查正确性、项目约定、测试、可维护性、安全、接口兼容、故障处理及跨组件失败场景。按项目指令全部在主线程顺序完成，没有独立审查者、跨模型审查或外部代码传输；下述结论不是独立二审证明。ce-simplify-code 的复用、质量、效率检查未发现需要新增抽象的理由；继续复用既有 SMTP provider、通知模块及身份模块。

## 已修正并复核

- Terraform 的 HR/MAP WebKit 用户映射补齐为各自账号，避免只改 App 而其余 profile 仍继承 MAS 用户名。
- 禁用 ecom/sup 时不再创建对应容器/身份、要求其 SQL 凭据或输出虚假 FQDN；保留非 PROD 的既有数据库映射。
- 比较 Key Vault secret 对象时忽略版本后缀；禁止把 SQL 密码藏在 Redis 等其它 secret 键下；SUP token/证书也不能借其它 secret 对象交付。
- 新增 SUP token 别名回归测试先失败，补上门禁后通过。内网 serviceauth 会拒绝重复 token，提前拦截可避免整组内网 caller 注册失败。不同 secret 对象里是否存了同一个值仍须交付方核验，Terraform 不读取值。
- DBA 盘点补充 schema/database 所有权；无权限验证不再猜 `dbo`。空结果、NULL 或 hash 不能证明无依赖，DBA 须另核动态 SQL、签名及密钥关系。
- 邮件日志用 `completed` 表达流程完成，不将“无管理员收件人而跳过发送”记为 `delivered=true`。

## P1：实施仍受阻

1. **实际对象、身份归属和版本未签收，无法生成最终建号授权及回滚 SQL。** 位置：计划 U1/U3；Terraform `docs/deployment/sql/cyp-2600-public-logins/README.md:14`。现有包只有只读盘点和权限核对材料，不是已完成 U3。需要 O1 镜像/SHA 与 O2 DBA 元数据、主体及依赖回执；按真实对象生成差异后，在获准 SQL Server 环境验证。归属 `release`，人工交付。
2. **尚未证明工作负载身份不能取得其它 SQL 密码，也未证明最小 SQL 权限能运行业务。** 位置：Terraform `workloads/public_db_isolation.tf:52` 及计划 U5/U6。回执引用仅是发布门禁，mock 测试没有访问真实 Azure/SQL。须检查 UAMI 和系统身份的直接/继承 RBAC，运行真实 SQL 正反向测试与工作负载取用探针。归属 `release`，人工交付。
3. **SUP 接收侧强制 mTLS 与各环境发版顺序未验收。** 位置：backend `internal/platform/serviceauth/registry.go:263`、`internal/config/sup_notifications.go:13`；Terraform `workloads/modules/container_apps/variables.tf:537`。现有 serviceauth 校验 token，不验证客户端证书；客户端发送证书不足以证明入口认证成立。新 SUP 镜像在未配通道的非生产环境可能启动并在注册成功后无法发信。因此必须先部署 MAS 接收端，交付并验证入口证书/caller 绑定，再配置对应环境和更新 SUP 镜像；不应直接合并触发旧 UAT 配置下的自动更新。归属 `release`，应用与网络负责人交付。
4. **生产窗口、实际 revision/流量、合规回退版本和批准未交付。** 位置：计划 U7/U8。不执行建号、KV/RBAC、apply、切流或清理旧引用；此前选定“由 DBA 执行”不代表这些动作已经获批。归属 `release`，按 O4 补齐。

这些是显式计划尚未完成的要求及部署前提，不是允许发布后再补的遗留事项。

## Requirements Completeness

| 要求 / 实施单元 | 状态 | 证据与缺口 |
| --- | --- | --- |
| R1、R3 / U4 | 本地配置完成 | 五个业务身份和两个 OAuth 身份明确；PROD username、secret、catalog 映射及禁用场景通过 mock 测试，实际账号尚未创建/核验 |
| R2 / U1、U3 | 部分完成 | 已有源码取证和只读盘点包；真实 schema/列/依赖、授权差异及反向 SQL 待 DBA 回执 |
| R4 / U2 | 本地应用改造完成，通道未验收 | SUP 不装配 SMTP；独立 caller/scope、固定用途、内网查收件人已实现；真实 mTLS/SMTP 与部署顺序待验收 |
| R5 / U5 | 静态配置完成，现场未验收 | 专属 UAMI、secret/ACR 建议授权范围和发布回执门禁；真实继承权限及拒绝探针未测 |
| R6 / U2、U6 | 部分完成 | 聚焦测试覆盖落库后发送失败、名单查询失败、跨 caller/scope 拒绝等；真实 SQL/业务数据及 SMTP 未测 |
| R7 / U6 | 未完成 | 仅落盘验收矩阵，没有获准隔离 SQL Server 环境和最终工作负载路径证据 |
| R8、R9 / U3、U7、U8 | 本次遵守执行边界，线上工作未执行 | 未改库、KV、RBAC 或部署，未变更旧 principal/SID；未来写入仍由各责任人按批准差异执行 |
| R10 / 全部 | 部分完成 | 源码基线、测试和缺口已记录；digest、运行配置、权限差异及执行回执待交付 |

## Actionable Findings

| # | 下一步 | 前提及责任 |
| --- | --- | --- |
| 1 | DBA 运行 inventory.sql，应用负责人交付 digest/SHA；随后生成精确授权/回滚差异 | DBA 与应用负责人；只读盘点可先做，写入另行批准 |
| 2 | 提供隔离 SQL Server 和获准数据范围；验证各运行身份 SQL/KV 正反向权限 | DBA、KV 管理员、应用负责人；不可用全库角色临时绕过失败 |
| 3 | 落实并实测 MAS 入口 mTLS/caller 绑定，先接收端后客户端；UAT 同样须先配通道 | 网络与应用负责人；不退回公网 SMTP |
| 4 | 签收分批窗口、回退和批准，按 MAP、HR、App、ecom、sup 执行与观察 | 发布负责人；SUP 阻塞不阻止其它 profile 独立验收 |

## Coverage

- 后端聚焦测试：`go test ./test/sup ./internal/modules/notifications/... ./internal/platform/serviceauth ./internal/config ./internal/server -count=1` 通过；日志字段修正后重跑 notifications 全部 package 通过。
- 后端增量 `golangci-lint --new-from-rev=89825778` 对受影响包检查，0 issues；`go test ./... -run '^$'` 全仓编译通过。后者没有执行全仓测试，不能记成全测试通过。
- Terraform：`fmt -check -recursive`、`workloads validate` 通过；完整 workloads mock-provider suite 为 **96 passed, 0 failed**。旧有 federated identity `resource_group_name` 弃用警告仍在，与本次无关。
- 回归测试覆盖身份/secret 别名、缺回执、禁用 profile、SUP 失败语义与窄接口；审查逐项核对修改后的调用和配置绑定，没有独立 validator 或跨模型佐证。
- SQL 文件仅静态检查，未在 SQL Server 执行。SQLite 集成测试不证明 SQL Server 权限、加密原语、触发器和跨库行为。SMTP 真发信、证书握手与 Azure Secret volume 文件路径仍待环境验收。
- 差异检查未发现本次引入的 secret 明文；没有真实 plan/apply，没有线上操作可记为成功。

---

## Verdict

**Not ready：本地准备可交接，完整计划未完成，不具备生产发布条件。** 审查没有剩余的已确认本地机械修复项；#1 至 #4 必须按责任分工取得证据。当前只保存本地提交，不推送、开 PR、合并或发布；不得把本报告当成已通过生产验收。

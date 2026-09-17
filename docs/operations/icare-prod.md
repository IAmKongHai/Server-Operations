# iCare Azure PROD 运维时间线

## 2026-09-17 14:48 CST — CYP-2600 首次部署前只读核验

- **操作人：** Codex，使用本机现有 Azure/GitHub 登录上下文。
- **原因：** 继续公网数据库账号隔离计划，补齐 O1/O3/O4 的现场证据。
- **影响：** 仅读 Azure 管理面、尝试读取 KV secret 元数据，并核对 GitHub 构建元数据及本地版本历史。未连接 SQL，未读取 secret 值，未修改资源、角色、网络、部署或流量。
- **备份：** 无配置变更，无需备份；核验结果及复查命令记录于本条。
- **回滚方式：** 只读查询无需回滚；本地文档可通过 Git 还原。
- **变更时序：** 核对订阅 -> 列出 PROD 应用/身份 -> 检查 KV 网络与授权 -> 核对 UAT 内网入口 -> 追溯历史镜像构建。全程无生产变更。

### 核验结果

| 项目 | 观察结果 | 能证明什么 / 尚缺什么 |
| --- | --- | --- |
| 订阅 | `408f1434-56ae-45b6-9762-7c9e1e615000` | 与 CYP-2600 配置一致 |
| PROD Container Apps | `iCare-2.0-PROD` 查询结果 `[]` | 五个公网 profile 均未在该 RG 部署；当前没有它们的 PROD revision/流量可切换 |
| PROD UAMI | 该 RG 仅列出 `icare-2-prod-gh-mobile-app` | 本计划五个 `icare2-prod-<profile>-runtime` 及共享 workload runtime 均尚未在该 RG 创建；不能冒称完成运行身份取用验收 |
| KV 授权模型 | `enableRbacAuthorization=true` | 使用 Azure RBAC；不是 access policy 模式 |
| KV 网络 | `publicNetworkAccess=Disabled`；`icare-2-prod-pe-key-vault` connection=`Approved` | 管理面存在批准的私有端点；不等于当前终端数据面可达 |
| KV 元数据查询 | 本机 `secret list` 返回 `ForbiddenByConnection` | 当前路径未通过网络边界；未读取 secret 值，不能确认五个新业务 secret 是否交付。没有为了取证修改防火墙或绕过网络限制 |
| KV RBAC | vault scope 加继承查询含订阅/RG 角色；vault 上现有运维用户和 Terraform 身份有 `Key Vault Secrets Officer` | 这些是交付身份，不能挂给公网容器充当 runtime。未完成目录组成员关系、未来 runtime 主体或数据面正反向验收 |
| UAT MAS 入口 | `icare2-uat-cae` 为 `internal=true`；MAS app ingress 为 `external=true`，`clientCertificateMode=null` | 此 external 表示跨 CAE 可访问的入口，须结合 internal CAE 判断，不能直接判为公网 MAS。未配置 ACA 客户端证书模式 |
| UAT 公网 CAE | `icare2-uat-cae-external` 为 `internal=false` | 与 MAS 私网环境不同；本轮未改任何入口 |

### 历史镜像来源

9 月 10 日 PROD 导入记录在 iCare 根仓 `docs/deployment/prod-ops-log.md`。本轮通过 Terraform Git 历史与 GitHub run 元数据建立以下历史对应关系，未重新读取 ACR manifest，**不是最终拟发布镜像签收**：

| profile | 导入记录中的 digest | 历史构建与源码 |
| --- | --- | --- |
| ecom | `sha256:efa318b95247510391db9e84ba5a588bd4f2703ad495bbcb7a2cd21ec93c744a` | [backend run 31413989540](https://github.com/cypressoai/iCare-backend/actions/runs/31413989540)，tag `v2026-08-11.01`，SHA `41578c7a90b91f10c3961dc6714aa3bcc4649be3`，success |
| sup | `sha256:bdafbdad3502773d5d120a4be1a3985daaa669c1fc47068ed907946f8c279b6a` | 同上；早于本次 SUP 邮件改造，不能作为整改后的候选镜像 |
| app/hr/map | `sha256:390a5128aff32ca327c6e2fb5076d650fb8c40595ff4dc719a50780c4e393c02` | [public-backend run 31143948145](https://github.com/cypressoai/iCare-public-backend/actions/runs/31143948145)，tag `v2026-08-06.01`，SHA `0d0a5d667a0698887d40a631a031abec9d67f8ed`，success |

Terraform 证据提交为 `938ac55`（ecom/sup）、`d202445`（public-backend）。两个历史源码版本的 workflow 均 checkout 触发 tag，未指定另一个源码 ref。MAS 的 `34a2685...` 目前只追溯到 Terraform `cfcab1f` 的现网 digest 回填，未由本轮确定其构建 SHA，不补写猜测。

### SUP 传输要求的边界

Terraform 旧计划 `docs/plans/2026-08-06-001-feat-uat-public-portals-deploy-plan.md` 的 R14b/KTD11 明确：UAT 内网调用采用 VNet 隔离 + 独立 service token，mTLS 另行处理。本轮管理面结果与“未设置客户端证书模式”一致。

这不能作为 PROD SUP mTLS 已通过的证据，也不能自动外推为 PROD 豁免。现有 backend 公网边界规则要求服务身份保护，本次 SUP 交付包仍保留真实接收端验证要求；若要改用其它认证边界，需先明确适用环境与决定依据，不能只给客户端配证书便签收。旧计划关于 Secret volume 不支持的历史描述不用于判断当前 AzureRM 4.80.0 能力。

### 可重复的只读检查

```bash
az containerapp list --subscription 408f1434-56ae-45b6-9762-7c9e1e615000 --resource-group iCare-2.0-PROD --query '[].name' -o json
az identity list --subscription 408f1434-56ae-45b6-9762-7c9e1e615000 --resource-group iCare-2.0-PROD --query '[].{name:name,principalId:principalId}' -o json
az keyvault show --subscription 408f1434-56ae-45b6-9762-7c9e1e615000 --name icare2-prod-icare2-kv --query '{rbac:properties.enableRbacAuthorization,publicNetworkAccess:properties.publicNetworkAccess}' -o json
az role assignment list --subscription 408f1434-56ae-45b6-9762-7c9e1e615000 --scope /subscriptions/408f1434-56ae-45b6-9762-7c9e1e615000/resourceGroups/iCare-2.0-PROD/providers/Microsoft.KeyVault/vaults/icare2-prod-icare2-kv --include-inherited --query '[].{principalId:principalId,role:roleDefinitionName,scope:scope}' -o json
gh run view 31413989540 --repo cypressoai/iCare-backend --json headSha,headBranch,conclusion,url
gh run view 31143948145 --repo cypressoai/iCare-public-backend --json headSha,headBranch,conclusion,url
```

### 下一步

1. DBA 先执行只读 `inventory.sql` 并回传受控位置；本轮未收到结果，O2 保持待交付。
2. 应用负责人选定包含整改的最终源码，构建并交付 digest/SHA；历史导入记录不能直接闭合 O1。
3. 获批后按“创建专属身份 -> 外部最小 RBAC 交付 -> 独立凭据与受限 SQL 验收 -> 首次部署”的顺序推进。现在没有旧 PROD revision，初次部署失败的停止/撤流方式须明确，不能假定有可回退旧版本。
4. O3 数据面探针由获准私网执行位置完成；本轮未请求或使用 DBA 密码。

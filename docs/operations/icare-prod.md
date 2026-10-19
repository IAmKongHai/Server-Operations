# iCare Azure PROD 运维时间线

## 2026-10-19 08:40 CST — 放开 m@cypresso.ai 在跳板机上的 shell 登录

- **操作人：** Claude，用户明确要求。
- **原因：** 用户要求解除这把 key 的“不能登录 shell”限制。
- **影响：** 该 key 的选项从 `restrict,port-forwarding,permitopen="10.0.0.5:1433",command="/bin/false"` 改为 `restrict,pty,port-forwarding,permitopen="10.0.0.5:1433"`：可以以 `icareadmin` 登录交互 shell（`icareadmin` 有免密 sudo，等于拿到这台 PROD runner 的 root）。端口转发仍只允许到 `10.0.0.5:1433`；agent/X11 转发仍关闭。未改 sshd 配置，未重启服务。
- **备份：** `~/.ssh/authorized_keys.bak-20261019-shell`（改前的 3 行版本）。
- **回滚方式：** `cp -p ~/.ssh/authorized_keys.bak-20261019-shell ~/.ssh/authorized_keys`。
- **验证：** `diff` 只有第 3 行变化；`ssh-keygen -lf` 三把 key 都能解析；新开 SSH 会话登录正常；`sshd -T` 显示 `permittty yes`、`allowtcpforwarding yes`、`forcecommand none`。

### 08:15 那次是谁加的

- 不是 SSH 登录写入的（`last` 和 sshd 日志在这个时段都没有记录），而是 Azure Run Command（`RunCommandLinux` seq 85，脚本在 `/var/lib/waagent/run-command/download/85/script.sh`）。
- Azure Activity Log：`Microsoft.Compute/virtualMachines/runCommand/action`，caller `byang@icare.com.ph`，appid `04b07795-8ddb-461a-bbee-02f9e1bf7b46`（Azure CLI），来源 IP `89.208.242.203`（`tizi-cyp` 出口）。00:14:51 UTC 先跑了一次只读检查（seq 84），00:15:34 UTC 加 key。
- 本机 `az account show` 的登录账号就是 `byang@icare.com.ph`，所以是从这台 Mac 用本机 az 登录态执行的，很可能是之前某个 agent 会话做的，当时没有写运维记录。

## 2026-10-19 08:15 CST — 跳板机 icare-2-prod-ci-runner 加入同事 m@cypresso.ai 的隧道公钥

- **操作人：** 同事公钥写入于 08:15 CST；08:37 CST 由 Claude 只读核对确认。
- **原因：** 同事需经跳板机 `icareadmin@10.40.9.4`（`icare-2-prod-ci-runner`）建 SSH 隧道访问 `10.0.0.5:1433`。
- **影响：** `~icareadmin/.ssh/authorized_keys` 新增 1 行（共 3 行）。该 key 带 `restrict,port-forwarding,permitopen="10.0.0.5:1433",command="/bin/false"`：只能转发到 `10.0.0.5:1433`，不能开 shell、不能转发到其它地址。未改 sshd 配置，未重启服务。
- **备份：** `~/.ssh/authorized_keys.bak-20261019`（加 key 前的 2 行版本）。
- **回滚方式：** `cp ~/.ssh/authorized_keys.bak-20261019 ~/.ssh/authorized_keys`，或删掉 `m@cypresso.ai` 那一行。
- **验证：** `grep -c` 确认该 key 只出现 1 次；与备份 `diff` 只多这一行；文件权限 `600`，`.ssh` 目录 `700`。

同事使用方式（本地端口可自定）：

```bash
ssh -N -L 11433:10.0.0.5:1433 icareadmin@10.40.9.4
# 之后连 127.0.0.1:11433
```

## 2026-09-17 15:17 CST — CYP-2600 完成源 SQL 实例只读盘点

- **操作人：** Codex，用户明确要求通过 Azure CLI 执行。
- **原因：** 执行 Terraform 交接包的 `inventory.sql`，补齐原始元数据。
- **影响：** `ihc-db-uat` 的 `master` 及五个业务库各完成 17 个元数据结果集；未建号、授权、改 schema/data 或调整 PROD 部署。
- **备份：** 保存原始 SQL、完整 JSON 和 SHA-256；没有业务或配置变更。
- **回滚方式：** 只读查询无需回滚；结果文件保留。
- **变更时序 / 验证：** 使用目标 VM 现有本机集成 sysadmin 身份查询，逐文件核对结果集数量、行数与哈希，受限目录归档完整。服务器路径、采集时间、身份及下载限制见 [ihc-db-uat 执行回执](ihc-db-uat.md)。原始盘点已完成，DBA 依赖/有效权限审核及写入批准仍待完成。

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

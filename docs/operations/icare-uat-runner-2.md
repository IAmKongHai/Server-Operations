# icare-uat-runner-2 运维时间线

机器档案：[`icare-uat-runner-2/README.md`](../../icare-uat-runner-2/README.md)

SSH：`ssh icare-uat-runner-2`（`icareadmin@10.30.6.5`）。主机名 `icare-2-uat-ci-runner-2`，CYP-2263 临时 D8s_v5 burst runner，GitHub runner 名 `icare-2-uat-runner-2`，组 `icare-2-uat`。

## 2026-08-25 15:20 CST - Deploy Azure UAT Portals 的 hr job 因 SWA CLI 拉不到 StaticSitesClient 失败，重跑通过

- 服务器：`icare-uat-runner-2`（GitHub runner `icare-2-uat-runner-2`，组 `icare-2-uat`）
- 操作人：`Claude`
- 原因：排查 `iCare-public-frontend` workflow `Deploy Azure UAT Portals` run [32820490312](https://github.com/cypressoai/iCare-public-frontend/actions/runs/32820490312) 中 `Deploy hr portal` 失败。
- 影响：**只读排查 + 一次 workflow 重跑**。未登录该 VM，未改 runner、Docker、网络、`/var/cache/buildx`。
- 备份：无（无配置变更）。
- 回滚方式：无变更可回滚。
- 现象：
  - 失败在 `Deploy to Static Web App` 这一步，job 仅跑 22s，进入 SWA CLI 后约 4.5s 即失败——是立即失败，不是超时。
  - 报错：`Deployment Failure Reason: Could not load StaticSitesClient metadata from remote. Please check your internet connection.`
  - OIDC 登录、`az staticwebapp secrets list` 取部署 token 均已通过（否则会先打 `FAIL could not read the deployment token`），故与 Azure 权限/自定义角色无关。
- 定位：
  - `@azure/static-web-apps-cli@2` 部署时不自己上传，先从公网 CDN（`*.azureedge.net`）拉版本元数据、再下载 `StaticSitesClient` 二进制到 `~/.swa/deploy/`，由它完成上传。这一段与 `az` 登录无关，是独立的出网依赖。
  - 同 run 的 `Deploy member portal` 同时成功，但它跑在 **`icare-2-uat-runner-1`**，不是同一台机器；两个 portal job 分别落在 runner-2 / runner-1，因此**不是**两 job 争抢同一个 `~/.swa` 缓存目录导致的。
  - 回看最近 12 次 `Deploy Azure UAT Portals`，hr job 长期稳定跑在 runner-2 且全部成功，无该机固有失败模式。
- 处置：用户执行 failed job 重跑，`Deploy hr portal` 在 runner-2 上通过（07:35 那次尝试）。
- 验证：run 32820490312 重跑后 hr / member 两个 portal job 均 success。
- 结论：判定为一次性的 CDN / 出网抖动，未做任何配置变更。
- 后续（暂未实施，复发再做）：
  - 给 `Deploy to Static Web App` 加重试，并在重试前 `rm -rf ~/.swa/deploy` 清掉可能损坏的半份二进制；
  - 若 UAT 网络有出站白名单，确认 `swalocaldeploy.azureedge.net` 在名单内。

## 2026-08-23 18:26 CST - 建立机器档案

- 服务器：`icare-uat-runner-2`
- 操作人：`Grok`
- 原因：与 `icare-uat-runner-1` 一并固化连接信息、SKU、runner slot、Buildx 约定。
- 影响：只新增 `icare-uat-runner-2/README.md`；SSH 别名原本已指向 `10.30.6.5`，未改。
- 备份：无（文档）。
- 回滚：删该 README。
- 验证：档案中的 hostname / `Standard_D8s_v5` / 无 wait slot / 无 `gh` / `/var/cache/buildx` 已存在，与只读 SSH 盘点一致。当时有 `Runner.Worker`，未动进程。

## 2026-08-23 18:18 CST - 预建 `/var/cache/buildx`，对齐原 UAT runner

- 服务器：`icare-uat-runner-2`（Azure Linux 3.0，主机名 `icare-2-uat-ci-runner-2`）
- 操作人：`Grok`
- 原因：tag `v2026-08-23.03` 的 `iCare-backend` `Build Azure UAT Images` 第一次落到这台新机，在 `Prepare backend build cache` 秒失败：`mkdir: cannot create directory '/var/cache/buildx': Permission denied`。前端 `Wait for backend UAT` 按设计 fail-fast，不是 frontend runner / 代码问题。
- 影响：只新增空目录，**未**重启 runner / Docker，**未**重跑 UAT 发版 workflow。
- 备份：改前状态留在对话与本条：
  - `/var/cache` 为 `root:root` `drwxr-xr-x`，无 `buildx` 子目录
  - 原机 `icare-uat-runner-1` 上已有 `drwxr-xr-x icareadmin:icareadmin /var/cache/buildx`（含 `icare-backend-uat` / `ecom` / `sup` 三份 cache）
- 回滚方式：
  ```bash
  ssh icare-uat-runner-2 'sudo rm -rf /var/cache/buildx'
  ```
  回滚后该机再接 UAT 镜像构建会再次 Permission denied。
- 变更时序：
  1. 只读确认 runner 用户 `icareadmin`（sudo + docker），`/opt/actions-runner` 属主同用户，service `actions.runner.cypressoai.icare-2-uat-runner-2` active。
  2. `sudo mkdir -p /var/cache/buildx && sudo chown icareadmin:icareadmin /var/cache/buildx && sudo chmod 755 /var/cache/buildx`（权限对齐原机，不用 775）。
- 验证：
  - `ls -ld /var/cache/buildx` → `drwxr-xr-x 2 icareadmin icareadmin`
  - 以 `icareadmin` 执行 workflow 同款 `mkdir -p /var/cache/buildx` 成功；`df -h /` 约 **88G Avail / 7%**
  - runner service 仍 `active`，未 restart
- 后续：需人工重跑 backend `Build Azure UAT Images`（tag `v2026-08-23.03`），成功后再重跑 frontend `Deploy MAS Azure UAT`。新 UAT burst 机上线 checklist 必须含此目录。
- 方案沉淀：`docs/solutions/icare-uat-runner-2/workflow-issues/buildx-cache-dir-missing-on-new-uat-runner-2026-08-23.md`

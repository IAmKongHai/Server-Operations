# icare-uat-runner-2 运维时间线

机器档案：[`icare-uat-runner-2/README.md`](../../icare-uat-runner-2/README.md)

SSH：`ssh icare-uat-runner-2`（`icareadmin@10.30.6.5`）。主机名 `icare-2-uat-ci-runner-2`，CYP-2263 临时 D8s_v5 burst runner，GitHub runner 名 `icare-2-uat-runner-2`，组 `icare-2-uat`。

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

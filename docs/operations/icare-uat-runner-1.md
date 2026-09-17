# icare-uat-runner-1 运维时间线

机器档案：[`icare-uat-runner-1/README.md`](../../icare-uat-runner-1/README.md)

SSH：`ssh icare-uat-runner-1`（兼容 `ssh icare-uat-runner`）→ `icareadmin@10.30.6.4`。主机名 `icare-2-uat-ci-runner`。

## 2026-09-17 15:30 CST — 作为 CYP-2600 盘点归档下载跳板

- **操作人：** Codex，用户明确允许使用 UAT runner VM 作跳板。
- **原因：** 用户接通 VPN 后，将 `ihc-db-uat` 上既有的六库元数据归档下载本机。
- **影响：** 使用现有 SSH 与 Python，经私有 Blob 端点 `10.30.5.9:443` 读取 `538622` bytes 归档并流式回传；未落盘归档，未改 runner / Docker / `/var/cache/buildx` 或服务配置。
- **备份：** 未改配置，无需备份；源 VM 原件保留。
- **回滚方式：** 转发进程已结束，无服务变更需要回滚。
- **变更时序：** 确认 SSH、DNS 与 HTTPS 连通 → 通过 stdin 传入只读短期 SAS → 内存读取归档 → SSH 回传至本机。SAS 不放命令参数或 Git。
- **验证：** 本机归档 SHA-256 与源 VM 一致，完整解压及六库元数据校验通过。结果位置与中转记录见 [ihc-db-uat 时间线](ihc-db-uat.md)。

## 2026-08-24 20:32 CST - 只读确认到 ihc-db-uat 的跳板能力

- 服务器：`icare-uat-runner-1`（`10.30.6.4`）
- 操作人：`Grok`
- 原因：评估把 `10.100.0.4` 上 17 GB `.bak` 运到 `mssql-ref` 的中转点。
- 影响：**只读**。ping / TCP 探测 / `df`。未改 runner、Docker、`/var/cache/buildx`。
- 备份：无。
- 回滚：无变更。
- 验证：
  - `10.100.0.4` ping ~1.5ms；1433 / 445 / 3389 开，22 拒绝。
  - 本机无 Tailscale，`100.124.140.78` ICMP/22 不通，不能直送 mssql-ref。
  - 根分区剩约 59G，够暂存 17G bak。
  - 已装 `/opt/mssql-tools18/bin/sqlcmd`。
- 相关：`docs/plans/2026-08-24-001-ops-mssql-ref-sync-from-ihc-db-uat-plan.md`

## 2026-08-23 18:26 CST - 纳入 SSH 别名 `icare-uat-runner-1` 并建立档案

- 服务器：`icare-uat-runner-1`（Azure Linux 3.0，`Standard_B2s`，`10.30.6.4`）
- 操作人：`Grok`（用户指定别名）
- 原因：原别名只有 `icare-uat-runner`，与 burst 机 `icare-uat-runner-2` 不对称；用户要求 `icareadmin@10.30.6.4` 使用 `icare-uat-runner-1`。
- 影响：
  - 本机 `~/.ssh/config`：`Host icare-uat-runner icare-uat-runner-1` 指向同一地址，旧别名仍可用
  - 新增机器档案 `icare-uat-runner-1/README.md` 与本时间线
  - **未**改 VM、runner、Docker
- 备份：SSH 块原先已是 `Host icare-uat-runner` / `HostName 10.30.6.4`，本次只在 Host 行追加 `icare-uat-runner-1`
- 回滚方式：从 Host 行去掉 `icare-uat-runner-1`，保留 `icare-uat-runner`
- 验证：档案中的 hostname / SKU / 双 runner slot / `/var/cache/buildx` 与只读 SSH 盘点一致
- 相关：`icare-uat-runner-2` 档案见 `icare-uat-runner-2/README.md`

# icare-uat-runner-1 运维时间线

机器档案：[`icare-uat-runner-1/README.md`](../../icare-uat-runner-1/README.md)

SSH：`ssh icare-uat-runner-1`（兼容 `ssh icare-uat-runner`）→ `icareadmin@10.30.6.4`。主机名 `icare-2-uat-ci-runner`。

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

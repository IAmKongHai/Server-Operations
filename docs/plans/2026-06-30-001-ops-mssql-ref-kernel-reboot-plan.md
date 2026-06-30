---
title: mssql-ref 新内核加载定时重启计划
type: ops
date: 2026-06-30
---

# mssql-ref 新内核加载定时重启计划

## Summary

计划在 `2026-07-01 03:00 CST` 对 `mssql-ref` 执行一次维护重启，用于加载已安装但尚未运行的新内核 `5.15.0-185-generic`。该 VM 的系统时区是 UTC，因此对应 VM 本地时间为 `2026-06-30 19:00 UTC`。

本计划只覆盖重启前检查、定时重启、重启后验证和文档记录；不改 SQL Server 配置、不改数据库 schema/data、不改防火墙、不改 Tailscale 配置。

## Current State

- 服务器：`mssql-ref`（`192.168.2.20`）
- Tailscale IP：`100.124.140.78`
- VM 时区：`Etc/UTC`
- 当前运行内核：`5.15.0-181-generic`
- 已安装新内核：`5.15.0-185-generic`
- 重启标记：`/run/reboot-required` 存在
- SQL Server 当前可达地址：`100.124.140.78,1433`

## Maintenance Window

- 用户期望时间：`2026-07-01 03:00 CST`
- VM 本地执行时间：`2026-06-30 19:00 UTC`
- 预期影响：
  - VM 会短暂离线。
  - SQL Server、SSH、Tailscale 会随 VM 重启中断。
  - 重启完成后，SQL Server 和 Tailscale 应由 systemd 自动恢复。
- 预计中断时间：通常 1-3 分钟；如果系统启动或服务恢复较慢，按 10 分钟观察窗口处理。

## Preconditions

执行定时重启前必须再次确认：

1. 用户明确同意设置 `2026-07-01 03:00 CST` 的定时重启。
2. `mssql-ref` 上没有正在进行的 SQL Server 恢复、备份、导入、长事务或手工维护。
3. 当前 SSH 可登录，且 Tailscale 已登录。
4. SQL Server 服务当前处于正常运行状态。
5. VM 没有明显磁盘满、系统时间异常或 boot 分区异常。

## Proposed Execution

### 1. 重启前只读预检

- 确认时间换算：
  - `date`
  - `timedatectl`
- 确认待加载内核：
  - `uname -r`
  - `dpkg -l "linux-image-*"`
- 确认服务状态：
  - `systemctl is-active mssql-server`
  - `systemctl is-active tailscaled`
- 确认可达性：
  - SSH 可登录
  - `100.124.140.78:1433` TCP 可连通

### 2. 设置定时重启

推荐在当前时区为 UTC 的 VM 上使用 UTC 时间设置：

```bash
sudo shutdown -r 19:00 "Scheduled reboot to load kernel 5.15.0-185-generic; target time 2026-07-01 03:00 CST"
```

说明：

- 该命令需要在 `2026-06-30 19:00 UTC` 之前执行。
- 如果执行时已经晚于 `2026-06-30 19:00 UTC`，不能再使用这个命令，需要重新确认维护窗口。

### 3. 定时任务确认

设置后立即确认：

```bash
systemctl status systemd-shutdownd 2>/dev/null || true
cat /run/systemd/shutdown/scheduled 2>/dev/null || true
```

## Cancellation

如需取消已设置的定时重启：

```bash
sudo shutdown -c
```

取消后确认：

```bash
cat /run/systemd/shutdown/scheduled 2>/dev/null || true
```

若无输出，表示没有待执行的 systemd shutdown 计划。

## Post-Reboot Verification

重启窗口后执行：

1. 确认 VM 恢复：
   - `ssh mssql-ref 'uptime'`
2. 确认新内核已加载：
   - `ssh mssql-ref 'uname -r'`
   - 期望值：`5.15.0-185-generic`
3. 确认 SQL Server 正常：
   - `ssh mssql-ref 'systemctl is-active mssql-server'`
   - 从本机测试 `100.124.140.78:1433` TCP 连通性
4. 确认 Tailscale 正常：
   - `ssh mssql-ref 'tailscale ip -4'`
   - 期望仍包含 `100.124.140.78`
5. 确认重启标记是否清除：
   - `ssh mssql-ref 'ls -l /run/reboot-required /var/run/reboot-required 2>/dev/null || true'`

## Rollback And Recovery

- 重启本身不可回滚；可在执行前用 `sudo shutdown -c` 取消。
- 如果重启后 SQL Server 未恢复：
  - 先查 `systemctl status mssql-server --no-pager` 和 `journalctl -u mssql-server -b --no-pager`。
  - 未经用户确认，不手工重启 SQL Server 或改配置。
- 如果 Tailscale IP 不可达：
  - 先通过普通 SSH 别名 `mssql-ref` 登录检查 `tailscaled` 状态。
  - 未经用户确认，不改 Tailscale 配置。
- 如果新内核启动异常导致 VM 不可达：
  - 通过 PVE 控制台检查启动状态。
  - 必要时从 GRUB 选择旧内核 `5.15.0-181-generic` 启动，作为恢复路径。

## Documentation

实际设置定时重启后，追加 `docs/operations/mssql-ref.md`，记录：

- 设置时间
- 计划重启时间（CST 与 UTC 两种）
- 预期影响
- 取消方式
- 定时任务确认结果

重启完成后再追加一条记录，记录：

- 实际恢复时间
- 启动后内核版本
- SQL Server 与 Tailscale 验证结果
- 是否仍存在 `/run/reboot-required`

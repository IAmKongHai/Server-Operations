---
title: PVE 9 节点级 RRD 文件损坏导致节点图表不可读
date: 2026-06-12
category: docs/solutions/pve/runtime-errors
server: pve
module: pve / rrdcached
problem_type: runtime_error
component: tooling
severity: medium
symptoms:
  - PVE Web UI 节点 overview 图表可能不显示
  - pvesh get /nodes/pve/rrddata 报 rrd_fetch_r failed
  - pmxcfs 每 10 秒持续记录 RRD update error
root_cause: corrupted_cache
resolution_type: cache_rebuild
tags: [pve, proxmox, rrd, rrdcached, pvestatd, monitoring]
---

# PVE 9 节点级 RRD 文件损坏导致节点图表不可读

## Context

`pve` 升级到 PVE 9 系后，节点级监控历史文件 `/var/lib/rrdcached/db/pve-node-9.0/pve` 变成 0 字节。PVE Web UI 的节点 overview 图表可能不显示，命令行读取节点 RRD 也失败。

本次只影响节点级 RRD。`pve-vm-9.0/110`、`pve-vm-9.0/120`、`pve-vm-9.0/130` 和 `pve-storage-9.0/pve/*` 均能正常返回数据。

## Symptoms

节点 RRD API 报错：

```text
RRD error: rrdcached@unix:/var/run/rrdcached.sock: rrd_fetch_r failed: mmaping file '/var/lib/rrdcached/db/pve-node-9.0/pve': Invalid argument
```

系统日志每 10 秒重复：

```text
pmxcfs[1011]: [status] notice: RRDC update error /var/lib/rrdcached/db/pve-node-9.0/pve: -1
pmxcfs[1011]: [status] notice: RRD update error /var/lib/rrdcached/db/pve-node-9.0/pve: mmaping file '/var/lib/rrdcached/db/pve-node-9.0/pve': Invalid argument
```

文件状态：

```text
-rw-r--r-- 1 root root 0 May 16 10:02 /var/lib/rrdcached/db/pve-node-9.0/pve
```

## Root Cause

节点级 RRD 文件损坏为 0 字节，`rrdcached` 无法 mmap 该文件。`pvestatd` 仍通过 `pmxcfs` 持续向 `pve-node-9.0/pve` 写节点指标，因此错误按采集周期持续出现。

本次排除的基础原因：

- `/` 与 `/var/lib/rrdcached` 磁盘空间充足。
- inode 使用率正常。
- 文件和目录权限正常。
- 系统时间已同步。
- hostname 与 `/etc/hosts` 解析正常。
- `pvesm status` 正常，storage 查询没有 DNS 或挂载延迟。
- VM 级和 storage 级 RRD 文件正常。

## Resolution

采用最小修复：只移走损坏的节点级 RRD 文件，让 PVE 重新生成节点 RRD。不要先清空整个 `/var/lib/rrdcached/db`，否则会丢失 VM 与 storage 图表历史。

执行顺序：

1. 停止 `pvestatd`，停止 `rrdcached.socket` 与 `rrdcached.service`。
2. 备份并改名损坏的 `/var/lib/rrdcached/db/pve-node-9.0/pve`。
3. 启动 `rrdcached.socket`、`rrdcached.service`、`pvestatd`。
4. 等待约 30 秒到数分钟，让节点 RRD 重新生成。
5. 验证节点 RRD API、VM/storage RRD API 和最近日志。

本次实际保留：

```text
/root/pve-node-rrd-pve.20260612-134546.bak
/var/lib/rrdcached/db/pve-node-9.0/pve.bad.20260612-134546
```

修复后新文件：

```text
-rw-r--r-- 1 root root 1504296 Jun 12 13:46 /var/lib/rrdcached/db/pve-node-9.0/pve
```

## Verification

修复后验证：

- `pvesh get /nodes/pve/rrddata --timeframe hour --cf AVERAGE --output-format json` 能返回节点 RRD 数据。
- `pvesh get /nodes/pve/qemu/<vmid>/rrddata --timeframe hour --cf AVERAGE --output-format json` 对 VM `110`、`120`、`130` 正常。
- `pvesh get /nodes/pve/storage/local/rrddata --timeframe hour --cf AVERAGE --output-format json` 正常。
- 13:46 之后没有新的 `RRD/RRDC/rrdcached/pve-node` 错误。
- 三台 VM 仍为 `running`，三个 storage 仍为 `active`。

## Rollback

可把保留的坏文件放回原路径，但这只会恢复原损坏状态，主要用于保留现场：

```bash
systemctl stop pvestatd
systemctl stop rrdcached.socket rrdcached.service
cp -a /var/lib/rrdcached/db/pve-node-9.0/pve.bad.20260612-134546 /var/lib/rrdcached/db/pve-node-9.0/pve
systemctl start rrdcached.socket rrdcached.service
systemctl start pvestatd
```

功能性回滚通常不需要做；如果新 RRD 已正常采集，应保留修复后的文件。

## Notes

- 此类修复会丢失节点级图表历史，但本次原文件已为 0 字节，没有可用历史。
- PVE 9.2 升级不应代替坏文件修复；已损坏的 0 字节 RRD 文件未必会被升级自动修好。
- 如果 VM 或 storage RRD 同时损坏，不要照搬本方案直接全量清库，应先确认影响范围并备份相关文件。

## Related

- `docs/operations/pve.md`：2026-06-12 13:50 记录本次修复。
- `docs/plans/2026-06-12-001-fix-pve-rrd-then-upgrade-plan.md`：本次执行计划。
- Proxmox forum: [Proxmox 9 no data in the overview](https://forum.proxmox.com/threads/proxmox-9-no-data-in-the-overview.170239/)
- Proxmox pve-devel: [Expand and migrate RRD data and add/change summary graphs](https://lore.proxmox.com/pve-devel/DBOJ7YLX5AL1.3M8J791J4K9J4%40proxmox.com/)

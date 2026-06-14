---
title: PVE 快照 vs 备份策略 —— 单宿主测试环境为何当前不配自动备份
date: 2026-06-14
category: docs/solutions/pve/best-practices
server: pve
module: pve / 备份与快照
problem_type: best_practice
component: tooling
severity: low
tags: [pve, snapshot, backup, vzdump, prune-backups, disaster-recovery, retention, test-environment]
---

# PVE 快照 vs 备份策略 —— 单宿主测试环境为何当前不配自动备份

## Context

`pve` 宿主机上跑着几台测试/参考 VM（`110/mssql-ref`、`120/mas-csharp`、`130/mas-go-dev`）。
2026-06-14 清理掉一批长期堆积的搭建期快照后，引出一个问题：是否应该给这些 VM 配「自动备份、N 天后删除」？

本文记录两件事：
1. 快照与备份在 PVE 里的本质区别（避免再把快照当备份用）。
2. 针对「单宿主机 + 可再生数据」的现状，为什么决定**当前不配自动备份**，以及什么条件下应重新评估。

## 快照 ≠ 备份（PVE 官方定位）

| | 快照 Snapshot | 备份 Backup（vzdump） |
| --- | --- | --- |
| 是什么 | 某时间点的还原点 | 完整打包导出的备份文件 |
| 存在哪 | **同一块物理盘**（本环境 = NVMe thin pool `nvme-data`） | 可存到别的存储（目录型存储 / PBS / NAS） |
| 依赖原盘吗 | **依赖**：物理盘坏，快照一起没 | **独立**：可放到 VM 外，盘坏不影响 |
| 能当灾难恢复吗 | **不能** | 能（前提是存到 VM 外） |
| PVE 官方定位 | 只是 vzdump 的一种 *mode*（`snapshot` 模式 = 临时拍快照做一致性备份后即删），**从不作为备份替代品** | 真正的数据保护手段；「Proxmox 备份永远是全量备份」 |

要点：快照和原数据在同一块物理盘，盘一坏两者全完，所以**绝不能用常驻快照当备份**。
快照的正确用法是「重大变更前临时打、回滚或确认无事后即删」。

## vzdump 保留策略参数（备查）

备份任务用 `prune-backups` 配保留，参数（按给定顺序处理）：

- `keep-last=<N>` —— 保留最近 N 个
- `keep-hourly=<N>` / `keep-daily=<N>` / `keep-weekly=<N>` / `keep-monthly=<N>` / `keep-yearly=<N>`

「2 天后删除」= `prune-backups keep-daily=2`，配合 calendar 定时任务即可。
注意：`prune-backups` 只对**备份文件**生效，**不管 VM 快照**——快照清理在 PVE 里始终是手动 `qm delsnapshot`。

## 当前环境的决策：不配自动备份

### 现状

- **只有一台宿主机**：无论备份存 NVMe（VM 所在盘）还是那块几乎全空的 480G SATA SSD（`local-lvm`，Data% 0%），都在同一台 PVE 上。整机 / 机房级故障（主板、电源、双盘同损）时备份与原数据一起丢，**做不到异地容灾**。单宿主下的本地备份只能防「误删单个文件 / 单 VM 配置写坏」，防不住它名义上要防的灾难场景。
- **数据基本可再生**：
  - 数据库是从生产 `.bak` restore 的参考数据，源 `.bak` 本机还有；
  - 应用代码在所有同事电脑 + GitHub；
  - mas-go-dev 后端可重新 seed。
  - 真正「不可再生」的只有这一个月搭好的环境配置（SQL Server 安装、账号权限、库收缩、IIS/ASP.NET 部署等），重搭费时但做得到。
- **测试/参考环境**：RPO/RTO 要求低，没有「丢一小时数据就出事」的压力。

### 结论

> 单宿主机做不到异地容灾 + 数据可再生 + 测试环境低 RPO/RTO → **当前不配自动备份**。
> 需要回滚点时**手动打快照、用完即删**即可。

自动备份在当前拓扑下，更多是「占空间的安慰剂」：救不了它要救的灾难场景，又为可再生的数据付出存储成本。

## 何时应重新评估（触发条件）

出现以下任一情况，应重新考虑备份策略：

1. **新增第二台宿主机 / 接入 PBS / NAS** —— 具备把备份放到 VM 外的能力，异地容灾才成立。
2. **某台 VM 开始承载不可再生数据** —— 例如不再有外部 `.bak`/seed 来源、或在 VM 上产生了无法重建的状态。
3. **重搭环境的成本变得不可接受** —— 环境复杂到「宁愿花存储也不愿重搭」，此时可对**配置/环境**做低频 vzdump（存到那块空闲的 SATA SSD，`keep-last=2 keep-weekly=2`，每周或手动触发），但要清楚它仍非异地容灾。

## 相关

- 快照清理时间线：`docs/operations/pve.md`（2026-06-14 清理 9 个搭建期快照）。
- PVE 无自动清理快照机制；vzdump 保留策略只管备份文件、不管快照。

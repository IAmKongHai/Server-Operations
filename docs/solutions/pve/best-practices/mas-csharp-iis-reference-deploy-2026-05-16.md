---
title: 在 PVE 上部署 MAS 老 C# / IIS 参考环境
date: 2026-05-16
last_updated: 2026-06-15
category: docs/solutions/pve/best-practices
server: pve
module: pve / mas-win
problem_type: workflow_issue
component: windows-iis
severity: low
tags: [pve, windows-server-core, iis, aspnet-framework, mas, reference-environment]
---

# 在 PVE 上部署 MAS 老 C# / IIS 参考环境

## Context

团队正在用 Go + React 重构 MAS 老系统，需要一套能打开旧页面、登录旧系统并读取旧数据库的参考环境。数据库已在 `mssql-ref` VM 中恢复完成，本次补齐 Windows Server Core + IIS + ASP.NET Framework 应用层。

目标不是生产可用，而是让团队能对照旧行为。旧系统只在局域网开放，不接公网，不恢复真实邮件发送和外部生产回调。

## Decision

在 PVE 上新建独立 VM `mas-win`，运行 Windows Server 2022 Server Core、IIS 和 ASP.NET 4.x。`MAS-API` 与 `MAS-WEB` 分成两个 IIS site / app pool，数据库继续连接 `mssql-ref`。

这个方案的取舍：

- 保留 Windows / IIS / .NET Framework 的真实运行环境，避免 Linux 容器化改造旧系统。
- 使用 Server Core，资源占用低于完整 Windows 桌面版。
- 用 VM 快照分阶段回滚，适合临时参考环境。
- 允许登录/session 所需的最小写入权限，但不把旧环境当生产系统维护。

## Implementation

VM：

| 项目 | 值 |
| --- | --- |
| VMID | `120` |
| Name | `mas-win` |
| IP | `192.168.2.21/24` |
| OS | Windows Server 2022 Standard Evaluation / Server Core |
| CPU / Memory | 4 vCPU / 8 GiB |
| Disk | `nvme-data:vm-120-disk-0`，100G thin-provisioned |
| Network | `e1000` on `vmbr0` |
| On boot | `onboot=1`，`startup=order=20,up=90,down=180` |

ISO / 凭据：

- Windows ISO 使用 Microsoft Windows Server 2022 Evaluation 镜像。
- VirtIO ISO 使用 Fedora `virtio-win.iso`。
- Windows 管理员密码只保存在 PVE `/root/mas-win-secrets.env`，权限 `600`。

Windows 基线：

- 启用静态 IP、WinRM、RDP 和 Windows 防火墙必要规则。
- 安装 VirtIO guest tools / QEMU guest agent。
- PVE guest agent ping 验证通过。
- 快照：`windows-core-ready`。

IIS 基线：

- 安装 IIS、ASP.NET 4.8、.NET Extensibility 4.8、ISAPI Extensions / Filters、Windows Authentication、Management Service 等角色服务。
- IIS 默认站点 HTTP 200 验证通过。
- 快照：`iis-aspnet-ready`。

应用部署：

| 站点 | 端口 | AppPool | 路径 |
| --- | ---: | --- | --- |
| `MAS-API` | `9020` | `MAS-API` | `C:\MAS\Apps\MAS-API` |
| `MAS-WEB` | `9021` | `MAS-WEB` | `C:\MAS\Apps\MAS-WEB` |

配置处理：

- 从 iCare repo `docs/MAS-old-c#/old-C#-code/` 打包 `MAS-API` 和 `MAS-WEB`。
- VM 内保留 `Web.config.orig`，只修改部署副本。
- 数据库连接统一指向 `192.168.2.20,1433`。
- SQL login 使用 `mas_ref_owner`，密码从 `mssql-ref` 的 `/root/mssql-secrets.env` 的 `MSSQL_MAS_REF_OWNER_PASSWORD` 读取。（2026-06-15 更新：原账号 `mas_ref_reader` 已改名为 `mas_ref_owner`，密码不变；改名后需同步 `MAS-API\Web.config`，否则登录失败，详见 [runtime-errors 排查记录](../runtime-errors/mas-web-login-fail-stale-mssql-user-in-mas-api-2026-06-15.md)。）
- `MAS-WEB` 的 `serverlink` 指向 `http://192.168.2.21:9020/`。
- `MAS-WEB` 的环境开关按 NAS 旧部署对齐为 `env=client-prod`。
- `MAS-API` 的环境开关按 NAS 旧部署对齐为 `prodEnv=true`、`uatEnv=false`。
- 静态资源缓存配置与 NAS 旧部署一致，仍为 `clientCache cacheControlMode="UseMaxAge"` / `cacheControlMaxAge="7.00:00:00"`。
- SMTP、旧生产 URL、上传盘路径和外发能力在部署副本中本地化或禁用。
- OAuth client 使用 `authprovidermasweb.dbo.oauth_clients` 中 `user` 记录同步，文档不记录 client secret。

## SQL Permissions

首轮只给该 SQL login 三库 `db_datareader`，但旧 C# 登录链路会调用函数、存储过程，并写入登录状态和 access token。随后为了支持全面 CRUD 测试，按用户确认将该登录提升为三套参考库的 `db_owner`：

| 数据库 | 角色 | 原因 |
| --- | --- | --- |
| `medicalassistance` | `db_owner` | 旧系统核心业务库，需要覆盖新增、修改、删除、审批、登录状态等完整流程 |
| `authprovidermasweb` | `db_owner` | OAuth token、用户认证、异常日志等认证相关写入 |
| `maswebkit` | `db_owner` | WebKit 相关旧模块 CRUD 验证 |

说明：该账号早期叫 `mas_ref_reader`（只读阶段命名），提权为 `db_owner` 后名实不符，已于 2026-06-15 改名为 `mas_ref_owner`（密码不变）。该授权只适用于 PVE 参考环境，不要复制到生产或准生产数据库。

## Validation

2026-05-16 验证结果：

| 检查 | 结果 |
| --- | --- |
| `mas-win` 运行状态 | VM running |
| QEMU guest agent | running / guest ping OK |
| `MAS-API` site | Started |
| `MAS-WEB` site | Started |
| `MAS-WEB` 登录页 | HTTP 200 |
| `MAS-API` 根路径 | HTTP 403，符合无默认文档的 API 站点预期 |
| Windows 到 SQL Server | 三库连接成功，表数量分别为 419 / 9 / 66 |
| 测试账号登录 | HTTP 200，JSON `status=200`、`error=false`；`db_owner` 提权和 preprod 环境开关切换后复测仍通过 |
| 登录后首页 | 带 cookie GET `/` 返回 HTTP 200 |

最终快照：

```text
mas-csharp-preprod-ready
```

## Operational Notes

- `nvme-data` 当前仍在线，但由于多个 VM 快照和 thin provisioning，PVE 会提示 thin volume 逻辑分配总量超过物理池容量。不要长期堆积中间快照。
- `mas-csharp-smoke-ready` 是 UAT/local-reference 阶段的快照；`mas-csharp-preprod-ready` 是当前 preprod/client-prod 环境开关后的推荐回滚点。
- `mssql-ref` 和 `mas-win` 已启用 PVE 自启动。数据库 VM 使用 `startup=order=10,up=60,down=180`，Windows/IIS VM 使用 `startup=order=20,up=90,down=180`，避免宿主机重启后应用早于 SQL Server 可用。
- `mas-win` 当前网卡是 `e1000`。已安装 VirtIO guest tools，后续可在维护窗口切换为 VirtIO 网卡。
- PVE 快照时 Windows 事件日志出现 VSS `8194` warnings，当前不影响 IIS 和登录 smoke。
- 凭据只记录在对应 VM / PVE 的 root-only 文件中，仓库文档不要写明文密码、token 或 OAuth secret。

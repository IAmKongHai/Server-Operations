# mas-web-app 运维操作时间线

> Azure 生产 VM `MAS-WEB-APP`（`172.0.0.8`），订阅 `e026db6e-ee32-47f1-b49c-da9e5f0441b8` / 资源组 `IHC-POC-RG`。
> Windows Server 2016 Datacenter（`2016-datacenter-gensecond`），`Standard_D8s_v5`，southeastasia，管理员 `iCARE_Admin`。
> 无公网 IP，只有 C 盘。定位：iCare 老系统（MAS / Toplogic 系）生产 IIS 应用服务器。
> **按生产对待**：任何重启 / 启停站点 / 改配置前必须先备份并征得用户确认。

## 2026-08-24 - 只读排查：本机无 tvs 服务，确认 TVS 在独立 VM

- 服务器：`MAS-WEB-APP`（`172.0.0.8`）
- 操作人：`Claude`
- 原因：延续 `Pre-Prod-Server` 那轮排查，继续在这台生产机上找名字含 `tvs` 的服务。
- 选型 / 影响：**全程只读**。走 `az vm run-command invoke --command-id RunPowerShellScript` 在 VM 内执行 `Get-Service` / `Get-CimInstance Win32_Service` / `Get-ScheduledTask` / `Get-Process` / `Get-Website` / `Get-ChildItem IIS:\AppPools` / `Get-ChildItem -Directory` / `Get-PSDrive`。未写文件、未启停任何服务或站点、未改任何配置。唯一副作用是 VM 内起过几个短暂的 PowerShell 查询进程（8 核机，负载可忽略）。
- 备份：无需（无变更）。
- 回滚方式：无需（无变更）。
- 定位过程：
  1. `az network nic list` 在两个订阅里按 `privateIPAddress=='172.0.0.8'` 反查，命中 NIC `mas-web-app261` → VM `MAS-WEB-APP`（rg `ihc-poc-rg`）。
  2. `powerState` = `VM running`；VM 扩展只有 `enablevmAccess` 与 `Site24x7WindowsServerAgent`。
  3. 磁盘：仅 C 盘，已用 487.1 GB / 剩余 536.3 GB。
- tvs 七路只读搜索，**全部无命中**：

  | 检查项 | 命令 | 结果 |
  | --- | --- | --- |
  | 服务名 / 显示名 | `Get-Service` + `-like '*tvs*'` | 0 |
  | 服务二进制路径 | `Get-CimInstance Win32_Service` + `PathName -like '*tvs*'` | 0 |
  | 计划任务 | `Get-ScheduledTask` 按 TaskName / TaskPath | 0 |
  | 运行中进程 | `Get-Process` 按 Name | 0 |
  | IIS 站点 | `Get-Website` 按 Name / PhysicalPath | 0 |
  | IIS 应用池 / 子应用 / 虚拟目录 | `Get-ChildItem IIS:\AppPools`、`Get-WebApplication`、`Get-WebVirtualDirectory` | 0 |
  | 全盘目录名（C 盘 4 层） | `Get-ChildItem -Recurse -Depth 4 -Directory -Filter '*tvs*'` | 仅 `wnetvsc.inf` / `wnetvsc_vfpp.inf` 的 DriverStore / WinSxS 目录——Hyper-V 合成网卡驱动，与业务无关 |

- 本机实际承载 —— IIS（`W3SVC` + `WAS` 均 Running），只有两个业务站点：

  | 站点 | 端口 / 绑定 | 物理路径 | 状态 |
  | --- | --- | --- | --- |
  | Default Web Site | `*:80:` | `%SystemDrive%\inetpub\wwwroot` | Stopped |
  | MASWEB | `*:80:` | `C:\Toplogic\MAS Web` | Started |
  | MASAPI | `*:9020:` | `C:\Toplogic\MAS API` | Started |

- 非系统服务（`PathName` 不在 `C:\Windows\` 下且 Running）**全是监控与安全 agent，没有任何业务服务**：
  - Datadog：`datadogagent`、`datadog-process-agent`、`datadog-trace-agent`、`datadog-system-probe`、`Datadog Installer`
  - Trend Micro：`ds_agent` / `ds_monitor` / `ds_notifier`（Deep Security）、`Amsp`（Solution Platform）、`CloudEndpointService`（env prod / region ap3）、`tm_netsrv`、`Trend Micro Endpoint Basecamp`
  - Site24x7：`Site24x7 Windows Agent`、`Applog Agent`、`Plugin Agent`、`Agent Helper`
  - 其它：`ir_agent`（Rapid7 Insight）、`ManageEngine UEMS - Agent` + Health Checker、`NCPA`（Nagios）、`FSMLogAgent`（Fortinet FortiSIEM）、`AnyDesk`
  - Azure：`WindowsAzureGuestAgent`、`RdAgent`
- 值得注意：生产机上常驻 **AnyDesk 服务**（`C:\Program Files (x86)\AnyDesk\AnyDesk.exe --service`）。已向用户提示确认是否为预期运维通道，本次未做任何处置。
- 结论：`tvs` 既不在 `10.100.0.37`（`Pre-Prod-Server`）也不在 `172.0.0.8`（`MAS-WEB-APP`）。TVS 是同订阅 `IHC-POC-RG` 下的独立 VM `TVS-Server`（私网 `172.0.3.4`，公网 `20.195.101.224`），电源状态 `VM deallocated`，需先启动才能查其内部服务——属状态变更动作，未执行，待用户确认。
- 交叉参考：见 `docs/operations/pre-prod-server.md` 同日条目。

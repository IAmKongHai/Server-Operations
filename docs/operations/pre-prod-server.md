# pre-prod-server 运维操作时间线

> Azure 预生产 VM `Pre-Prod-Server`（`10.100.0.37`），订阅 `e026db6e-ee32-47f1-b49c-da9e5f0441b8` / 资源组 `IHC-UAT-RG`。
> Windows Server 2016 Datacenter，`Standard_B4as_v2`，southeastasia，管理员 `iCare_Admin`。
> 定位：iCare 老系统（MAS / Toplogic 系）IIS 应用服务器，代码在 `C:\Toplogic\`。

## 2026-08-24 - 只读盘点 IIS 站点，确认 TVS 不在这台机器上

- 服务器：`Pre-Prod-Server`（`10.100.0.37`）
- 操作人：`Claude`
- 原因：需要找一个名字含 `tvs` 的服务，怀疑跑在这台预生产机上。
- 选型 / 影响：全程只读。走 `az vm run-command invoke --command-id RunPowerShellScript` 在 VM 内执行 `Get-Service` / `Get-Website` / `Get-ChildItem IIS:\AppPools` / `Get-ScheduledTask` / `Get-ChildItem -Directory`，未改任何配置、未启停任何站点或服务。
- 备份：无需（无变更）。
- 回滚方式：无需（无变更）。
- 定位过程：
  1. `az network nic list` 在两个订阅里按 `privateIPAddress=='10.100.0.37'` 反查，命中 NIC `pre-prod-server30` → VM `Pre-Prod-Server`（rg `ihc-uat-rg`）。
  2. VM 扩展只有 `AzurePolicyforWindows`、`enablevmAccess`、`GuestAttestation`、`Site24x7WindowsServerAgent`。
  3. VM 内 `W3SVC` + `WAS` 在跑，确认是 IIS 服务器。
- 盘点结果 —— IIS 站点（除 `Default Web Site` 外全部 Started）：

  | 站点 | 端口 / 绑定 | 物理路径 |
  | --- | --- | --- |
  | Default Web Site | `*:80:`、`808:*`（**Stopped**） | `%SystemDrive%\inetpub\wwwroot` |
  | MAS Web | `*:80:` | `C:\Toplogic\Web\MAS Web` |
  | MAS API | `*:8443:` | `C:\Toplogic\API\MAS Web API` |
  | HR Portal | `*:8080:`、`*:8180:`、`*:8082:` | `C:\Toplogic\Web\HR Portal` |
  | Member Portal | `*:8025:`、`*:8026:` | `C:\Toplogic\Web\Member Portal` |
  | Webkit API | `*:4859:`、`*:9443:` | `C:\Toplogic\API\Webkit API` |
  | MAS Web Archive | `*:6130:` | `C:\Toplogic\MAS Archive\MAS Web` |
  | MAS API Archive | `*:6120:` | `C:\Toplogic\MAS Archive\MAS Web API` |
  | SUPIortaAPI（Sales Portal） | `*:6444:`、`*:6443:preprod.icare.com.ph` | `C:\Toplogic\API\SalesPortalAPIPreprod` |
  | Webkit API T7 | `*:7720:preprod.icare.com.ph` | `C:\Toplogic\API\Webkit API` |

- 应用池：`HR Portal`、`MAS API`、`MAS API Archive`、`MAS Web`、`MAS Web Archive`、`Member Portal`、`Sales Portal`、`Webkit API`、`Webkit API T7`（均 Started / v4.0），外加 IIS 自带的 `.NET v2.0`、`.NET v4.5`、`DefaultAppPool` 等。`Get-WebApplication` / `Get-WebVirtualDirectory` 为空——所有服务都是站点级，没有子应用。
- 另有一批 `C:\Toplogic\SRA\` 下的批处理程序：`SRA Batch Claims Processing`、`SRA Approved Claim Billings`、`SRA LOA Auto Approval`、`SRA NOTIFY USERS`、`SRA Report Manager v2`、`SRA Retail Application Approval`、`SRA Upload Batch Claims Processing 1~6`、`SRA Upload Batch LOA Mapping`、`SRA Upload File Claims Processing`、`SRA Web Email`、`SRA HR Portal Terminate Members`、`Member Importing`。
- 监控 / 安全：Site24x7 四个 agent 服务（Windows / Applog / Plugin / Agent Helper）+ Trend Micro Endpoint Basecamp + `tm_netsrv` + Windows Defender。
- 验证（tvs 三路搜索均在 VM 内执行）：
  - `Get-Service` 名称 / 显示名含 `tvs` → **0 条**
  - `Get-ScheduledTask` 任务名 / 路径含 `tvs` → **0 条**
  - `Get-ChildItem C:\ -Recurse -Depth 4 -Directory -Filter '*tvs*'` → 只命中 Hyper-V 网卡驱动 `wnetvsc.inf` / `wnetvsc_vfpp.inf` 的 DriverStore / WinSxS 目录，与业务无关
- 结论：**TVS 不在 `10.100.0.37` 上**，而是同订阅 `IHC-POC-RG` 下的独立 VM。
- TVS 所在机器（`az resource list` 按名字搜 `tvs` 得到）：
  - VM `TVS-Server`，rg `IHC-POC-RG`，Windows Server 2016 DC，`Standard_B8as_v2`，southeastasia，管理员 `iCare-Admin`
  - 私网 `172.0.3.4`（注意与 UAT 网段 `10.100.0.x` 不同段），公网 `20.195.101.224`
  - 关联资源：`TVS-Server-nsg`、`TVS-Servers-nsg`、`TVSServernsg167`、`TVS-Server-Public-IP`、`tvs-server259`（NIC）、`TVS-Server_OsDisk_1_c04af...`
  - **电源状态：`VM deallocated`（已解除分配）**——所以无法用 `run-command` 看它内部跑什么服务；要查需先启动 VM，属状态变更动作，未执行，待用户确认。
- 后续（2026-08-24）：又只读排查了生产机 `MAS-WEB-APP`（`172.0.0.8`，rg `IHC-POC-RG`），同样七路搜索无 tvs 命中，详见 `docs/operations/mas-web-app.md`。

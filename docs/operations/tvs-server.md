# tvs-server 运维操作时间线

> Azure VM `TVS-Server`，订阅 `e026db6e-ee32-47f1-b49c-da9e5f0441b8` / 资源组 `IHC-POC-RG`。
> Windows Server 2016 Datacenter，`Standard_B8as_v2`，southeastasia，管理员 `iCare-Admin`。
> 私网 `172.0.3.4`（子网 `ihc-poc-vnet/TVS` = `172.0.3.0/28`，**子网无 NSG**），公网 `20.195.101.224`（Static / Standard SKU）。
> NIC `tvs-server259`，NIC 级 NSG `TVSServernsg167`（仅 HTTP 80 / HTTPS 443 入站放通给 `*`）。
> **实际角色：SQL Server 2016 SP2 双实例数据库服务器**（不是 Web 服务器，IIS 未安装）。
> 常态：`VM deallocated`（平时关机）。

## 2026-08-24 - 临时开机只读排查，定位 tvs 为数据库名（非 Windows 服务）

- 服务器：`TVS-Server`（`172.0.3.4`）
- 操作人：`Claude`
- 原因：连续在 `Pre-Prod-Server`（`10.100.0.37`）、`MAS-WEB-APP`（`172.0.0.8`）上按「服务名含 tvs」搜索均无命中，需要开机确认这台同名机器上到底跑什么。
- 选型 / 影响：
  - 开机前**先断公网**（用户选定方案 A：从 NIC 解绑公网 IP，物理移除入口，而非靠 NSG 规则拦），再开机，全程无公网暴露。
  - 开机前先给 OS 盘做快照兜底。
  - VM 内部检查**全程只读**（`Get-Service` / `Get-CimInstance` / `Get-ScheduledTask` / `Get-Process` / `Get-Website` / `Get-NetTCPConnection` / `Invoke-Sqlcmd` 查询 / `Select-String`），未改任何配置、未启停任何服务。
  - 原规格 `Standard_B8as_v2` 在 southeastasia **无容量**，两次 `az vm start` 均 `AllocationFailed`；按 Azure 建议临时改 `Standard_D8as_v5`（同 8 vCPU）才起来，查完已改回。
- 备份：OS 盘快照 `TVS-Server-osdisk-snap-20260824-preboot`（Standard_LRS，tags `purpose=pre-boot-safety-snapshot` / `delete-after=2026-09-24`）。VM 仅一块 OS 盘 `TVS-Server_OsDisk_1_c04af16289d34c0089f0bd3557d41231`（StandardSSD_LRS），无数据盘。
- 回滚方式：所有改动均已按逆序还原（见下「收尾核验」）。如需回到开机前磁盘状态，用上述快照建盘替换 OS 盘。
- 变更时序：
  1. 只读盘点网络：NIC `tvs-server259` / NSG `TVSServernsg167`（仅 80、443 入站，**无 3389、无 SQL 端口**）/ 子网 `TVS` 无 NSG、无路由表 / 公网 IP 为 Static+Standard（确认解绑不丢地址）。
  2. 建 OS 盘快照 → `Succeeded`。
  3. （中途方案调整）先加过临时规则 `TempDenyAllInbound`（prio 100 Deny 全入站），用户改选方案 A 后**已删除**，NSG 回到原始两条规则。
  4. `az network nic ip-config update --remove publicIPAddress` 解绑公网 IP；核验 `TVS-Server-Public-IP` 资源保留、`20.195.101.224` 未丢、`attachedTo: null`。
  5. `az vm start` ×2 → `AllocationFailed`（区域无 `B8as_v2` 容量）；`provisioningState` 一度为 `Failed`（磁盘经查完好 `Attached`/`Succeeded`，订阅配额无限制）。
  6. `az vm resize --size Standard_D8as_v5` → `Succeeded`（同时把 `provisioningState` 修回 `Succeeded`）→ `az vm start` 成功，`VM running`，`publicIPs` 为空。
  7. Guest Agent 就绪后经 run-command 只读排查（详见下）。
  8. 收尾：`az vm deallocate` → `az vm resize` 回 `Standard_B8as_v2` → 公网 IP 绑回 `ipconfig1`。
- 排查结果 —— **tvs 是数据库名，不是 Windows 服务名**（这解释了前三轮按服务名搜全空）：
  - 服务名 / 服务二进制路径 / 计划任务 / 进程名 四路搜 `tvs` → **全部 0 命中**
  - 全盘目录名搜 `tvs` → 只有 Hyper-V 网卡驱动 `wnetvsc.inf` 巧合匹配
  - **IIS 完全没装**（`W3SVC` / `WAS` 服务不存在，`Get-Website` 无输出），但有空的 `C:\inetpub`
  - SQL Server 2016 双实例，tvs 库在 `MSSQLSERVER01`：

    | 数据库 | 实例 | 状态 | 创建时间 | 恢复模式 | 兼容级别 |
    | --- | --- | --- | --- | --- | --- |
    | `mastvsdb` | MSSQLSERVER01 | ONLINE | 2026-06-24 15:51 | FULL | 130 |
    | `mastvsdb_uat` | MSSQLSERVER01 | ONLINE | 2026-06-24 15:37 | FULL | 130 |
    | `masdb` | MSSQLSERVER01 | ONLINE | 2026-06-24 15:19 | — | — |
    | `medicalassistance_replicated` | MSSQLSERVER01 | ONLINE | 2026-06-24 16:33 | — | — |

  - 实例端口：**`MSSQLSERVER01` 监听 `0.0.0.0:4330`**（非标准端口，PID 2156）；默认实例 `MSSQLSERVER` 监听 `0.0.0.0:1433`（PID 3064，只有系统库）
  - 服务状态：`MSSQL$MSSQLSERVER01` / `MSSQLSERVER` / `SQLAgent$MSSQLSERVER01` / `SQLBrowser` 均 Running+Automatic；`SQLSERVERAGENT`（默认实例）Stopped+Manual
  - 已装软件：SQL Server 2016 SP2（KB4052908）、SSMS 22、Visual Studio、.NET 10 SDK、ODBC 13/18 + OLE DB 19 —— 带开发工具，像兼作开发 / 迁移用的库机
  - 也装了 **AnyDesk 服务**（与 `MAS-WEB-APP` 一致）
- 权限边界：run-command 以 `NT AUTHORITY\SYSTEM` 执行，可读服务器级元数据（`sys.databases`），但**被拒绝访问 `mastvsdb` / `mastvsdb_uat` 库内容**（`Login failed ... Failed to open the explicitly specified database`）。未自行授权、未改任何 SQL 权限，故拿不到表结构与数据量。
- 关机前抓取的连接证据（机器一关这些动态视图就清空，故先抓后关）：
  - `sys.dm_exec_connections` + `dm_exec_sessions`：**当前无任何外部连接**，四条全是 `<local machine>`（SQL CEIP 遥测、SQLAgent Generic Refresher / Email Logger，以及本次排查自己的查询）
  - `Get-NetTCPConnection -State Established` 过滤 `sqlservr`：**空**
  - `sp_readerrorlog`（本次开机后）：只有本次排查被拒的 4 条记录
  - 归档 `ERRORLOG.1~3`（停机前历史，2026-06-26）：出现过 SQL 登录名 **`tvsadminsp`** 登录失败（当时实例为「仅 Windows 认证」）；`sa` 亦多次失败；所有 `[CLIENT: ...]` 来源均为 `<local machine>` 或 `172.0.3.4`（本机自己），**无任何其它服务器 IP**
  - 现状 `sys.server_principals`：**只有 `sa`，`tvsadminsp` 已不存在**；认证模式已改为混合模式（`IsIntegratedSecurityOnly = 0`），`sa` 的 `modify_date` = 2026-06-26 09:52 —— 6/26 有人调过认证配置，但 tvs 应用账号最终没建起来
- 网络侧线索：
  - 资源组内另有两个**未绑定任何 NIC / 子网**的 NSG：`TVS-Server-nsg`、`TVS-Servers-nsg`。两者规则与在用的 `TVSServernsg167` 相同，**都只有 HTTP 80 / HTTPS 443 入站，没有任何 SQL 端口（1433 / 4330）规则**。
  - 推断：TVS-Server 最初是按 **Web 服务器**规划的（三个只开 80/443 的 NSG + 公网 IP + `C:\inetpub`），后来实际被拿去装 SQL Server 双实例，网络配置从未按 DB 用途调整过。
  - VNet `ihc-poc-vnet` = `172.0.0.0/21`，TVS 独占子网 `172.0.3.0/28` 且**子网无 NSG** → 同 VNet 内其它机器（如 `MAS-WEB-APP` 172.0.0.8 所在的 `172.0.0.0/25`）在网络层可直达 `172.0.3.4:4330`。
  - `ihc-poc-vnet` 有 **4 条 Connected 对等互连，全部 `allowForwardedTraffic: true`**：
    - `ihc-uat-vnet`（同订阅 `ihc-uat-RG`）
    - `IHC-VNet-01`（订阅 `408f1434-...` / `ihc-rg-001`）
    - `IHC-VNet-Hub`（订阅 `408f1434-...` / `IHC-Connectivity-RG`，中心辐射 hub）
    - **`icare-2-uat-vnet`**（订阅 `408f1434-...` / `iCare-2.0-UAT`，即 `icare-uat-runner-1/2` 所在 VNet）
  - 因此网络可达范围远超单个 VNet：**TVS 子网无 NSG + 四向 peering 全通**，上述各 VNet 内机器在网络层均可直达 `172.0.3.4:4330`。唯一的收窄因素是 NIC 级 NSG `TVSServernsg167`——但它只放通 80/443，**并未放通 4330**，所以实际入站 SQL 流量应当是被 NIC NSG 拦住的（NSG 默认拒绝未匹配入站）。这与「历史日志中从无外部 IP 连入」互相印证。
  - 无 App Service / Function App（`az webapp list`、`az functionapp list` 均空）。Application Gateway `ihc-poc-waf` / `ihc-uat-app-gw` 的后端池中**无 `172.0.3.4`**（后端仅 `10.0.0.19`、`10.100.0.36`）。无 Load Balancer。
- 收尾核验（逐项对照初始状态，全部一致）：

  | 项目 | 初始 | 收尾后 |
  | --- | --- | --- |
  | 电源 | `VM deallocated` | `VM deallocated` |
  | provisioningState | `Succeeded` | `Succeeded`（中途的 `Failed` 已消除） |
  | 规格 | `Standard_B8as_v2` | `Standard_B8as_v2` |
  | 私网 IP | `172.0.3.4` | `172.0.3.4` |
  | 公网 IP 绑定 | 绑在 `ipconfig1` | 已绑回 `ipconfig1` |
  | 公网地址 | `20.195.101.224` | `20.195.101.224`（未变） |
  | NSG 入站规则 | HTTP 300 / HTTPS 443@320 | 同初始，临时规则无残留 |

- 遗留物：快照 `TVS-Server-osdisk-snap-20260824-preboot` 保留（标签 `delete-after=2026-09-24`），会产生少量存储费用，待用户决定是否删除。
- 横向排查「哪个服务在访问这台 DB」（2026-08-24 同日进行）：
  - 方法：对**运行中**的 Windows VM 用 run-command 只读执行 `Select-String`，在 `C:\Toplogic`、`C:\inetpub`、IIS `applicationHost.config`、UiPath 目录、用户 Documents/Desktop 等位置搜连接串特征 `172.0.3.4` / `TVS-Server` / `MSSQLSERVER01` / `mastvsdb` / `tvsadminsp` / `Server=...4330`。脚本内置密码遮蔽（`password=***`），不输出明文口令。
  - 踩坑：初版正则含 `,4330`，命中 2021 年理赔日志里的金额 `4330.00`（`finalamount` / `basicclaim` 等）造成大量误报；收紧为只匹配连接串上下文后复扫。
  - 阴性结论（**0 真命中**），本订阅 `e026db6e-...` 19 台：`MAS-WEB-APP`、`MAS-Search-Engine-Server`、`RPA-Commander`、`RPA-Worker01`~`RPA-Worker13`（13 台全扫）、`ihc-poc-db`、`Pre-Prod-Server`、`ihc-app-uat-1`。其中 `RPA-Commander` 作为 RPA 编排中心无 TVS 连接串，是较有分量的阴性证据。
  - 阴性结论（**0 真命中**），跨订阅 `408f1434-...` 6 台（覆盖与 `ihc-poc-vnet` 有 peering 的 VNet）：`icare-2-uat-app01`、`icare-2-uat-db01`、`ihc-phws-001`、`ihc-phdb-001`、`iCare-Companion-Apps`、`E-Billing-APP-UAT`。
  - Azure 侧补充阴性证据：
    - 无 App Service / Function App（`az webapp list`、`az functionapp list` 均空）
    - Application Gateway `ihc-poc-waf` / `ihc-uat-app-gw` 后端池无 `172.0.3.4`；无 Load Balancer
    - **Network Watcher 存在但未配置任何 NSG flow log**（`az network watcher flow-log list` 返回空）→ 无历史流量记录可查，只能靠客户端连接串取证
  - 初步判断（待剩余机器扫完确认）：这套 tvs 库很可能**尚无任何服务在使用**。证据链：库 2026-06-24 建立 → 6/26 有人把实例从「仅 Windows 认证」改为混合模式并尝试 `tvsadminsp` 登录（失败）→ 该登录名至今不存在 → NSG 从未放通 4330 → DB 侧历史无任何外部 IP 连入 → 客户端侧遍扫无连接串。像是**搭了一半停下的迁移/新建项目**。
- 交叉参考：`docs/operations/pre-prod-server.md`、`docs/operations/mas-web-app.md` 同日条目。

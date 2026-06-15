---
title: "改 mssql-ref 登录账号后 MAS-WEB 登录失败：根因在 MAS-API 残留旧用户名"
server: pve
module: pve / mas-win
date: 2026-06-15
problem_type: runtime_error
component: windows-iis
symptoms:
  - "mssql-ref 把 mas_ref_reader 改名 mas_ref_owner 后，MAS-WEB 登录页 http://192.168.2.21:9021/ 登录失败"
  - "报错出现在 9021（WEB 层），但 MAS-WEB 的 Web.config 不含任何数据库用户名"
  - "MAS-API（9020）的 Web.config 仍引用已停用账号 mas_ref_reader，导致后端连库认证失败"
  - "VM、IIS 站点、应用池都在运行，HTTP 层未整体宕机，问题只在连库这一层"
root_cause: config_error
resolution_type: config_change
severity: high
related_components:
  - authentication
  - database
tags:
  - mssql
  - connection-string
  - web-config
  - iis
  - qemu-guest-agent
  - powershell-encodedcommand
  - mas-legacy
  - utf8-no-bom
---

# 改 mssql-ref 登录账号后 MAS-WEB 登录失败：根因在 MAS-API 残留旧用户名

## Problem

把 `mssql-ref`（192.168.2.20）上的 SQL Server 登录账号从 `mas_ref_reader` 改名为 `mas_ref_owner`（密码、权限不变）后，MAS C# 老系统的登录页 `http://192.168.2.21:9021/`（MAS-WEB）登录失败。根因是 `mas-win` VM 上 MAS-API 站点的 `Web.config` 里仍写着旧账号 `mas_ref_reader`（共 33 处），导致 EF / ADO.NET 连库认证失败。

## Symptoms

- `http://192.168.2.21:9021/`（MAS-WEB）登录失败；账号改名前正常，改名后才出问题，时间点高度吻合。
- MAS-WEB 的 `Web.config` 不含任何数据库用户名——它不直连库，所有库访问都走 MAS-API。
- MAS-API（9020）根路径返回 403（WebAPI 根无目录浏览的**正常**行为，并非故障信号，排查时一度被误读）。
- VM、IIS 站点、应用池本身都在运行，HTTP 层并未整体宕机——问题只在“连库”这一层。

## What Didn't Work

1. **误以为是 WEB 层 / 缓存问题**
   登录入口在 9021（MAS-WEB），第一反应去查 MAS-WEB 配置。实际 `MAS-WEB\Web.config` 根本不含任何数据库用户名，在 WEB 层找连接串属于方向错误。

2. **误把 MAS-API 根路径 403 当故障**
   403 是 WebAPI 没有默认目录浏览的正常表现，不能据此判断 API 挂了。

3. **多层 shell 内联 PowerShell —— 转义地狱**
   命令链是 `本地 zsh → ssh → qm guest exec → powershell`，PowerShell 变量符号被逐层吃掉：
   - `powershell -Command "...$_.Matches..."`：`$_` 被中途解释吞掉，报 `]` 解析错误。
   - 内联多变量替换脚本：`$path`、`$content`、`$false` 全变空，`WriteAllText(,,...)` 参数为空、`New-Object UTF8Encoding()` 丢参，报 `Missing ')'`。
   结论：跨 4 层的内联引号/变量无法稳定转义，这条路走不通。

4. **UTF-8 base64 喂给 `-EncodedCommand`**
   先用 UTF-8 的 base64 传给 `powershell -EncodedCommand`，PowerShell 解不出来。`-EncodedCommand` 强制要求 **UTF-16LE** 编码后的 base64。

## Solution

全程用 PVE 宿主的 QEMU guest agent（`qm guest exec`）远程下命令，**无需 SSH 进 Windows**。

**1. 定位 VM 与确认 guest agent**

```bash
ssh pve "qm list"                      # mas-win = VMID 120
ssh pve "qm config 120"                # agent: enabled=1，guest exec 可用
```

**2. 在 Windows 内定位站点、物理路径与配置文件**

```bash
ssh pve 'qm guest exec 120 -- cmd.exe /c "ipconfig"'          # 确认 192.168.2.21
ssh pve 'qm guest exec 120 -- cmd.exe /c "appcmd list site"'  # MAS-API:9020 / MAS-WEB:9021
ssh pve 'qm guest exec 120 -- cmd.exe /c "appcmd list vdir"'  # C:\MAS\Apps\MAS-API 等
# 全量搜旧账号：只在 MAS-API\Web.config 命中，MAS-WEB 不含库用户名
ssh pve 'qm guest exec 120 -- cmd.exe /c "findstr /S /I /M /C:\"mas_ref_reader\" C:\MAS\Apps\MAS-API\*.config C:\MAS\Apps\MAS-WEB\*.config"'
```

`C:\MAS\Apps\MAS-API\Web.config` 里 `mas_ref_reader` 出现 **33 处**：`<appSettings>` 的 `DATA_SOURCE_A~D / USER_ID_A~D / PASSWORD_A~D`（对应库 medicalassistance、maswebkit、insularsalesportal、masprepaid）、`MsdbSqlConnection` 内联连接串，以及 `<connectionStrings>` 里约 30 个 EF 连接串（AuthDbContext、AccountsEntities、ClaimsEntities …）。

**3. 备份配置文件**

```bash
ssh pve 'qm guest exec 120 -- cmd.exe /c "copy /Y C:\MAS\Apps\MAS-API\Web.config C:\MAS\Apps\MAS-API\Web.config.bak.20260615"'
```

**4. 用本地 .ps1 + EncodedCommand 整文件替换（绕开转义）**

把替换逻辑写成本地脚本，不让任何 shell 解释脚本内容：

```powershell
# replace.ps1
$path = 'C:\MAS\Apps\MAS-API\Web.config'
$content = [System.IO.File]::ReadAllText($path)
$content = $content.Replace('mas_ref_reader','mas_ref_owner')   # 密码不动
# UTF-8 无 BOM 写回，避免 BOM 破坏 XML
[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))
```

转成 **UTF-16LE** 的 base64（注意不是 UTF-8 base64）并下发：

```bash
B64=$(iconv -f UTF-8 -t UTF-16LE replace.ps1 | base64 | tr -d '\n')
ssh pve "qm guest exec 120 -- powershell.exe -NoProfile -EncodedCommand $B64"
# 返回 err-data 里的 #< CLIXML ... progress ... 是 PowerShell 进度流噪音，非错误
```

**5. 回收应用池让新配置生效**

```bash
ssh pve 'qm guest exec 120 -- cmd.exe /c "appcmd recycle apppool /apppool.name:MAS-API"'
```

**6. 验证（两层都要看，光看 HTTP 不够）**

```powershell
# 6a. HTTP 探活（VM 内执行，同样走 EncodedCommand）
Invoke-WebRequest -UseBasicParsing -Uri 'http://192.168.2.21:9021/'   # 期望 200

# 6b. 真·连库验证：用新凭据跑 ADO.NET，确认登录身份与库
$cs = "data source=192.168.2.20,1433;initial catalog=medicalassistance;user id=mas_ref_owner;password=***;Connection Timeout=15"
$c = New-Object System.Data.SqlClient.SqlConnection $cs
$c.Open()
$cmd = $c.CreateCommand(); $cmd.CommandText = "SELECT SUSER_SNAME(), DB_NAME()"
$r = $cmd.ExecuteReader(); $r.Read()
"OK login=$($r[0]) db=$($r[1])"   # 期望 OK login=mas_ref_owner db=medicalassistance
$c.Close()
```

结果：9021 返回 HTTP 200；连库测试返回 `OK login=mas_ref_owner db=medicalassistance`。修复完成。

**回滚**：还原备份并回收应用池即可：

```bash
ssh pve 'qm guest exec 120 -- cmd.exe /c "copy /Y C:\MAS\Apps\MAS-API\Web.config.bak.20260615 C:\MAS\Apps\MAS-API\Web.config"'
ssh pve 'qm guest exec 120 -- cmd.exe /c "appcmd recycle apppool /apppool.name:MAS-API"'
```

## Why This Works

MAS 是分层结构：**MAS-WEB（9021）只是前端站点，自己不直连数据库**；所有数据访问都委托给 **MAS-API（9020）**，连接串（appSettings 的 DATA_SOURCE/USER_ID/PASSWORD、MsdbSqlConnection、约 30 个 EF connectionStrings）全部集中在 `MAS-API\Web.config`。

因此当数据库登录账号改名后，唯一需要同步的就是 MAS-API 的 `Web.config`。改完回收 MAS-API 应用池，EF / ADO.NET 用新凭据重建连接池，登录链路即恢复。WEB 层无需任何改动——去查 WEB 层只会白费功夫。

`-EncodedCommand` 之所以能解决转义：base64 后的脚本是不透明字节流，`zsh → ssh → qm guest exec` 各层都不会再解析里面的 `$`、引号、括号，PowerShell 收到后整体解码执行，从根本上消灭了多层转义问题。

## Prevention

1. **改库账号 / 密码前，先全量 grep 所有客户端连接串**，按文件逐一改。本例 33 处恰好都在一个文件，但同一账号可能散落在多个站点、多个 config、外加内联连接串：

   ```bash
   ssh pve 'qm guest exec 120 -- cmd.exe /c "findstr /S /I /M /C:\"<旧账号>\" C:\MAS\Apps\*.config"'
   ```

2. **跨多层 shell 给 Windows 下 PowerShell，统一用 `-EncodedCommand`（UTF-16LE base64）**，别再内联拼引号和变量：

   ```bash
   B64=$(iconv -f UTF-8 -t UTF-16LE script.ps1 | base64 | tr -d '\n')
   ssh pve "qm guest exec 120 -- powershell.exe -NoProfile -EncodedCommand $B64"
   ```
   必须 UTF-16LE，不是 UTF-8；写回 XML 用 UTF-8 无 BOM。

3. **验证以“真实连库”为准，不要只看 HTTP 200**。HTTP 200 只说明站点活着；`SELECT SUSER_SNAME(), DB_NAME()` 返回预期账号 / 库才证明凭据真能连库。同时记住 MAS-API 根 403 是正常现象。

4. **凭据集中化、避免明文散落**。当前同一账号在单文件硬编码 33 处、密码明文。可考虑收敛到环境变量 / 单一配置源，或用 `aspnet_regiis -pe` 加密 `connectionStrings` / `appSettings` 配置节，下次改账号只改一处且不留明文。

5. **明文密码风险**：`Web.config` 及备份 `Web.config.bak.20260615` 中数据库密码均为明文，注意备份文件的留存与访问权限，勿随站点目录对外暴露。

## Related Issues

- [在 PVE 上部署 MAS 老 C# / IIS 参考环境](../best-practices/mas-csharp-iis-reference-deploy-2026-05-16.md) —— 本次故障的直接上游：定义了 `mas-win` IIS 双站点与连接串指向，文中账号名 `mas_ref_reader` 已被本次改名推翻。
- [PVE 上 MAS 老系统参考 SQL VM](../best-practices/mas-legacy-reference-sql-vm-2026-05-16.md) —— 定义 `mssql-ref` 库与初始登录账号，是 `mas_ref_reader → mas_ref_owner` 改名链条的起点。
- [sqlcmd 跨多层 shell 的转义陷阱](../../best-practices/sqlcmd-shell-pitfalls-2026-05-13.md) —— 同类问题（本地→ssh→exec→sqlcmd）在 SQL 场景的版本，可与本文的 PowerShell EncodedCommand 解法相互参照。

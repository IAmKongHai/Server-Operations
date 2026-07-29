# mas-win 运维操作时间线

## 2026-07-29 15:20 CST - 验证 HRLink 浏览器登录成功（Dashboard）

- 服务器：`mas-win`（`192.168.2.21:9023`）+ `MAS-Webkit-API:4859`
- 操作人：`Grok`
- 原因：用户反馈登录卡住；此前 API 已通但 ego-browser UI 验证未完成。
- 做了什么（只读验证，无配置变更）：
  - 复现：裸 `POST /api/auth` 若不带正确 **HMAC app-sign**，`HttpContentHashMiddleware` 抛 500（空 body）。
  - app-sign 算法（前端 `Ly` / CryptoJS）：密钥未登录时为 ContentHashing `DefaultKey`=`[660JVJTe}tM`；`keyB64=Base64(Utf8(key))`，`app-sign=Base64(HmacSHA256(bodyJson, keyB64))`。
  - 正确签名后 `POST http://192.168.2.21:9023/api/auth` → **200**，`success=true`，`fullname=San Jose, Lourence T`，`companyname=ABC COMPANY`，`subscriptionno=3917`，Set-Cookie `__Hst-Spa-HR`。
  - 浏览器：Pinia `auth_user.loginUsernamePassword` + `router.push('/dashboard?from=login')` 成功进入 Dashboard。
  - 可见数据：POLICY PERIOD、Member Enrollment、Recent Upload Members（含 batch 3199 等）、Event Logs 区。
- 性能注意：Webkit `GET /me` 偶发 **20–40s**，页面会长时间显示 `LOADING ...`；登录总耗时约 20s+ 属后端慢，不是前端死循环。
- 自动化坑：`wait()` 单位是**秒**；`wait(10000)` 会假死。Vue 登录表单绑定 `r.username/r.password`，纯 DOM 赋值可能不触发 v-model；表单成功后需 `router.push`。
- 回滚：无（只读）。

## 2026-07-29 15:05 CST - 修复 HRLink 登录：auth DB + 密码过期

- 服务器：`mas-win` / `mssql-ref`
- 操作人：`Grok`
- 原因：登录失败。排查链路后发现两层问题：
  1. （此前）`appsettings.Development.json` 覆盖导致请求 cloudkit（已修）。
  2. **Webkit** `Web.config` 连 **`authprovidermas`**，mssql-ref 上该库不存在/登录失败；OAuth 校验在 `GetOAuthClientDetails` 炸。
  3. 账号 `jts@toplogic.com.ph` 在 `maswebkit.dbo.tblsubscriptioncompany.passwordexpiry=2025-10-31`，业务返回 **errorcode 2003 密码过期**。
- 做了什么：
  - `MAS-Webkit-API\Web.config`：`authprovidermas` → **`authprovidermasweb`**；`apicachemas` 暂改指 `maswebkit`（库不存在）。
  - SQL：`UPDATE tblsubscriptioncompany SET passwordexpiry=DATEADD(year,5,GETDATE()) WHERE emailaddress='jts@toplogic.com.ph'`（1 行）。
- 验证：`POST http://192.168.2.21:9023/api/auth`（带 app-sign）→ **HTTP 200**，`success=true`，`subscriptionno=3917`，`companyname=ABC COMPANY`。
- 回滚：恢复 `Web.config.bak.authdb-20260729`；把 `passwordexpiry` 改回原值。
- 说明：浏览器需硬刷新后再登；ego-browser 任务空间被用户接管未完成 UI 自动化，但 API 登录已通。

## 2026-07-29 14:51 CST - 修复 HRLink 误连 cloudkit.toplogic.com.ph

- 服务器：`mas-win`（`192.168.2.21`）
- 操作人：`Grok`
- 原因：登录 HR Link 时后端报 `No such host is known. (cloudkit.toplogic.com.ph:6030)`。排查发现 `web.config` 将 `ASPNETCORE_ENVIRONMENT=Development`，ASP.NET Core 用 `appsettings.Development.json` **覆盖**了 `appsettings.json` 里已改好的 `http://192.168.2.21:4859/`。
- 影响：
  - `ASPNETCORE_ENVIRONMENT` 改为 **Production**。
  - `appsettings.json` / `appsettings.Development.json` 的 `IHCWebkitAPI` 均改为 `http://192.168.2.21:4859/`。
  - Login ClientId/Secret 恢复为发布包生产值（供 OAuth 对 Webkit）；OTP 仍指本机无效地址。
  - 回收 `HRLinkPortal` 应用池。
- 验证：站点 9023 仍 200；4859 `/login` 仍返回 API JSON 400（路由存活）。用户需再试登录；若仍失败再查 `authprovidermas` / CryptLib / OAuth client 数据。
- 回滚：改回 Development + Development.json 中 cloudkit 地址（不推荐）。

## 2026-07-29 14:08 CST - 覆盖部署 HRLink 真实 SPA 前端

- 服务器：`mas-win`（PVE VM `120`，`192.168.2.21`）
- 操作人：`Grok`
- 原因：`http://192.168.2.21:9023/` 仍是 B1 占位 `index.html`（wwwroot 仅 1 文件），用户无法看到真实 Insular HR Link 登录 UI。
- 影响：
  - 用完整包 `HRLinkPortalProdv2`（wwwroot 275 文件）覆盖 `C:\MAS\Apps\HRLinkPortal`。
  - 短暂停止 `HRLinkPortal` 站点/应用池以释放日志文件锁。
  - `IHCWebkitAPI` 保持 `http://192.168.2.21:4859/`；上传路径本地化；关闭 HTTPS 跳转。
- 回滚：无完整镜像备份；可从 iCare 包重新部署或恢复占位页（不推荐）。
- 验证：
  - `GET /` → 200，title **Insular HR Link**，入口 `assets/index.19d8eae8.js`。
  - `GET /assets/index.19d8eae8.js` → 200，约 536KB。
  - 浏览器强制刷新（Ctrl+F5）后应见真实前端而非 Reference Environment 占位文案。

## 2026-07-29 10:55 CST - 部署 MAS-Webkit-API（TopLogic.WebApi :4859）

- 服务器：`mas-win`（PVE VM `120`，`192.168.2.21`）
- 操作人：`Grok`
- 原因：为 HR Link / MAP 提供参考环境用的 **Webkit / Companion API**（生产站名 `MASAPIProd`，主程序 `TopLogic.WebApi.dll`），替代此前把门户指到管理端 `MAS-API:9020` 的 B1 占位。
- 影响：
  - 新增 IIS 站点 **`MAS-Webkit-API:4859`**、AppPool `MAS-Webkit-API`、防火墙入站 `4859`。
  - 部署路径：`C:\MAS\Apps\MAS-Webkit-API`（来源 iCare `docs/MAS-old-c#/old-C#-code/MAS-Webkit-API`）。
  - `Web.config` 本地化：SQL → `192.168.2.20,1433` / `mas_ref_owner`；`CATALOG_A=medicalassistance_preprod`；`BaseUrl=http://192.168.2.21:4859/`；上传目录 → `C:\MAS\Data\Webkit\...`；去掉 URL Rewrite 段（Server Core 未装 Rewrite 模块，否则 500.19）。
  - `HRLinkPortal` `appsettings.json` 的 `IHCWebkitAPI` → `http://192.168.2.21:4859/`。
  - `MemberPortal` `Web.config` 的 `MemberPortalAPI` → `http://192.168.2.21:4859/`。
  - **未**从生产机拷文件；未改 Azure / 生产。
- 回滚方式：
  - 删除站点/AppPool `MAS-Webkit-API` 与目录 `C:\MAS\Apps\MAS-Webkit-API`。
  - 恢复 `appsettings.json.bak.webkit-20260729`、`Web.config.bak.webkit-20260729`（MemberPortal / HRLink）。
  - 配置原件：`Web.config.orig`。
- 做了什么：
  1. 修正本地目录名尾部空格后打包 `MAS-Webkit-API`。
  2. PVE 临时 HTTP 传入 Windows Staging，解压到 `C:\MAS\Apps\MAS-Webkit-API`。
  3. 本地化配置 + 建站 4859。
  4. 门户 API 基址改指 4859。
- 验证结果：
  - 站点 `MAS-Webkit-API` **Started**，`*:4859` 监听。
  - `GET http://192.168.2.21:4859/` → **403**（API 无默认页，符合预期）。
  - `POST /login` → **400** JSON `parameters null or missing`（路由已工作，缺加密参数）。
  - `POST /checkpasswordexpirycompany` 明文测试 → **500** `CryptographicException: Length of the data to decrypt is invalid`（路由已进入业务逻辑，明文非 CryptLib 密文，预期失败）。
  - 现有 `9020`–`9023` 仍可用（HRLink 根路径仍 200）。
- 已知限制：
  - 真登录需 CryptLib 加密字段 + 有效 OAuth client（`authprovidermas` 等库与 `oauth_clients` 数据）。
  - 配置仍引用 `authprovidermas`、`apicachemas`；与 mas-win 管理端常用的 `authprovidermasweb` 可能不同，业务登录前需核对 mssql-ref 库是否齐全。
  - 无 `Global.asax`（发布包未带）；当前路由已能响应。
  - OTP 微服务仍未部署。

## 2026-07-28 15:05 CST - 部署 MemberPortal(9022) + HRLinkPortal(9023)（B1 仅前端）

- 服务器：`mas-win`（PVE VM `120`，`192.168.2.21`）
- 操作人：`Grok`
- 原因：在既有 MAS-API/MAS-WEB 参考环境上，增加会员门户（MemberPortal）与 HR Link 门户（HRLinkPortal / InsularHRPortal），策略为 **B1：仅前端可打开**，不部署真实 Webkit API / OTP。
- 影响：
  - 新增 IIS 站点 `MemberPortal:9022`、`HRLinkPortal:9023` 及对应 AppPool、防火墙入站规则。
  - 安装 **ASP.NET Core 6.0.36 Hosting Bundle**（ANCM V2 + runtime）。
  - 部署目录：`C:\MAS\Apps\MemberPortal`、`C:\MAS\Apps\HRLinkPortal`；数据目录：`C:\MAS\Data\MemberPortal\...`、`C:\MAS\Data\HRLinkPortal\...`。
  - 短暂 `iisreset`（Hosting Bundle 安装后），现有 MAS-API/MAS-WEB 随之重启后已恢复。
  - **不**影响数据库；登录/业务 API 调用预期失败（B1）。
- 回滚方式：
  - 恢复 PVE 快照 `portals-pre-deploy`；或删除两个新站点/AppPool/目录后 `iisreset`。
  - Hosting Bundle 可保留（对 MAS Framework 站点无害）。
- 做了什么：
  1. 创建快照 `portals-pre-deploy`。
  2. 本机打包 `MemberPortalProd` / `HRLinkPortalProdv2`，经 PVE 临时 HTTP（`192.168.2.10:18080`）拉入 Windows `C:\MAS\Staging\portals-20260728`。
  3. 静默安装 `dotnet-hosting-6.0.36-win.exe`，`iisreset`。
  4. 解压到 `C:\MAS\Apps\` 并重命名；删除 macOS AppleDouble `._*`（否则 MemberPortal 解析 `App_Browsers/._*` 会 500）。
  5. 本地化配置（保留 `*.orig`）：
     - MemberPortal：`MemberPortalAPI=http://192.168.2.21:9020/`，`SkipOTP=1`，上传路径改 `C:\MAS\Data\MemberPortal\...`，SMTP host `127.0.0.1`、密码 `DISABLED-REF-ENV`。
     - HRLink：`IHCWebkitAPI=http://192.168.2.21:9020/`，OTP 指 `127.0.0.1:9`，上传路径改 `C:\MAS\Data\HRLinkPortal\...`，ClientSecret 脱敏；去掉 URL Rewrite/HTTPS 跳转；`ASPNETCORE_ENVIRONMENT=Development`（启用 Swagger）；补 `wwwroot/index.html` 占位（发布包 wwwroot 为空）。
  6. 建 AppPool（MemberPortal CLR v4.0；HRLinkPortal No Managed Code）+ 站点 + 防火墙。
  7. 清理 PVE 临时 HTTP 与 `/tmp/maswin-portals-transfer`。
- 验证结果：
  - `http://192.168.2.21:9022/` → **HTTP 200**，页面 title `Sign In - Member Portal`。
  - `http://192.168.2.21:9023/` → **HTTP 200**（参考占位页）。
  - `http://192.168.2.21:9023/swagger/index.html` → **HTTP 200**；`swagger/v1/swagger.json` 可用。
  - `http://192.168.2.21:9021/` MAS-WEB 仍 200；`9020` MAS-API 仍 403（预期）。
  - HRLink `POST /api/auth/login` 返回应用层 500（无真实 Webkit + ContentHash 中间件，B1 预期限制）。
- 已知限制：
  - 无独立 Member/HR Webkit API（`:4859` 族）；业务登录与数据对照不可用。
  - HRLink 原包 `wwwroot` 静态前端资源缺失，仅 API + Swagger + 占位首页。
  - 无 OTP / PDF / 真实 SMTP。

## 2026-06-22 17:32 CST - 放置 2307 PDF 表单结果文件

- 服务器：`mas-win`（PVE VM `120`，`192.168.2.21`）
- 操作人：`Codex`
- 原因：需要把本地 PDF `mas-win/2307_Report_Form.pdf` 放到 MAS 老 C# / IIS 参考应用的附件目录，并按应用期望文件名保存为 `2307_Pdf_Form_Result.pdf`。
- 影响：
  - 新建目录 `C:\MAS\Apps\MAS-WEB\Attachments\BIR`。
  - 新增文件 `C:\MAS\Apps\MAS-WEB\Attachments\BIR\2307_Pdf_Form_Result.pdf`。
  - 未重启 VM、IIS site、app pool 或任何服务，未修改 IIS / 应用配置。
- 回滚方式：
  - 删除 `C:\MAS\Apps\MAS-WEB\Attachments\BIR\2307_Pdf_Form_Result.pdf`。
  - 如确认目录不再需要且为空，可删除 `C:\MAS\Apps\MAS-WEB\Attachments\BIR`。
- 做了什么：
  1. 本地确认源文件存在，大小 `297824` bytes，SHA256 为 `1ac4bff2cd79a8c5c4abc3d8d05770943e0e2dab49cf77b901bc9c35e5c5b43f`。
  2. 通过 `ssh pve` 使用 PVE guest agent 确认 VM `120` 正在运行，目标目录和目标文件此前均不存在。
  3. 将 PDF 临时复制到 PVE `/tmp/maswin-2307-transfer/`，在 PVE 上短暂启动只服务该目录的 HTTP server。
  4. 通过 `qm guest exec 120` 在 Windows VM 内执行 PowerShell：创建目标目录、从 `http://192.168.2.10:18080/2307_Report_Form.pdf` 下载到临时文件，再移动为目标文件。
  5. 停止临时 HTTP server，并清理 PVE 临时目录。
- 验证结果：
  - PVE 临时 HTTP server 日志显示 `192.168.2.21` 成功请求 `GET /2307_Report_Form.pdf`，返回 `200`。
  - VM 内目标文件大小为 `297824` bytes。
  - VM 内目标文件 SHA256 为 `1ac4bff2cd79a8c5c4abc3d8d05770943e0e2dab49cf77b901bc9c35e5c5b43f`，与本地源文件一致。

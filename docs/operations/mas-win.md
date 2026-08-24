# mas-win 运维操作时间线

## 2026-08-24 23:32 CST - MAS-API / Webkit 连到 ihc20260824 preprod catalog

- 服务器：`mas-win`（`192.168.2.21`）
- 操作人：`Grok`
- 原因：mssql-ref 已恢复 10.100.0.4 最新库；C# 参考站仍指旧 `maswebkit` / `insularsalesportal` / `masprepaid` / `authprovidermasweb`。
- 影响：
  - 只改现网 `C:\MAS\Apps\MAS-API\Web.config` 与 `MAS-Webkit-API\Web.config`。
  - `maswebkit` → `maswebkit_preprod`；`insularsalesportal` → `insularsalesportal_preprod`；`masprepaid` → `masprepaid_preprod`；`authprovidermasweb` → `authprovidermasuat_preprod`。
  - `medicalassistance_preprod`、`msdb`、`medicalassistance_replicated`（`pvLinkedServerMAS`）未改。
  - MemberPortal / HRLink / MAS-WEB 无直连 SQL，未改。回收 `MAS-API`、`MAS-Webkit-API` 池。
- 备份：`Web.config.bak.20260824-ihc-cut`（两站各一份）。
- 回滚：用上述 bak 覆盖回 `Web.config` 后再 recycle 对应池。
- 验证：CATALOG_B/C/D/SEARCH 与 Auth 连接串已是新名；`pvLinkedServer=maswebkit_preprod`。HTTP `9021/9022/9023` **200**，`9020/4859` **403**（API 无默认页，预期）。
- 相关：`mssql-ref/databases.md`

## 2026-08-20 15:36 CST - 登录页 version 改回新包显示值

- 服务器：`mas-win` / `MAS-WEB:9021`、`MemberPortal:9022`
- 操作人：`Grok`
- 原因：覆盖时还原了已本地化的旧 `Web.config`，页脚 `ver` 仍显示覆盖前版本，看起来像没换包。
- 选型 / 影响：只改正文版本号；SQL / OAuth / 路径 / SkipOTP 等本地化项未动。改 `Web.config` 会让 IIS 自动回收对应应用池（短暂中断）。
- 备份：`C:\MAS\Apps\MAS-WEB\Web.config.bak.version-20260820`、`C:\MAS\Apps\MemberPortal\Web.config.bak.version-20260820`
- 回滚方式：用上述 bak 覆盖回 `Web.config`（池会再回收一次）。
- 变更：
  - MAS-WEB `version`：`2026.02.19.00` → `2026.08.05.00`
  - MemberPortal `version` / `layoutver`：`2026.01.27.00` → `2026.07.28.00`
  - HRLink：新包登录 JS 自身写死 `ver 2022.12.28.02`，不是旧配置还原，未改。
- 验证（VM 本机 `Invoke-WebRequest`）：
  - `http://127.0.0.1:9021/` HTTP 200，footer / `?v=` = `2026.08.05.00`
  - `http://127.0.0.1:9022/` HTTP 200，footer / `?v=` = `2026.07.28.00`
- 说明：浏览器若仍见旧号，强刷或清缓存（静态资源 `cacheControlMaxAge=7d`）。

## 2026-08-20 14:40 CST - 三个门户登录级 smoke 通过（含 Webkit 缺对象补齐）

- 服务器：`mas-win`（`192.168.2.21`）+ `mssql-ref`（`maswebkit`）
- 操作人：`Grok`
- 原因：`birnaries_20082026` 覆盖后 HTTP 200 已通，但登录级 smoke 未完成。浏览器实测暴露新 Webkit / 新 MemberPortal 依赖参考库里没有的对象。
- 选型 / 影响：
  - 五站进程未重启以外的 IIS 配置；未改防火墙 / crontab / SSH。
  - `maswebkit` 新增兼容存储过程与两列，仅服务参考环境 MemberPortal 登录。
  - 管理端 `ADMIN` 密码按 SQL `dbo.decoder` 方案对齐（不记明文）。
- 备份：PVE 快照仍是 `pre-birnaries-20082026`。`maswebkit` 变更前 `sp_getmaswebmemberdetailsv6` 不存在；`tblsubscriptionmembers` 无 `verifieddepinfo*` 列。
- 回滚方式：
  - 站点：停池后恢复快照 `pre-birnaries-20082026`。
  - 库：`DROP PROCEDURE dbo.sp_getmaswebmemberdetailsv6`；`ALTER TABLE dbo.tblsubscriptionmembers DROP CONSTRAINT DF_tblsubscriptionmembers_verifieddepinfo, DF_tblsubscriptionmembers_verifieddepinfodatetime; ALTER TABLE dbo.tblsubscriptionmembers DROP COLUMN verifieddepinfo, verifieddepinfodatetime;`（在 `maswebkit`）。
- 变更时序：
  1. MAS-API 新 `Helpers.dll` 需要 `DATA_SOURCE_SEARCH` 等 AppSettings（覆盖时还原的旧 Web.config 没有）——已补 SEARCH 键并 remap catalog 到 `maswebkit`，回收 MAS-API 池。
  2. MemberPortal `SignInUser` 现走 Webkit `login?` + `login_type=portal`（AES 加密参数）。`LoginV2` 调用缺失的 `dbo.sp_getmaswebmemberdetailsv6`。
  3. 在 `maswebkit` 用 v5 全文复制出 v6，并增加 `dentalinformation` 列，满足 EF 结果集。
  4. `GetPortalMemberDetailsV10` 读 `tblsubscriptionmembers.verifieddepinfo` / `verifieddepinfodatetime`——表上补两列（bit / datetime，默认 0 与 `19000101`）。
  5. 浏览器跑完 9021 / 9022 / 9023 登录。
- 验证（浏览器，非只贴 HTTP）：
  - `9021` MAS-WEB：title `Dashboard - MAS Web Insular`（ADMIN）。
  - `9022` MemberPortal：邮箱检查 → 密码 → 隐私同意双勾 → `http://192.168.2.21:9022/home/dashboard`，title `Dashboard - Member Portal`，会员 `RIVERA, ARC FREDERICK` / `02826185`。`SignInUser` ≈ 22s，`ContinueSignIn` ≈ 0s。
  - `9023` HR Link：表单走 `/api/auth`（入口 JS 无 `with-otp`）→ `http://192.168.2.21:9023/dashboard?from=login`，用户 `San Jose, Lourence T`，可见 POLICY PERIOD、Member Enrollment、Event Logs。
- 已知限制：
  - v6 是参考环境兼容包装，不是生产脚本同步；`dentalinformation` 固定 0。
  - 新包 `searchengine_db` 仍未接入。
  - Staging / PVE tar 仍在，删除前需确认。
  - Webkit `/me` 与 memberdetails 20–30s 慢路径仍在。
- 计划：`docs/plans/2026-08-20-001-ops-mas-win-csharp-replace-plan.md`

## 2026-08-20 13:50 CST - 用 birnaries_20082026 原地覆盖五个 IIS 站点

- 服务器：`mas-win`（PVE VM `120`，`192.168.2.21`）
- 操作人：`Grok`
- 原因：新版 C# 发布包到位，替换参考环境上的五个老站点（管理端 API/Web、MemberPortal、HRLink、Webkit API）。
- 选型 / 影响：
  - 站点名、端口、应用池不变。
  - 覆盖期间五站短暂停止；`C:\MAS\Data` 未动。
  - 配置沿用覆盖前已本地化的副本（SQL → `mssql-ref` / `mas_ref_owner` / `medicalassistance_preprod`；门户 API → `:4859`）。
  - 未改防火墙、crontab、数据库。
- 备份：
  - PVE 快照 `pre-birnaries-20082026`（2026-08-20 13:11）。
  - 现网配置与补丁：`C:\MAS\Backup\pre-birnaries-20082026\`。
- 回滚方式：恢复快照 `pre-birnaries-20082026`（停池后回滚）。不要用更旧的 `portals-pre-deploy`（会丢掉 07-29 补丁）。
- 变更时序：
  1. `.gitignore` 忽略 `birnaries_20082026/`（含生产凭据，不入库）。
  2. 快照 + 备份 Web.config / appsettings / StoreFallback / 2307 PDF。
  3. 经 Tailscale 把 gzip 包传到 PVE，再经 `192.168.2.10:18080` 拉进 Windows Staging（PVE HTTP 已关）。
  4. 停五站/池，robocopy 覆盖 `C:\MAS\Apps\*`，还原备份配置与本地补丁文件。
  5. HRLink 入口 JS `index.9d92b79b.js`：`/api/auth/with-otp` → `/api/auth`（1 处）。
  6. 启动五站。
- 验证：
  - `http://192.168.2.21:9021/` → **200**，title `Sign In - MAS Web Insular`
  - `http://192.168.2.21:9022/` → **200**，title `Sign In - Member Portal`
  - `http://192.168.2.21:9023/` → **200**，title `iCare HR Link`，入口 `assets/index.9d92b79b.js`
  - `http://192.168.2.21:9020/` 与 `:4859/` → **403**（API 无默认页，预期）
  - MemberPortal store 任意生产 Profile base64url → **200** `image/png`（306 bytes）
  - `POST :4859/login` JSON → **400**（路由存活）
  - `POST :9021/user-signin` 表单 → **200**（路由存活；未用业务账号做完整登录）
- 已知限制：
  - 登录级 smoke（ADMIN / MemberPortal 两步登录 / HRLink Dashboard）未在本轮用业务账号跑完，需浏览器强刷后再试。
  - 新包 `searchengine_db` 未接入；`apicachemas` 仍 remap 到 `maswebkit`。
  - Staging 仍在 `C:\MAS\Staging\birnaries-20082026\`，PVE `/tmp/maswin-birnaries-20082026.tar.gz` 仍在；删除前需确认。
- 计划：`docs/plans/2026-08-20-001-ops-mas-win-csharp-replace-plan.md`

## 2026-07-29 16:20 CST - MemberPortal store 全量本地回退 + 账号2 登录耗时验证

- 服务器：`mas-win` / `MemberPortal:9022`
- 操作人：`Grok`
- 原因：用户强刷后仍见 store 500；Dashboard 极慢。要求用账号 `qnetir@outlook.com` 验证。
- 验证（HTTP，非浏览器填表）：
  - `SignInUser` ≈ **22s** → success（email 匹配）
  - `ContinueSignIn` ≈ **0s** → success
  - 登录后首页 Dashboard HTML ≈ **22s**
  - `GET /member/member-ledger/details` ≈ **22s** → success，会员 `BAHADOR, DAVOUD` / memberno `02826174`
  - 端到端约 **65s**（主要耗在 Webkit `/login` + `/me` + `v7/memberdetails`）
- store：将 `StoreFallbackModule` 改为**所有** `/framework/common/store` 请求直接返回本地 `default-profile.png`（不再尝试外网），验证任意 base64url → **200 image/png**。
- 登录 UI 注意：两步登录——先 `#txtCheckEmail` + `#btnSignInCheck`，再显示密码 `#txtPassword` + `#btnSignIn`。
- ego-browser 自动化中途用户接管 task space，未完成 UI 全程；API 路径已证实可登。
- 回滚：还原 `App_Code/StoreFallbackModule.cs` / 去掉 modules 项，回收 AppPool。

## 2026-07-29 16:05 CST - 修复 MemberPortal store 500 与 Dashboard 日期 JS 崩溃

- 服务器：`mas-win` / `MemberPortal:9022`
- 操作人：`Grok`
- 原因：登录后 Console 大量  
  `GET /framework/common/store?base64url=...` **500**；  
  `tab-dashboard.js` `isValidSqlDate` 对 `undefined` 调用 `.split` 导致表单不加载。
- 根因：
  1. `store` 把 `base64url` 解码成生产地址  
     `https://ap.insularhealthcare.com.ph:2443/Profile/default.png`，再经 `StorageAuth` Basic 拉取；本地/参考网访问生产文件存储失败，控制器 catch 后 **500**。
  2. Dashboard `GetMemberDetails` 部分日期字段为空时，前端未判空。
- 做了什么：
  - 增加本地占位图：`Assets/Images/default-profile.png`
  - `App_Code/StoreFallbackModule.cs`：对生产 Profile URL 的 `store` 请求直接返回本地 PNG（200）
  - `Web.config` 注册模块（备份 `Web.config.bak.store-fallback-20260729`）
  - `utility.js` `storageAuthUrl`：生产/default Profile 直返本地图
  - `tab-dashboard.js` `isValidSqlDate`：null/undefined 安全返回 false
  - 回收 AppPool `MemberPortal`
- 验证：
  - `GET .../store?base64url=aHR0cHM6...default.png` → **200** `image/png`（306 bytes）
  - `GET /Assets/Images/default-profile.png` → **200**
- 回滚：还原 `Web.config.bak.store-fallback-20260729`，删 `App_Code/StoreFallbackModule.cs`，还原 utility/tab-dashboard（无单独 bak 时可从发布包覆盖），回收池。
- 说明：preload 字体 credentials 警告可忽略；业务字段缺失仍取决于 Webkit 会员数据完整性。

## 2026-07-29 15:50 CST - 修复 MemberPortal 登录 Unable to fetch user details

- 服务器：`mas-win` / `MemberPortal:9022` → API `MAS-Webkit-API:4859`
- 操作人：`Grok`
- 原因：账号 `afrivera@icare.com.ph` 登录提示 `Unable to fetch user details. Please contact MIS/IT.`
- 根因：
  1. `SignInUser` 可成功拿 token，但 `ProcceedWithSignIn` 调 `MemberServices.GetMemberDetails` 时请求 **`GET {MemberPortalAPI}v8/memberdetails?...`**。
  2. 当前 Webkit 只注册了 `memberdetails`～`v7/memberdetails`（`v7` 内部已用 V8 SP），**没有 `v8/memberdetails` 路由** → **HTTP 404 HTML**。
  3. `GetMemberDetails` 失败返回 null → `TempSignInResult.user == null` → `ContinueSignIn` 返回 500 文案。
  4. `Logs/login_*.txt` 可见 `user:null`；`Logs/Member Details_*.txt` 可见 `{"error":404,...}`。
- 做了什么：
  - 备份：`C:\MAS\Apps\MemberPortal\bin\MemberPortal.dll.bak.v8-to-v7-20260729`
  - 二进制同长替换（UTF-16LE）：`v8/memberdetails` → `v7/memberdetails`（1 处）
  - 回收 AppPool `MemberPortal`
- 验证：
  - `POST /Home/SignIn/SignInUser` → `success=true`，`initial.emailaddress=afrivera@icare.com.ph`
  - `POST /Home/SignIn/ContinueSignIn` → **`{"success":true}`**
- 回滚：用 `.bak.v8-to-v7-20260729` 覆盖 `MemberPortal.dll` 并回收 AppPool。
- 说明：若后续升级 Webkit 增加正式 `v8/memberdetails` 路由，可再改回 v8。

## 2026-07-29 15:40 CST - 消掉 HRLink 前端 console.error("No") 噪音

- 服务器：`mas-win` / `HRLinkPortal:9023`
- 操作人：`Grok`
- 原因：登录已通，但控制台仍刷 `console.error("No")`（及 app-sign 调试 log）。
- 根因：ContentHash `Ly(msg,key)` 在 msg/key 为空时 `console.error("No")`；GET 无 params 或校验路径会触发。`/api/auth/me` **401** 是未登录探测，属预期，Chrome 会红字记录网络失败，应用层无法完全关掉。
- 做了什么：
  - 备份：`index.19d8eae8.js.bak.console-quiet-20260729`
  - 补丁：空参直接 `return ""`（去掉 `console.error("No")`）；去掉 app-sign 不匹配时的 `console.log(generated/header)`。
  - 仍保留先前 with-otp→auth 修改。
- 验证：下发 JS 中无 `console.error("No")` / `console.log("generated`。
- 回滚：用 `.bak.console-quiet-20260729` 覆盖回 assets（或再叠 `.bak.no-otp-20260729`）。
- 用户：强刷后再看 Console；401 `/me` 打开未登录页时仍可能出现（正常）。

## 2026-07-29 15:35 CST - 修复 HRLink 表单登录 500（with-otp → 无 OTP 路径）

- 服务器：`mas-win` / `HRLinkPortal:9023`
- 操作人：`Grok`
- 原因：用户控制台显示 `POST /api/auth/with-otp → 500`；打开页 `GET /api/auth/me → 401`（未登录预期）。
- 根因：
  - SPA 登录表单默认走 **`/api/auth/with-otp`**（`loginUsernamePassword(..., false)`）。
  - 该接口登录 Webkit 成功后还会调 OTP：`OTHER_API.OTP=http://127.0.0.1:9/`（占位假地址），连接被拒绝 → `HttpRequestException` → **500**。
  - 此前自动化用的是 `loginUsernamePassword(..., true)` → **`/api/auth`**（不走 OTP），所以能进 Dashboard；与用户真实点 Sign In 路径不一致。
- 做了什么：
  - 备份：`wwwroot/assets/index.19d8eae8.js.bak.no-otp-20260729`
  - 补丁：将包内唯一一处 `"/api/auth/with-otp"` 替换为 `"/api/auth"`（本地无 OTP 服务）。
- 验证：
  - 下发 JS 中 `with-otp` 出现次数 = 0。
  - `POST /api/auth` 仍 200；旧 `with-otp` 路由若直打仍会 500（后端未改）。
- 回滚：`Copy-Item ...index.19d8eae8.js.bak.no-otp-20260729 ...index.19d8eae8.js` 后强刷。
- 用户侧：必须 **强刷 / 清缓存** 才能加载新 JS；登录后 `/me` 可能仍慢 20–40s。

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

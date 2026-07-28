# mas-win 运维操作时间线

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

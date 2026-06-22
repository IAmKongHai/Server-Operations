# mas-win 运维操作时间线

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

---
title: tizi-cyp 从 Alma+S-UI 整装为 Debian+3x-ui 并保持 REALITY 身份
date: 2026-08-09
category: docs/solutions/tizi-cyp/best-practices
server: tizi-cyp
module: tizi-cyp / 3x-ui / REALITY 迁移
problem_type: best_practice
component: tooling
severity: high
applies_when:
  - 在 tizi-cyp 或同构主力代理上整装系统并换 3x-ui
  - 需要客户端 UUID/REALITY 密钥与重装前一致
  - 节点同时承载 Tailscale 旁路（如 mssql-ref-proxy）
tags:
  - tizi-cyp
  - 3x-ui
  - xray
  - reality
  - debian
  - s-ui
  - reinstall
  - mssql-ref-proxy
  - tailscale
---

# tizi-cyp 从 Alma+S-UI 整装为 Debian+3x-ui 并保持 REALITY 身份

## Context

`tizi-cyp`（公网 `89.208.242.203`）原为 **AlmaLinux 9 + S-UI 1.5.x + sing-box**，承载主力代理流量与 `mssql-ref-proxy`（TS→mssql-ref:1433）。  
2026-08-09 维护窗整装为 **Debian 13 + 3x-ui 3.6 + Xray 26.7.28**，从本机备份迁回 VLESS+REALITY 身份，面板与跳板改绑**新** Tailscale IP。

通用选型与清单见：

- `docs/solutions/best-practices/proxy-node-3x-ui-debian-upgrade-2026-08-09.md`
- `docs/runbooks/proxy-node-reinstall-upgrade.md`

时间线：`docs/operations/tizi-cyp.md`（备份 01:38、重建 02:02 条目）。

## Guidance

### 重装前

1. 本机备份目录（gitignore）：`_backups/tizi-cyp-pre-reinstall-20260809/`  
   - 关键：`s-ui/s-ui.db`、结构化导出、`mssql-ref-proxy` unit、`authorized_keys`  
2. 服务端 tar 在整装后不可用，**以本机为准**。  
3. 确认云控制台保留公网 IP；DNS `cyp-tz.skysms.xyz` 可不动。

### 重建后标准态（验收锚点）

| 项 | 值 |
|----|-----|
| hostname | `tizi-cyp` |
| 面板 | `tailscale ip -4`:2095 + webBasePath（仅 TS） |
| 数据面 | remark `cyp-tizi`，VLESS+REALITY `:443`，`minClientVer=1.0.0` |
| 分享域名 | `cyp-tz.skysms.xyz`（custom share） |
| 跳板 | **当前** TS IP:1433 → `100.124.140.78:1433`（旧 TS `100.88.178.78` 已废弃） |
| 防火墙 | ufw：22、443、tailscale0 |
| 验收 | `scripts/verify-tizi-cyp-baseline.sh` → `VERIFY_TIZI_CYP_OK` |

### 本机特有注意

- **mssql-ref-proxy** 与代理面板无关但同机；漏恢复会导致 `dev-cypresso` 等经 cyp 跳 MSSQL 失败。  
- 整装后 Tailscale **节点 IP 变化**，任何文档/脚本写死的 `100.88.178.78` 必须作废。  
- 面板账密在 `/etc/x-ui/install-result.env`；完整 URL 用 settings 里的 webListen/webPort/webBasePath 拼，不要用过期的 ACCESS_URL。  
- 禁用客户端可留在面板；运行时 config 不含其 UUID 是正常现象。

## Examples

### 正确打开面板

```text
http://<当前TS_IP>:2095/<webBasePath>/
```

根路径 404 ≠ 服务挂了。

### 回滚跳板

```bash
systemctl disable --now mssql-ref-proxy
rm -f /etc/systemd/system/mssql-ref-proxy.service
systemctl daemon-reload
```

## Why

主力节点整装成本高，必须把「备份拉回本机」「身份字段级迁移」「TS IP 重绑」「旁路服务」写成可检索经验，避免只存在于对话记录。  
cyp 作为第一台从 S-UI 全家迁 3x-ui 的样板，后续 `tizi` / `rao-tizi` 可走同一 runbook，按是否整装 OS 裁剪步骤。

## References

- `docs/runbooks/proxy-node-reinstall-upgrade.md`
- `docs/solutions/best-practices/proxy-node-3x-ui-debian-upgrade-2026-08-09.md`
- `docs/operations/tizi-cyp.md`
- `scripts/verify-tizi-cyp-baseline.sh`

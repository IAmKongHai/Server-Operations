---
title: 代理节点统一为 Debian + 3x-ui/Xray 的选型与升级经验
date: 2026-08-09
category: docs/solutions/best-practices
server: (适用 tizi 族代理节点)
module: 代理节点 / 3x-ui / Xray / REALITY
problem_type: best_practice
component: tooling
severity: medium
applies_when:
  - 将 S-UI/sing-box 或旧系统节点迁到 3x-ui + Xray
  - 重装或新装纯代理节点（公网 22+443，面板仅 Tailscale）
  - 协议只使用 Xray（VLESS+REALITY），需客户端身份可连续
  - 规划 tizi / rao-tizi 等后续节点升级
tags:
  - proxy-node
  - 3x-ui
  - xray
  - reality
  - debian
  - s-ui
  - tailscale
  - minclientver
  - webbasepath
  - tizi-cyp
  - reinstall
---

# 代理节点统一为 Debian + 3x-ui/Xray 的选型与升级经验

## Context

2026-08 在 `tizi-cyp` 上完成：AlmaLinux 9 + **S-UI/sing-box** → **Debian 13 + 3x-ui/Xray** 整装与 REALITY 身份迁移；并与 `tizi-ddy`（已是 Debian+3x-ui）对照。  
约束：协议**只用 Xray**；要主流面板与现代 UI；关心稳定性/性能；另有节点待升级。

操作时间线：`docs/operations/tizi-cyp.md`（2026-08-09 备份与重建条目）。  
逐步命令：`docs/runbooks/proxy-node-reinstall-upgrade.md`。  
单节点 3x-ui 运维细节（分享域名、Flow、复制链接）：`docs/solutions/tizi-ddy/best-practices/3x-ui-proxy-node-aligned-with-s-ui-2026-07-28.md`。  
Shadowrocket 兼容：`docs/operations/tizi-ddy.md`（2026-07-30 `minClientVer`）。

## Guidance

### 1. 选型：什么时候整装、什么时候只换面板

| 目标 | 建议 |
|------|------|
| 协议只要 Xray + 要主流面板 | **3x-ui + Xray**（社区体量远大于 S-UI） |
| 代理专用 VPS 系统 | **Debian 13** 优先（教程/脚本/内核）；Alma 长支持强但非代理首选 |
| 已在 Debian、只嫌 S-UI | **不必重装 OS**，迁面板即可 |
| 已要统一 Debian 且维护窗空闲 | 可整装（cyp 路径） |
| 性能焦虑 | 同量级 VLESS+REALITY 下 Xray/sing-box 差可忽略；cyp 上 S-UI 单进程内存更肥，换 3x-ui 通常不更差 |
| 稳定性 | 3x-ui **更新快**→升级回归风险更高；稳定靠「先从节点试升 + 固定 minClientVer + 不跟风点 Update」 |

**一句话：** 换到 3x-ui+Xray **值得**；为换面板而整机重装 **默认不值得**，除非还要换 OS/清盘。

### 2. 目标暴露面（全节点一致）

```text
公网：22 + 443 only
面板：Tailscale IPv4:2095 + 随机 webBasePath（HTTP，靠 TS 隔离，可不给面板上 SSL）
订阅：不用则 subListen=127.0.0.1 或关闭
数据面：VLESS + REALITY :443，flow=xtls-rprx-vision
REALITY：minClientVer=1.0.0（必填）
BBR + fq；SSH PasswordAuthentication no
```

### 3. 迁移纪律（身份连续）

- **S-UI DB 不能直接导入 3x-ui**。迁移单位是：UUID、REALITY 密钥材料、shortIds、SNI/dest、客户端 enable、分享域名。
- 备份 **先 scp 回本机**（`_backups/`，gitignore），再重装；盘上 `/root/backup` 会随系统消失。
- **Tailscale IP 重装后会变**。所有 `listen`/`bind`（面板、socat 跳板）必须用 `tailscale ip -4` 现值，不能抄旧 operations 里的 `100.x`。
- 新节点若不要求兼容旧客户端：**不要**复制其它机器的 REALITY 私钥（防节点关联）；身份连续场景才「原样迁密钥」。

### 4. 必写的兼容项

| 项 | 为何 |
|----|------|
| `minClientVer=1.0.0` | Xray 较新版本默认最低客户端版本号会拒 Shadowrocket 等（ddy 2026-07-30） |
| `domainStrategy=UseIPv4` / 等价 | dest 有 AAAA 且机器无可用 v6 时，避免 handshake/出站踩 IPv6 |
| Flow=`xtls-rprx-vision` | 空 Flow 时链接可能生成但不可用（见 ddy best-practice） |
| `shareAddrStrategy=custom` + 域名 | 避免分享链接变成 TS IP 或裸公网 IP |

### 5. webBasePath 与访问

- 安装脚本生成随机路径；**根路径 `/` 返回 404 是预期**，不代表服务挂了。
- 完整 URL：`http://<TS_IP>:2095/<webBasePath>/`（需本机在 Tailscale 网内）。
- `install-result.env` 里的 `ACCESS_URL` 常是安装瞬间的公网 IP+临时端口，**迁 listen/port 后以 DB settings 为准**。

### 6. 主机密钥与 SSH

- 重装后 `REMOTE HOST IDENTIFICATION HAS CHANGED` → `ssh-keygen -R <IP>`，与「有没有注入登录公钥」无关。
- 云镜像可能只注入**当前**一把公钥；旧机多把 `authorized_keys` 需事后补全。

### 7. 验收与回归

- 结构：`ss`（443 / TS:2095 / 无公网面板）、`ufw`、`bbr`、config 内启用 UUID 与私钥哈希对账。
- 可选：对公网 443 + 伪装 SNI 做 `openssl s_client`，应看到伪装站证书（如 `*.xbox.com`）。
- cyp 可跑：`scripts/verify-tizi-cyp-baseline.sh`；其它节点复制改 hostname/断言即可。
- 升级 3x-ui/Xray：**先从节点（如 ddy）→ 再主力**；升完立刻测 Shadowrocket。

### 8. 文档落盘约定

| 内容 | 位置 |
|------|------|
| 逐步 runbook | `docs/runbooks/proxy-node-reinstall-upgrade.md` |
| 本通用经验 | 本文 |
| 单机时间线 | `docs/operations/<server>.md` |
| 3x-ui 日用操作 | `docs/solutions/tizi-ddy/best-practices/3x-ui-proxy-node-aligned-with-s-ui-2026-07-28.md` |
| 密钥/DB 备份 | 本机 `_backups/`，**不入库** |

## Examples

### 健康：cyp 重建后（摘要）

- Debian 13，3x-ui 3.6.0，Xray 26.7.28  
- 面板 `100.x:2095` + webBasePath；`*:443` xray；ufw 22+443+tailscale0  
- 6 客户端 UUID 与旧 S-UI 一致；`minClientVer=1.0.0`  
- mssql-ref-proxy bind **新** TS IP:1433  

### 不健康：只开 2095 根路径

- 浏览器访问 `http://TS:2095/` → 404 → 误判「面板挂了」  
- 实为缺少 webBasePath  

### 不健康：升 Xray 后未设 minClientVer

- 桌面 Xray 客户端正常，iOS Shadowrocket 失败  
- 日志提示默认 minimal client version  

## Why

代理节点的核心资产是 **REALITY 身份 + 客户端 UUID + 窄暴露面**，不是某个 Linux 发行版本身。  
3x-ui 在「只要 Xray」时生态与排障成本更优；Debian 降低装机摩擦。  
把 `minClientVer`、TS bind、webBasePath、备份拉回本机写成纪律，后续 `tizi` / `rao-tizi` 升级可重复执行，避免每个节点重新踩坑。

## References

- Runbook：`docs/runbooks/proxy-node-reinstall-upgrade.md`
- cyp 时间线：`docs/operations/tizi-cyp.md`
- ddy 部署心智：`docs/solutions/tizi-ddy/best-practices/3x-ui-proxy-node-aligned-with-s-ui-2026-07-28.md`
- 3x-ui：https://github.com/MHSanaei/3x-ui  
- S-UI：https://github.com/alireza0/s-ui  

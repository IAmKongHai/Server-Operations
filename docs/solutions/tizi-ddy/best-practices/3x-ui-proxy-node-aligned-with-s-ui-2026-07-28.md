---
title: 用 3x-ui 部署扩容代理节点并对齐 S-UI 运维心智
date: 2026-07-28
category: docs/solutions/tizi-ddy/best-practices
server: tizi-ddy
module: tizi-ddy / 3x-ui 代理节点
problem_type: best_practice
component: tooling
severity: medium
applies_when:
  - 新增纯代理扩容节点，参考 tizi / tizi-cyp 暴露面与 REALITY 形态
  - 面板栈选用 3x-ui（Xray）而非 S-UI（sing-box）
  - 需要分享链接固定域名、关闭订阅、客户端可稳定连通
tags:
  - tizi-ddy
  - 3x-ui
  - xray
  - vless
  - reality
  - share-addr
  - bbr
  - tailscale
  - proxy-node
  - s-ui
---

# 用 3x-ui 部署扩容代理节点并对齐 S-UI 运维心智

## Context

需要把公网机 `80.251.215.131`（别名 `tizi-ddy`，Debian 13）建成与 `tizi-cyp` 同角色的**纯扩容代理**：公网只开 `22` + `443`，管理面板只走 Tailscale，数据面 VLESS+REALITY。用户指定面板为 [3x-ui](https://github.com/MHSanaei/3x-ui)，而主节点族（`tizi` / `rao-tizi` / `tizi-cyp`）用的是 S-UI。时间线见 `docs/operations/tizi-ddy.md`。

部署与验收中还踩到 3x-ui v3 特有摩擦：分享链接默认落公网/Tailscale IP、客户端页二维码依赖 subId、REALITY 客户端 Flow 为空时不可用。这些与 S-UI「一门多用户」心智可对齐，但操作入口不同。

## Guidance

### 1. 暴露面与系统基线（对齐 cyp，防火墙按 OS 选型）

| 项 | 目标 |
| --- | --- |
| 角色 | 扩容/分流代理，不装 Nginx/litellm |
| 时区 / hostname | `Asia/Shanghai` / 与 SSH 别名一致 |
| BBR | `tcp_congestion_control=bbr` + `default_qdisc=fq`，写入 `sysctl.d` |
| Tailscale | 已登录；面板只绑 TS IPv4 |
| 公网 | `22` + `443`；面板端口（如 `2095`）不对公网开放 |
| 防火墙 | EL 系用 firewalld；Debian 用 **ufw**（`OpenSSH` + `443/tcp` + `tailscale0` 全放） |
| SSH | 公钥可用后 `PasswordAuthentication no` |
| 观测 | vnstat 监控 `eth0`（及可选 `tailscale0`） |

### 2. 3x-ui 安装与面板绑定

- 非交互安装：`XUI_NONINTERACTIVE=1`，`XUI_SSL_MODE=none`（面板仅 TS HTTP 时可跳过面板证书），`XUI_PANEL_PORT=2095`，SQLite 即可。
- 凭据只落服务器 `/etc/x-ui/install-result.env`（600），**不入库**。
- 安装后：`x-ui setting -listenIP <tailscale-ipv4>`，确认 `ss` 上 `2095` 仅 TS、公网 `2095` 不通。
- **订阅关闭**（用户不用订阅时）：`subEnable=false`，`subListen=127.0.0.1`（或干脆不监听）；与 cyp 的 `subListen=127.0.0.1` 同思路。

### 3. 数据面：一门多用户（S-UI ↔ 3x-ui）

| S-UI | 3x-ui |
| --- | --- |
| 入站管理（一条 REALITY:443） | **入站**（如 `ddy-tizi`） |
| 用户管理（限流/过期） | **客户端**（关联到该入站） |

- **入站**：门的规格——端口、协议、REALITY 私钥/SNI/dest、传输。通常整机 **只维护一条** 主力 VLESS+REALITY `:443`。
- **客户端**：钥匙与额度——UUID、Flow、流量、过期；必须 **关联入站**，否则无可用连接串。
- REALITY 参数对齐现网：`assets-xbxweb.xbox.com` / `:443`，`fingerprint=chrome`；**密钥本机新生成，禁止复制其它节点**。
- VLESS+REALITY 客户端 **Flow 必须为 `xtls-rprx-vision`**。Flow 为空时面板可生成链接，但实测无法正常代理。

### 4. 分享链接固定域名（避免手改 IP）

3x-ui 新建入站默认 `shareAddrStrategy=node`（无远程 node 时常落成 listen/访问 host，易变成 **Tailscale IP** 或公网 IP）。

对每个入站（或跑修复脚本）：

- `shareAddrStrategy=custom`
- `shareAddr=ddy-tizi.skysms.xyz`（DNS A 记录指向节点公网 IP）
- 可选：Hosts 组绑定同一域名到全部 inboundIds；`webDomain`/`subDomain` 作 public host 兜底

本机脚本（创建/导入入站后一键对齐）：

```bash
ssh tizi-ddy '/root/bin/xui-set-share-domain.sh'
```

### 5. 如何复制连接串（最简路径）

不要依赖「客户端列表上的二维码」——无 **subId** 时会报「无法生成共享链接」（订阅体系）；订阅关闭时更常见。

**推荐：**

1. **客户端** → 点该行 **ⓘ 信息**
2. 底部 **复制链接**（或同排二维码）
3. 前提：已关联入站、Flow 正确、入站 share 已是域名

备选：入站行菜单 **导出链接** / 通用操作 **导出链接**（批量）。

### 6. 验收清单

- `sysctl`：`bbr` + `fq`
- `ss`：`*:443` 为 xray；面板仅 `TS:2095`；无意外公网 `2095`/`2096`
- 公网 `:443` 通；`:2095`/`:2096` 不通
- 分享串 `@` 后为域名而非裸 IP/TS IP
- 测试客户端实测可代理（Flow=`xtls-rprx-vision`）

## Why This Matters

- **暴露面错误**（面板绑公网、订阅乱开）会把管理面暴露给扫描；与 cyp 对齐可降低习惯性误配。
- **share 默认 host** 导致每条链接手改域名，扩用户时易错且难审计。
- **入站/客户端混淆** 时会出现「有客户端无关联入站」「有二维码无直连串」；用 S-UI 心智映射后操作路径清晰。
- **Flow 漏配** 是 REALITY 上「链接有了但连不上」的高频原因，与面板 UI 默认值有关，必须写进检查表。

## When to Apply

- 新建或重装 **3x-ui** 代理节点，并对齐现有 `tizi*` 族运维约定
- 从 S-UI 心智迁移到 3x-ui 日常加人、复制链接、限流
- 分享域名变更（如 `*.skysms.xyz`）后批量修正 shareAddr / Hosts

不适用：S-UI 节点本身（用面板 External/addrs）；非代理业务机。

## Examples

### 分享 host 错误 vs 正确

```text
# 默认/错误（经 TS 打开面板时常见）
vless://...@100.75.133.13:443?...

# custom shareAddr 后
vless://...@ddy-tizi.skysms.xyz:443?flow=xtls-rprx-vision&security=reality&sni=assets-xbxweb.xbox.com&...
```

### 加人最小步骤

1. 客户端添加 → 关联入站 `ddy-tizi` → Flow=`xtls-rprx-vision` → 设流量
2. ⓘ → 复制链接
3. 确认串内 host 为 `ddy-tizi.skysms.xyz`

### 与 cyp 对照（运维形态同、栈不同）

| | tizi-cyp | tizi-ddy |
| --- | --- | --- |
| OS | AlmaLinux | Debian 13 |
| 面板 | S-UI / sing-box | 3x-ui / Xray |
| 防火墙 | firewalld | ufw |
| 数据面 | VLESS+REALITY :443 | 同左（密钥独立） |
| 面板 | 仅 Tailscale :2095 | 同左 |
| 订阅 | 本机/不暴露 | 关闭 |

## Related

- 运维时间线：`docs/operations/tizi-ddy.md`
- 参考部署计划（S-UI 节点）：`docs/plans/2026-07-09-001-ops-tizi-cyp-proxy-deploy-plan.md`
- cyp 时间线：`docs/operations/tizi-cyp.md`（REALITY SNI/dest、面板绑 TS）
- 主节点 External 域名：`docs/operations/tizi.md`（`tz.skysms.xyz`）

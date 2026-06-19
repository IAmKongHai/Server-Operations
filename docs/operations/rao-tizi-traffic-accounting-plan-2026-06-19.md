# rao-tizi 流量统计核对与监控方案（规划，2026-06-19）

> 状态：**规划中，未执行任何安装/改动**。今天仅产出本计划，后续择期实施。
> 服务器：`rao-tizi`（Rocky Linux 9，2 vCPU / 1GB RAM）。`tizi` 的备用代理，2026-05-20 起接管 `litellm-us.konghai.me` 的 nginx 反向代理透传。
> 姊妹文档：`tizi-traffic-accounting-plan-2026-06-19.md`（方案设计与原理详见该文，本文只记 rao-tizi 的实测数据与差异）。

## 一、背景

`rao-tizi` 与 `tizi` 角色相同（S-UI 代理 + nginx LLM 透传），需要一套与 `tizi` 一致的流量统计与告警，用于：和 VPS 提供商面板对账、看清流量构成、月用量触达阈值时 Telegram 主动通知。

**与 tizi 的关键差异**：`rao-tizi` 是 LLM 透传流量的**承接方**（2026-05-20 DNS 从 tizi 切过来），因此其 nginx 透传（8443/80）流量占比预计明显高于 tizi，监控对它更有意义。

## 二、调查结论（2026-06-19 实测）

### 1. 内核网卡计数器（自 2026-06-10 15:44 开机起累计，约 9 天）

```
eth0  RX(接收/下行) = 86.3 GB
eth0  TX(发送/上行) = 86.2 GB
eth0  合计          = 172.5 GB（约 9 天）
```

收发几乎对称（86.3 / 86.2），符合「代理 + 透传中转」双向流量的特征。数据源：`/proc/net/dev` 的 eth0 行。

> 注：本文暂无 rao-tizi 的 VPS 提供商面板用量数值（tizi 那份有 882GB 面板数作对比，rao-tizi 待用户补充）。实施 vnstat 后即可与面板逐月对账。

### 2. 流量构成预期（与 tizi 同理）

- **代理双向放大**：S-UI 只记「用户业务量一份」，网卡上约为其 2 倍（收发各一遍）。
- **S-UI 不统计 nginx 透传**：8443 反代 OpenAI/Anthropic/Groq/xAI/Cerebras 等，走 nginx 不进 S-UI。rao-tizi 作为透传承接方，这部分占比更大。
- 协议封装开销（+3~10%）、系统流量（dnf/tailscale/SSH/DNS）、统计周期不对齐。

### 3. 当前对外端口画像（流量归属）

| 端口 | 进程 | 用途 | 流量量级 |
| --- | --- | --- | --- |
| `443` | `sui` | 代理数据面 | **主力** |
| `8443` | `nginx` | LLM 供应商 HTTPS 透传（litellm-us 承接方） | **较大**（高于 tizi） |
| `80` | `nginx` | HTTP | 少量 |
| `2095` | `sui` | 管理面板（已限 tailscale，见 rao-tizi.md 2026-06-19） | 极少 |
| `22` | `sshd` | SSH 运维 | 极少 |
| `tailscale0` | `tailscaled` | tailscale 内网 | 极少 |

### 4. 资源余量

2 vCPU / 1GB RAM，约 618MB available。未装 vnstat；有 `epel-cisco-openh264`（需确认完整 EPEL 源）。三组件均近零开销，余量充足。

## 三、监控方案规划（vnstat + nftables + Telegram bot）

方案设计、原理、性能/安全约束与 `tizi` 完全一致，**详见 `tizi-traffic-accounting-plan-2026-06-19.md` 第三节**，此处只列要点与 rao-tizi 特化项：

- **组件 1 vnstat**：读 `/proc/net/dev` 计数器，网卡级日/月精确账单，零抓包开销，与 VPS 面板对账。
- **组件 2 nftables 计数器**：按端口分类。rao-tizi **重点关注 8443+80（透传）vs 443（代理）的占比**，验证透传承接量。新增规则前先读出并备份现有 nft ruleset，避免与 firewalld/sui 链冲突。
- **组件 3 Telegram bot**：cron 定时读 vnstat 当月用量，多级阈值（建议 700/800/950GB，按 rao-tizi 套餐上限调整）触发 Telegram 推送；token/chat id 存本地 600 文件，勿入仓库；加「已告警去重」。

> 提示：tizi 与 rao-tizi 可共用同一套脚本与同一个 Telegram bot，消息体里标明来源主机名区分两台即可。

## 四、待实施清单

1. [ ] 补充 rao-tizi 的 VPS 提供商面板月用量数值，确定套餐流量上限
2. [ ] 确认/启用完整 EPEL 源，安装并 enable vnstat，初始化 eth0 数据库
3. [ ] 跑 1~2 天后用 vnstat 月度数据与 VPS 面板对账
4. [ ] 读出并备份现有 nft ruleset，新增 443 / 8443+80 / 其余 的 counter
5. [ ] 复用 tizi 的 Telegram 告警脚本（消息标注主机名），配置 rao-tizi 阈值
6. [ ] 验证告警链路（手动触发测试推送）
7. [ ] 完成后在 `docs/operations/rao-tizi.md` 追加实施记录

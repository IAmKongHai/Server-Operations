# tizi-cyp 代理节点部署计划

> 状态：**规划中**（SSH 密钥/禁密码、Tailscale、BBR 已就绪；S-UI / firewalld / vnstat 未装）  
> 计划建立：2026-07-09  
> 基线复核：2026-07-10（只读采集 `tizi` + `tizi-cyp`）  
> 目标服务器：`tizi-cyp`（`89.208.242.203`，AlmaLinux 9.7）  
> 参考模板：`tizi`（主代理）+ `rao-tizi`（备用代理）上已验证的 S-UI 运维形态

## Summary

将 `tizi-cyp` 建成与 `tizi` **同构的纯代理节点**：S-UI（sing-box）数据面监听 `443`，管理面板仅经 Tailscale 访问，公网只暴露 `22` + `443`，并用 `vnstat` 做网卡级流量对账。

**不**把 `tizi` 上的 Nginx LLM 反代（`80`/`8443`）迁到本机——该职责已在 `rao-tizi`；新节点定位为**扩容/分流代理**，不是 litellm 入口。

---

## 1. 现状对照（2026-07-10 只读复核）

| 项 | `tizi`（参考） | `tizi-cyp`（当前） | 目标 |
| --- | --- | --- | --- |
| SSH 别名 | `ssh tizi` | `ssh tizi-cyp`（已通） | 保持 |
| 公网 IP | `74.211.103.83` | `89.208.242.203` | 保持 |
| OS | Rocky Linux 9.7 | AlmaLinux 9.7 | 保持（同属 EL9） |
| 规格 | 2 vCPU / 1 GiB / 20 G 盘 | 3 vCPU / 2 GiB / 38 G 盘 | 规格更宽裕，直接对齐软件栈 |
| 主机名 | `unique-idea-1.localdomain` | `cute-fiber-1.localdomain` | 建议改为 `tizi-cyp`（可选） |
| 时区 | `Asia/Shanghai`（CST） | **UTC** | 改为 `Asia/Shanghai` |
| SSH 密码登录 | 密钥为主 | **已禁用**（`PasswordAuthentication no`） | 保持 |
| 公钥 | `id_ed25519` | 已装 `konghai@konghai.me` | 保持 |
| BBR | `bbr` + `fq`（sysctl 固化） | **已固化**（`/etc/sysctl.d/` 多处含 bbr/fq） | **已完成**，无需再改 |
| firewalld | active；public 开 `ssh` + `80/443/8443`；`tailscale0` → trusted | **未安装**；当前 iptables 仅 Tailscale 链，INPUT policy ACCEPT | 安装并启用；public 仅 `ssh` + `443/tcp`；`tailscale0` → trusted |
| S-UI | `1.4.1` + Sing-Box `v1.13.4`，`/usr/local/s-ui/sui` | 未装 | 安装同系并 enable |
| 数据面 | `*:443`（`sui`，inbound tag `vless-reality`，TLS 名 `REALITY`） | 无 | `*:443` VLESS + REALITY（**新密钥，不复制 tizi**） |
| 面板 | `100.90.28.83:2095`，path `/app/` | 无 | `100.88.178.78:2095`，path `/app/` |
| 订阅 | `127.0.0.1:2096` path `/sub/` | 无 | 同 tizi：默认本机；是否暴露见开放问题 |
| nginx / certbot | 有（LLM 透传残余） | 无 | **本期不装** |
| Tailscale | 节点名 `tizi`，`100.90.28.83`（v1.98.4） | **已装并 online**：节点名 `tizi-cyp`，`100.88.178.78`（v1.98.8，MagicDNS `tizi-cyp.taila93443.ts.net`） | **已完成**；装完 S-UI 后只绑定面板 |
| vnstat | 2.9 active（EPEL） | 无；**无 epel-release** | 装 EPEL + vnstat，监控 `eth0` |
| 用户流量重置 cron | 每月 29 日 23:59 | 无 | 按**本机服务商重置日**再配 |
| 客户端数 | `clients` = 25 | — | 新库 + 手工建用户，**不**复制 `s-ui.db` |

### 角色分工（三台代理节点）

| 节点 | 角色 | 数据面 | LLM Nginx |
| --- | --- | --- | --- |
| `tizi` | 主代理 | `443` S-UI | 残留 `80/8443`（DNS 已切走） |
| `rao-tizi` | 备用代理 + litellm 入口 | `443` S-UI | `80/8443` 正式承载 `litellm-us.konghai.me` |
| `tizi-cyp` | **扩容/分流代理**（本期） | `443` S-UI | **不装** |

### `tizi` 关键运行画像（要对齐的核心）

```text
公网:
  :22   sshd
  :443  sui          ← 代理数据面（主力流量）
  :80   nginx        ← 本期不迁到 tizi-cyp
  :8443 nginx        ← 本期不迁到 tizi-cyp

Tailscale:
  100.90.28.83:2095  sui  ← 面板 path=/app/

本机:
  127.0.0.1:2096 sui ← 订阅 path=/sub/
```

S-UI 设置摘要（`tizi` 实测）：

| 项 | 值 |
| --- | --- |
| 版本 | S-UI Panel `1.4.1` / Sing-Box `v1.13.4` |
| Panel | port `2095` / path `/app/` / listen = Tailscale IP |
| Sub | port `2096` / path `/sub/` / listen = `127.0.0.1` |
| `timeLocation` | `Asia/Tehran`（面板统计时区；系统时区仍是上海） |
| Inbound | tag `vless-reality`，type `vless`，`listen=::`，`listen_port=443` |
| TLS 配置名 | `REALITY` |
| 安装路径 | `/usr/local/s-ui/`，单元 `/etc/systemd/system/s-ui.service` |
| 安装入口 | 官方脚本 `bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/main/install.sh)` |

### `tizi-cyp` 已完成（不必重做）

见 `docs/operations/tizi-cyp.md` + 2026-07-10 复核：

1. 本机 `~/.ssh/config` → `Host tizi-cyp`
2. 公钥写入 `/root/.ssh/authorized_keys`
3. `PasswordAuthentication no` + 备份 `sshd_config.bak.20260709`
4. **Tailscale 已安装并登录**（2026-07-09 16:37 UTC 装包）：节点名 `tizi-cyp`，IPv4 `100.88.178.78`
5. **BBR + fq 已写入 sysctl.d**（运行时与持久配置均已是 bbr/fq）

---

## 2. 目标形态

```text
[客户端 Shadowrocket/Clash 等]
        │  VLESS+REALITY
        ▼
 tizi-cyp 公网 89.208.242.203:443  (sui)
        │
        ▼
     目标站点 / 直出

[本机 / 其它 tailnet 设备]
        │  HTTP
        ▼
 tizi-cyp tailscale 100.88.178.78:2095/app/  (sui 面板)
```

**成功标准：**

1. `ssh tizi-cyp` 仍仅密钥可用。  
2. 公网 `443` 有 `sui` 监听；公网探测 `2095` 不通。  
3. 本机经 Tailscale 打开 `http://100.88.178.78:2095/app/` 可进面板。  
4. 至少 1 个测试客户端能连通并有上下行统计。  
5. `vnstat` 能对 `eth0` 出日/月统计。  
6. 变更写入 `docs/operations/tizi-cyp.md` 并提交。

---

## 3. 范围

### 本期做（P0）

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| A. 系统基线 | 时区、主机名（可选）、基础包（`curl`/`sqlite`/`firewalld`/`epel`） | BBR 已完成；其余待做 |
| B. 防火墙 | 启用 firewalld；public 放行 `ssh` + `443/tcp`；`tailscale0` → trusted | 待做 |
| C. S-UI | 官方脚本安装；改管理员密码；建 VLESS+REALITY inbound（`:443`） | 待做 |
| D. 面板绑定 | 将 `webListen` 绑到 `100.88.178.78`；公网不可达 2095 | Tailscale 已就绪；绑定待 S-UI 后做 |
| E. 流量观测 | 装 EPEL + vnstat | 待做 |
| F. 运维固化 | 备份约定、可选月重置 cron、文档 | 待做 |

### 本期不做（明确排除）

- Nginx / certbot / `litellm-us` 反代（保留在 `rao-tizi`）  
- 从 `tizi` **整库复制** `s-ui.db`（共享 REALITY 密钥与用户 UUID，多节点易踩坑）  
- Telegram 流量告警、nftables 分端口计数（`tizi` 流量方案 P2，可后做）  
- 关闭 root 登录、改 SSH 端口、fail2ban  
- 把现网用户批量迁到新节点（需你指定迁移名单与窗口）

### 可选后续（P1）

- 为家庭/办公室路由器签发新节点配置，做分流或主备  
- 对齐服务商流量重置日的 S-UI `clients` 月清零 cron  
- 与 `tizi` 流量方案同构的 Telegram 阈值告警  
- 「同一客户端多服务器负载」：共享 UUID / 独立 REALITY 的多节点方案（另开）

---

## 4. 关键决策

| 决策 | 选择 | 理由 |
| --- | --- | --- |
| 面板栈 | **S-UI**（与 tizi 同款 1.4.x） | 运维经验、脚本、cron、库表路径全部可复用 |
| 协议 | **VLESS + REALITY @ 443** | tizi 现网唯一 inbound 即此形态；443 伪装成本低 |
| 面板暴露 | **仅 Tailscale** | 已在 tizi/rao-tizi 验证；避免公网扫面板 |
| 防火墙 | **firewalld** | 与 tizi 一致；本机可审计；`tailscale0` 进 trusted 是已知必要步骤 |
| LLM/Nginx | **不装** | 职责在 rao-tizi；避免 80/443 语义混乱（443 给代理） |
| 用户数据 | **新库 + 手工建用户** | 干净密钥；避免误覆盖 tizi；迁移可分批 |
| 系统时区 | **Asia/Shanghai** | 运维日志与 cron 与 tizi 一致 |
| S-UI 面板时区 | 见开放问题（tizi 现为 `Asia/Tehran`） | 与系统时区可分离，需你定 |

---

## 5. 分阶段实施（执行时按序、逐步确认）

> 生产守则：每步先备份、再改、可回滚；**危险动作（重启、改 firewall、装服务）执行前在对话中再次确认**。  
> 下列为计划步骤，**不是已执行记录**。

### 阶段 A — 系统基线

1. 再记一次基线快照（装包前）：`uname -a`、`free -h`、`df -h`、`ss -lntup`、`ip a`、`tailscale ip -4`。  
2. 时区：`timedatectl set-timezone Asia/Shanghai`。  
3. （可选）主机名：`hostnamectl set-hostname tizi-cyp`。  
   - 注意：Tailscale 的 **MagicDNS 名已是 `tizi-cyp`**，改系统主机名只影响本机 prompt/日志，不强制。  
4. BBR：**跳过**（已固化）。  
5. 安装基础工具：
   ```bash
   dnf install -y firewalld sqlite curl vim
   dnf install -y epel-release   # 后续 vnstat 用
   ```
6. 验证：SSH 不断；`timedatectl` 显示 `Asia/Shanghai`。

**回滚：** 时区改回 `UTC`；不需要卸载已有 BBR。

### 阶段 B — firewalld

1. `systemctl enable --now firewalld`。  
2. public zone：确保 `ssh` 服务放行；增加 `443/tcp`：
   ```bash
   firewall-cmd --permanent --add-service=ssh
   firewall-cmd --permanent --add-port=443/tcp
   ```
3. **不要**默认开 80/8443（本期无 nginx）。  
4. 将 `tailscale0` 划入 trusted（可与面板绑定同一步，也可先做）：
   ```bash
   firewall-cmd --permanent --zone=trusted --add-interface=tailscale0
   firewall-cmd --reload
   ```
5. 确认默认 zone 绑定 `eth0`：`firewall-cmd --get-active-zones`。  
6. 验证：已有 SSH 会话不断；本机再开一条新 `ssh tizi-cyp` 成功。

**回滚：** 紧急时 `systemctl disable --now firewalld`（仅恢复连通用；正式环境应修规则而非长期关墙）。

**风险：** 规则写错可能锁 SSH。执行时：

- 保持一个已建立的 SSH 会话  
- 改 permanent 后 `--list-all` 复核再 `reload`  
- 云商家救援控制台作后手  

**说明：** 当前 INPUT policy 是 ACCEPT，装 firewalld 后会变成「默认拒绝 + 白名单」；这是预期收紧，不是故障。

### 阶段 C — 安装 S-UI

1. 官方安装脚本（与 tizi 的 `s-ui.sh` 同源）：
   ```bash
   bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/main/install.sh)
   ```
2. 安装后确认：
   - `systemctl status s-ui`  
   - 二进制 `/usr/local/s-ui/sui`  
   - 默认面板 `2095` / `/app/`（初始账号**只记密码管理器，不入库**）  
3. 立即重置管理员密码：`/usr/local/s-ui/sui admin`（或面板内改密）。  
4. **临时访问**（面板尚未绑 Tailscale 前）：
   - **优先**：`ssh -L 2095:127.0.0.1:2095 tizi-cyp` → 浏览器 `http://127.0.0.1:2095/app/`  
   - 注意：本机 `tizi` 的 SSH 配置已 LocalForward `2095`，若同时连 tizi 隧道会冲突；要么临时关 tizi 隧道，要么本机改用其它本地端口如 `2195`：  
     `ssh -L 2195:127.0.0.1:2095 tizi-cyp` → `http://127.0.0.1:2195/app/`  
   - **禁止**把面板绑到 `0.0.0.0` 暴露公网。  
5. 在面板创建 **Inbound**：
   - 协议：VLESS  
   - 端口：`443`  
   - 安全：REALITY（**生成新的** shortId / publicKey / privateKey / serverNames / dest）  
   - 标签建议：`vless-reality`（与 tizi 命名一致）  
6. 创建至少一个 **测试 client**，导出链接/二维码。  
7. 验证：`ss -lntp | grep -E '443|2095'`；客户端可连。

**回滚：** `systemctl disable --now s-ui`；备份 `/usr/local/s-ui/db/` 后再决定是否卸载。

**注意：** 安装脚本依赖 GitHub；若出口受限，改用 release 二进制手工放到 `/usr/local/s-ui/`。

### 阶段 D — 面板绑定 Tailscale（Tailscale 本体已完成）

对齐 `tizi` / `rao-tizi` 2026-06-19 操作；TS IP 已固定为 **`100.88.178.78`**：

1. 备份 DB：
   ```bash
   cp -a /usr/local/s-ui/db/s-ui.db /usr/local/s-ui/db/s-ui.db.before-tailscale-panel-YYYYMMDD
   ```
2. 停止 s-ui → 改 `webListen` → 启动：
   ```bash
   systemctl stop s-ui
   sqlite3 /usr/local/s-ui/db/s-ui.db \
     "UPDATE settings SET value='100.88.178.78' WHERE key='webListen';"
   systemctl start s-ui
   ```
3. 若阶段 B 未做 trusted：`firewall-cmd --permanent --zone=trusted --add-interface=tailscale0 && firewall-cmd --reload`。  
   - **已知坑**（`docs/operations/tizi.md`）：只改 `webListen` 不够；`tailscale0` 无 zone 时入站走 public，2095 被拒。  
4. 浏览器：`http://100.88.178.78:2095/app/`（path 必须 `/app/`）。  
5. 公网验证：`89.208.242.203:2095` 应 connection refused / 超时。  
6. 订阅保持 `127.0.0.1:2096`，除非你明确要求暴露。

**回滚：**

```bash
sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE settings SET value='127.0.0.1' WHERE key='webListen';"
systemctl restart s-ui
```

### 阶段 E — vnstat

对齐 `tizi` 2026-06-19：

1. `dnf install -y epel-release`（若 A 未装）  
2. `dnf --enablerepo=epel install -y vnstat`  
3. `systemctl enable --now vnstat`  
4. `vnstat --iflist`（期望 `eth0`、`tailscale0`）  
5. 口径：`vnstat` 的 `rx+tx` ≈ S-UI 用户业务流量 ×2（代理双向），详见 `docs/operations/tizi-traffic-accounting-plan-2026-06-19.md`。

**回滚：** `systemctl disable --now vnstat && dnf remove -y vnstat`。

### 阶段 F — 运维固化与文档

1. 远端备份目录约定：`/root/backup/tizi-cyp-YYYYMMDD/`（sshd、firewalld、s-ui.db 快照）。  
2. **用户流量月重置 cron**（可选，依赖服务商重置日）：
   ```cron
   59 23 <DAY> * * /usr/bin/sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE clients SET up = 0, down = 0;"
   ```
   - `tizi` = 29 日；`rao-tizi` = 11 日 —— **tizi-cyp 必须查本机套餐后再写**。  
3. 每阶段完成后追加 `docs/operations/tizi-cyp.md` 并 `git commit`。  
4. SSH：面板推荐直连 Tailscale，不强制 LocalForward；若加隧道，避免与 `tizi:2095`、`rao-tizi:2096` 冲突。

---

## 6. 验证清单（Definition of Done）

| # | 检查项 | 期望 |
| --- | --- | --- |
| 1 | `ssh -o BatchMode=yes tizi-cyp true` | 成功 |
| 2 | 密码 SSH | 仍拒绝 |
| 3 | `systemctl is-active s-ui firewalld tailscaled vnstat` | 均为 active |
| 4 | `ss -lntp` | `*:443` → sui；`100.88.178.78:2095` → sui；无公网 2095 |
| 5 | `firewall-cmd --list-all` | public 含 ssh + 443/tcp |
| 6 | `firewall-cmd --get-zone-of-interface=tailscale0` | `trusted` |
| 7 | 浏览器 | `http://100.88.178.78:2095/app/` 可登录 |
| 8 | 客户端 | 测试用户可上网；面板 stats 有增量 |
| 9 | `vnstat -d` / `--iflist` | eth0 已登记 |
| 10 | 文档 | `docs/operations/tizi-cyp.md` 已记各阶段 |

---

## 7. 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| firewalld 误配锁死 SSH | 无法登录 | 保持既有会话；先 list 再 reload；云控制台救援 |
| 面板误绑 `0.0.0.0:2095` | 公网暴露管理面 | 装完立刻改 listen；公网 `nc`/`curl` 复核 |
| REALITY 参数/SNI 不当 | 连不上或易被干扰 | 选用常见 dest/serverNames；先 1 个测试客户端 |
| 与 tizi 用户同名不同 UUID | 客户端配置混乱 | 命名加后缀（如 `xxx-cyp`）或分组 `tizi-cyp` |
| 流量超套餐 | VPS 限速/关机 | 尽早 vnstat；弄清额度与重置日后再放量 |
| 安装脚本依赖 GitHub | 装不上 | 手工下 release；或经已有代理出口执行 |
| 系统时区 vs S-UI `timeLocation` | 面板统计日界困惑 | 系统用上海；S-UI 时区在面板统一设定并写文档 |
| 本机 SSH LocalForward 2095 与 tizi 冲突 | 临时看面板失败 | 用 `2195` 等其它本地端口，或优先用 Tailscale 直连 |

---

## 8. 开放问题（执行前需你确认）

1. **VPS 套餐**：月流量额度、重置日、是否限速/关机？（决定 cron 日与告警阈值）  
2. **S-UI 面板时区**：跟系统用 `Asia/Shanghai`，还是照搬 tizi 的 `Asia/Tehran`？  
3. **首批用户**：只建测试号，还是同步迁哪些现网用户（名单）？  
4. **主机名**：系统 hostname 是否改为 `tizi-cyp`？（MagicDNS 已是 tizi-cyp）  
5. **订阅**：是否需要公网/Tailscale 可达的 sub 端口，还是继续仅本机 2096？  
6. **REALITY dest/SNI**：是否有偏好域名（建议与 tizi **不同**，避免特征撞车）？  
7. **执行节奏**：是否按「A+B+C → 测通客户端 → D 收口面板 → E/F」分多次确认执行？

---

## 9. 建议执行顺序

```text
A 基线(时区/基础包)
  → B firewalld(+ tailscale0 trusted)
  → C S-UI + 测试客户端（SSH 隧道临时看面板）
  → D webListen=100.88.178.78（面板收口）
  → E vnstat
  → F 文档/cron
```

**推荐首轮执行窗口：** A + B + C（能出可测节点）→ 确认客户端可用后再 D → 最后 E/F。

每完成一阶段：在 `docs/operations/tizi-cyp.md` 追加一条（时间 / 原因 / 影响 / 备份 / 回滚 / 验证），并 `git commit`。

---

## 10. 参考路径

| 路径 | 用途 |
| --- | --- |
| `docs/operations/tizi.md` | 面板改 Tailscale、流量对账、月重置 cron |
| `docs/operations/rao-tizi.md` | 同构代理 + Tailscale 面板 + litellm 职责 |
| `docs/operations/tizi-traffic-accounting-plan-2026-06-19.md` | vnstat 口径与后续监控 |
| `docs/operations/tizi-cyp.md` | 本机节点时间线 |
| `AGENTS.md` | 服务器别名清单（`tizi-cyp` 已登记） |

---

## 11. Assumptions（规划时默认）

- 节点用途为**个人/小范围代理扩容**，不对外售卖面板。  
- 公网安全组若由商家面板控制，需同步放行 `443/tcp`（及已有 `22`）；本计划以 OS 内 firewalld 为准并双检。  
- 不自动迁移 tizi 用户；上线后由你指定迁移节奏。  
- 不在仓库写入面板账号、REALITY 私钥、Tailscale auth key、订阅 token。  
- Tailscale 已由先前操作完成并 online，本计划只消费其 IP `100.88.178.78`，不再重装。

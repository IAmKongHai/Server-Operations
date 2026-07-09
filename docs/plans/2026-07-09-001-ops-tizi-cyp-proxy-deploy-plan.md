# tizi-cyp 代理节点部署计划

> 状态：**规划中，未执行安装/改动（SSH 与密码策略已在先前运维完成）**  
> 日期：2026-07-09  
> 目标服务器：`tizi-cyp`（`89.208.242.203`）  
> 参考模板：`tizi`（主代理）+ `rao-tizi`（备用代理）上已验证的 S-UI 运维形态

## Summary

将 `tizi-cyp` 建成与 `tizi` **同构的纯代理节点**：S-UI（sing-box）数据面监听 `443`，管理面板仅经 Tailscale 访问，公网只暴露 `22` + `443`，并用 `vnstat` 做网卡级流量对账。

**不**把 `tizi` 上的 Nginx LLM 反代（`80`/`8443`）迁到本机——该职责已在 `rao-tizi`；新节点定位为**扩容/分流代理**，不是 litellm 入口。

---

## 1. 现状对照（2026-07-09 只读采集）

| 项 | `tizi`（参考） | `tizi-cyp`（当前） | 目标 |
| --- | --- | --- | --- |
| SSH 别名 | `ssh tizi` | `ssh tizi-cyp`（已通） | 保持 |
| 公网 IP | `74.211.103.83` | `89.208.242.203` | 保持 |
| OS | Rocky Linux 9.7 | AlmaLinux 9.7 | 保持（同属 EL9） |
| 规格 | 约 2 vCPU / 1 GiB / 20 G 盘 | 3 vCPU / 2 GiB / 38 G 盘 | 规格更宽裕，可直接对齐软件栈 |
| 主机名 | `unique-idea-1.localdomain` | `cute-fiber-1.localdomain` | 建议改为 `tizi-cyp`（可选） |
| 时区 | `Asia/Shanghai` | `UTC` | 改为 `Asia/Shanghai`（与 tizi 运维日志一致） |
| SSH 密码登录 | 未在本计划中改 | **已禁用**（`PasswordAuthentication no`） | 保持 |
| 公钥 | `id_ed25519` | 已装 `konghai@konghai.me` | 保持 |
| BBR | `bbr` + `fq`（sysctl 固化） | 运行时已是 `bbr` + `fq` | 写进 `/etc/sysctl.d/` 固化 |
| firewalld | 运行；public 开 `ssh/80/443/8443`；`tailscale0` → trusted | **未安装/未运行** | 安装并启用，public 仅 `ssh` + `443/tcp` |
| S-UI | `1.4.1`，`/usr/local/s-ui/sui`，systemd `s-ui` | 未装 | 安装并 enable |
| 数据面 | `*:443`（`sui`，VLESS + REALITY） | 无 | `*:443` VLESS + REALITY |
| 面板 | Tailscale `100.90.28.83:2095`，path `/app/` | 无 | Tailscale IP:2095，path `/app/` |
| 订阅 | `127.0.0.1:2096`（本机） | 无 | 同 tizi：默认本机；需要再议是否暴露 |
| nginx / certbot | 有（LLM 透传残余） | 无 | **本期不装** |
| Tailscale | 节点名 `tizi`，`100.90.28.83` | 无 | 安装并登录，节点名 `tizi-cyp` |
| vnstat | 已装并 active | 无 | 安装，监控 `eth0`（+ tailscale0） |
| 用户流量重置 cron | 每月 29 日 23:59（对齐服务商 30 日周期） | 无 | 装好后按**本机服务商重置日**配置（见开放问题） |
| 客户端数 | S-UI `clients` 约 25 | — | 新建节点，**不**直接复制 `tizi` 的 `s-ui.db` |

### `tizi` 关键运行画像（要对齐的核心）

```text
公网:
  :22   sshd
  :443  sui          ← 代理数据面（主力流量）
  :80   nginx        ← 本期不迁到 tizi-cyp
  :8443 nginx        ← 本期不迁到 tizi-cyp

Tailscale:
  <ts-ip>:2095  sui  ← 面板（/app/）

本机:
  127.0.0.1:2096 sui ← 订阅（默认不对外）
```

S-UI 设置摘要（`tizi`）：

- Panel：`2095` / path `/app/` / listen = Tailscale IP  
- Sub：`2096` / path `/sub/` / listen = `127.0.0.1`  
- Inbound：`vless-reality`（tag），TLS 配置名 `REALITY`  
- 安装路径：`/usr/local/s-ui/`，单元：`/etc/systemd/system/s-ui.service`  
- 安装入口：官方脚本 `bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/main/install.sh)`（`s-ui.sh` 内同此）

### `tizi-cyp` 已完成（不必重做）

见 `docs/operations/tizi-cyp.md`：

1. 本机 `~/.ssh/config` → `Host tizi-cyp`  
2. 公钥写入 `/root/.ssh/authorized_keys`  
3. `PasswordAuthentication no` + 备份 `sshd_config.bak.20260709`  

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
 tizi-cyp tailscale IP:2095/app/  (sui 面板)
```

**成功标准：**

1. `ssh tizi-cyp` 仍仅密钥可用。  
2. 公网 `443` 有 `sui` 监听；公网探测 `2095` 不通。  
3. 本机经 Tailscale 打开 `http://<ts-ip>:2095/app/` 可进面板。  
4. 至少 1 个测试客户端能连通并有上下行统计。  
5. `vnstat` 能对 `eth0` 出日/月统计。  
6. 变更写入 `docs/operations/tizi-cyp.md` 并提交。

---

## 3. 范围

### 本期做（P0）

| 阶段 | 内容 |
| --- | --- |
| A. 系统基线 | 时区、主机名（可选）、BBR sysctl 固化、基础包（`curl`/`sqlite3`/`firewalld`/`epel` 等） |
| B. 防火墙 | 启用 firewalld；public 放行 `ssh` + `443/tcp`；后续 `tailscale0` → trusted |
| C. S-UI | 官方脚本安装；改管理员密码；建 VLESS+REALITY inbound（`:443`） |
| D. Tailscale | 安装、登录、hostname=`tizi-cyp`；面板 `webListen` 绑 Tailscale IPv4 |
| E. 流量观测 | 装 vnstat，enable；记录与 VPS 面板对账方法 |
| F. 运维固化 | 备份目录约定、可选用户用量月重置 cron、文档 |

### 本期不做（明确排除）

- Nginx / certbot / `litellm-us` 反代（保留在 `rao-tizi`）  
- 从 `tizi` **整库复制** `s-ui.db`（会共享 REALITY 密钥与用户 UUID，多节点易踩坑；若以后要「同订阅多入口」另开方案）  
- Telegram 流量告警、nftables 分端口计数（`tizi` 流量方案里的 P2，可后做）  
- 关闭 root 登录、改 SSH 端口、fail2ban  
- 把现网用户批量迁到新节点（需你指定迁移名单与窗口）

### 可选后续（P1）

- 按需为家庭/办公室路由器签发新节点配置，做分流或主备  
- 对齐服务商流量重置日的 S-UI `clients` 月清零 cron  
- 与 `tizi` 流量方案同构的 Telegram 阈值告警  
- 若需要「同一客户端多服务器负载」：设计共享 UUID / 独立 REALITY 的多节点方案（不在本期）

---

## 4. 关键决策

| 决策 | 选择 | 理由 |
| --- | --- | --- |
| 面板栈 | **S-UI**（与 tizi 同款） | 运维经验、脚本、cron、库表路径全部可复用 |
| 协议 | **VLESS + REALITY @ 443** | tizi 现网唯一 inbound 即此形态；443 伪装成本低 |
| 面板暴露 | **仅 Tailscale** | 已在 tizi/rao-tizi 验证；避免公网扫面板 |
| 防火墙 | **firewalld**（不用仅靠云安全组假设） | 与 tizi 一致；本机可审计；`tailscale0` 进 trusted 是已知必要步骤 |
| LLM/Nginx | **不装** | 流量与职责已在 rao-tizi；避免占 80/443 语义混乱（443 给代理） |
| 用户数据 | **新库 + 手工建用户** | 干净密钥；避免误覆盖 tizi；迁移可分批 |
| 时区 | **Asia/Shanghai** | 运维日志与 cron 与 tizi 一致（S-UI 内部 `timeLocation` 可另设，tizi 现为 `Asia/Tehran`，**面板时区是否照搬见开放问题**） |

---

## 5. 分阶段实施（执行时按序、逐步确认）

> 生产守则：每步先备份、再改、可回滚；**危险动作（重启、改 firewall、装服务）执行前在对话中再次确认**。  
> 下列为计划步骤，不是已执行记录。

### 阶段 A — 系统基线

1. 记录基线：`uname -a`、`free -h`、`df -h`、`ss -lntup`、`ip a`。  
2. 时区：`timedatectl set-timezone Asia/Shanghai`。  
3. （可选）主机名：`hostnamectl set-hostname tizi-cyp`。  
4. 固化 BBR（运行时已是 bbr/fq，写入 drop-in，避免重启丢失）：
   - 例如 `/etc/sysctl.d/99-bbr.conf`：`net.core.default_qdisc=fq`、`net.ipv4.tcp_congestion_control=bbr`  
   - `sysctl --system` 验证。  
5. 安装基础工具：`firewalld`、`sqlite`/`sqlite3`、`curl`、`vim`；需要时启用 EPEL（装 vnstat 用，参考 tizi：`dnf --enablerepo=epel`）。  
6. 验证：SSH 不断；时区已是 CST。

**回滚：** 时区改回 `UTC`；删除 sysctl drop-in 并 `sysctl --system`。

### 阶段 B — firewalld

1. `systemctl enable --now firewalld`。  
2. public zone：确保 `ssh` 服务放行；增加 `443/tcp`；**不要**默认开 80/8443（本期无 nginx）。  
3. 确认默认 zone 绑定 `eth0`。  
4. 验证：本机仍可 `ssh tizi-cyp`；公网 `443` 尚未有进程时 connection refused 可接受。

**回滚：** `systemctl disable --now firewalld`（仅当紧急恢复连通；正式环境应修规则而非长期关墙）。

**风险：** 若 firewalld 规则写错可能锁 SSH。执行时保持一个已建立的 SSH 会话；改 permanent 后 `firewall-cmd --reload` 前先 `--list-all` 复核。

### 阶段 C — 安装 S-UI

1. 使用官方安装脚本（与 tizi 的 `s-ui.sh` 同源）：
   ```bash
   bash <(curl -Ls https://raw.githubusercontent.com/alireza0/s-ui/main/install.sh)
   ```
2. 安装后确认：
   - 单元：`systemctl status s-ui`  
   - 二进制：`/usr/local/s-ui/sui`  
   - 默认面板：`2095` / `/app/`（安装日志会打印初始账号，**只记在密码管理器，不入库**）  
3. 立即重置管理员密码：`/usr/local/s-ui/sui admin`（或面板内改密）。  
4. 临时访问策略（Tailscale 装好前）：
   - **优先**：SSH 本地转发 `ssh -L 2095:127.0.0.1:2095 tizi-cyp`，浏览器 `http://127.0.0.1:2095/app/`  
   - 或短时 `webListen=127.0.0.1` 保持默认，**禁止**把面板绑到 `0.0.0.0` 暴露公网。  
5. 在面板创建 **Inbound**：
   - 协议：VLESS  
   - 端口：`443`  
   - 安全：REALITY（生成新的 shortId / publicKey / privateKey / serverNames / dest）  
   - 标签建议：`vless-reality`（与 tizi 命名一致，便于记忆）  
6. 创建至少一个 **测试 client**，导出链接/二维码。  
7. 验证：`ss -lntp | grep -E '443|2095'`；客户端可连。

**回滚：** `systemctl disable --now s-ui`；保留 `/usr/local/s-ui/db/` 备份后再决定是否卸载。

**注意：** 安装脚本会拉 GitHub；若出口受限，改用 release 二进制手工解压到 `/usr/local/s-ui/`（tizi 上已有目录布局可参考）。

### 阶段 D — Tailscale + 面板绑定

对齐 `tizi` / `rao-tizi` 2026-06-19 操作：

1. 安装 Tailscale（官方 EL9 源或 install 脚本）。  
2. `tailscale up`，节点名建议 `tizi-cyp`；记录 IPv4（例：`100.x.y.z`）。  
3. 备份 DB：`cp -a /usr/local/s-ui/db/s-ui.db /usr/local/s-ui/db/s-ui.db.before-tailscale-panel-YYYYMMDD`。  
4. 停止 s-ui → 将 `settings.webListen` 改为 Tailscale IPv4 → 启动 s-ui  
   （tizi 做法：`sqlite3 ... UPDATE settings SET value="<ts-ip>" WHERE key="webListen";` 或 `sui setting`）。  
5. firewalld：`firewall-cmd --permanent --zone=trusted --add-interface=tailscale0 && firewall-cmd --reload`。  
   - **已知坑**（见 `docs/operations/tizi.md`）：只改 `webListen` 不够；`tailscale0` 若无 zone，入站仍走 public，2095 会被拒。  
6. 本机浏览器：`http://<ts-ip>:2095/app/`（注意 path 必须 `/app/`）。  
7. 公网验证：`2095` 应不可达。  
8. 订阅端口保持 `127.0.0.1:2096`（与 tizi 一致），除非你明确要求订阅链接公网可达。

**回滚：** `webListen` 改回 `127.0.0.1`；`trusted` 去掉 `tailscale0`；必要时 `tailscale down`。

### 阶段 E — vnstat

对齐 `tizi` 2026-06-19：

1. `dnf --enablerepo=epel install -y vnstat`（以实际源名为准）。  
2. `systemctl enable --now vnstat`。  
3. 确认接口：`vnstat --iflist`（期望 `eth0`；有 tailscale 后还有 `tailscale0`）。  
4. 说明：`vnstat` 的 `rx+tx` 约为 S-UI 用户业务流量的 ~2 倍（代理双向），对账方法见 `docs/operations/tizi-traffic-accounting-plan-2026-06-19.md`。

**回滚：** `systemctl disable --now vnstat && dnf remove -y vnstat`。

### 阶段 F — 运维固化与文档

1. 约定远端备份目录：`/root/backup/tizi-cyp-YYYYMMDD/`（sshd、firewalld、s-ui.db 快照）。  
2. **用户流量月重置 cron**（可选，依赖服务商重置日）：  
   ```cron
   59 23 <DAY> * * /usr/bin/sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE clients SET up = 0, down = 0;"
   ```  
   `tizi` 用 29 日；`rao-tizi` 用 11 日——**tizi-cyp 必须查本机套餐后再写**。  
3. 更新：
   - `docs/operations/tizi-cyp.md`（每阶段完成后追加）  
   - 如有长期约定，可在 `AGENTS.md` / `README.md` 补充「代理节点角色」一句（清单已有别名）  
4. 本机 SSH 已具备 `tizi-cyp` 别名，无需再改；若加 LocalForward 面板端口，注意勿与 `tizi:2095`、`rao-tizi:2096` 隧道冲突（tizi-cyp 推荐直连 Tailscale，不强制隧道）。

---

## 6. 验证清单（Definition of Done）

| # | 检查项 | 期望 |
| --- | --- | --- |
| 1 | `ssh -o BatchMode=yes tizi-cyp true` | 成功 |
| 2 | 密码 SSH | 仍拒绝 |
| 3 | `systemctl is-active s-ui firewalld tailscaled vnstat` | 均为 active（tailscale/vnstat 在对应阶段后） |
| 4 | `ss -lntp` | `*:443` → sui；`<ts-ip>:2095` → sui；无公网 2095 |
| 5 | `firewall-cmd --list-all` | public 含 ssh + 443/tcp；trusted 含 tailscale0 |
| 6 | 浏览器 | `http://<ts-ip>:2095/app/` 可登录 |
| 7 | 客户端 | 测试用户可上网；面板 stats 有增量 |
| 8 | `vnstat -d` | eth0 有数据或至少接口已登记 |
| 9 | 文档 | `docs/operations/tizi-cyp.md` 已记各阶段 |

---

## 7. 风险与缓解

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| firewalld 误配锁死 SSH | 无法登录 | 保持既有 SSH 会话；先 runtime 规则再 permanent；云控制台救援端口作后手 |
| 面板误绑 `0.0.0.0:2095` | 公网暴露管理面 | 安装后立刻改 listen；公网 `nc`/`curl` 复核 |
| REALITY 参数/SNI 不当 | 客户端连不上或易被干扰 | 选用常见 dest/serverNames；先测 1 个客户端再批量发配置 |
| 与 tizi 用户同名不同 UUID | 客户端配置混乱 | 命名加后缀（如 `xxx-cyp`）或分组 `tizi-cyp` |
| 流量超套餐 | VPS 限速/关机 | 尽早 vnstat；弄清套餐额度与重置日后再放量 |
| 安装脚本依赖 GitHub | 装不上 | 手工下 release；或经已有代理出口执行 |
| 时区与 S-UI `timeLocation` 不一致 | 面板统计日界困惑 | 系统用上海；S-UI 时区在面板统一设定并在文档写明 |

---

## 8. 开放问题（执行前需你确认）

1. **VPS 套餐**：月流量额度、重置日、是否限速/关机策略？（决定 cron 日与告警阈值）  
2. **S-UI 面板时区**：跟系统用 `Asia/Shanghai`，还是照搬 tizi 的 `Asia/Tehran`？  
3. **首批用户**：只建测试号，还是同步迁哪些现网用户（名单）？  
4. **主机名**：是否改为 `tizi-cyp`？  
5. **订阅**：是否需要公网/Tailscale 可达的 sub 端口，还是继续仅本机 2096？  
6. **REALITY dest/SNI**：是否有偏好域名（与 tizi 保持不同更安全，避免特征撞车）？

---

## 9. 建议执行顺序（一次对话可拆多次）

```text
A 基线 → B 防火墙 → C S-UI+测试客户端 → D Tailscale 收紧面板 → E vnstat → F 文档/cron
```

每完成一阶段：在 `docs/operations/tizi-cyp.md` 追加一条（时间 / 原因 / 影响 / 备份 / 回滚 / 验证），并 `git commit`。

**推荐首轮执行窗口：** 先做 A+B+C（能出测试节点），确认客户端可用后再做 D（面板收口），最后 E/F。

---

## 10. 参考路径

| 路径 | 用途 |
| --- | --- |
| `docs/operations/tizi.md` | 面板改 Tailscale、流量对账、月重置 cron |
| `docs/operations/rao-tizi.md` | 同构代理 + Tailscale 面板 |
| `docs/operations/tizi-traffic-accounting-plan-2026-06-19.md` | vnstat 口径与后续监控 |
| `docs/operations/tizi-cyp.md` | 本机节点时间线（已有 SSH/禁密码） |
| `AGENTS.md` / `README.md` | 服务器别名清单 |

---

## 11. Assumptions（规划时默认）

- 节点用途为**个人/小范围代理扩容**，不对外售卖面板。  
- 公网安全组若由商家面板控制，需同步放行 `443/tcp`（及已有 `22`）；本计划以 OS 内 firewalld 为准并双检。  
- 不自动迁移 tizi 用户；上线后由你指定迁移节奏。  
- 不在仓库写入面板账号、REALITY 私钥、Tailscale auth key、订阅 token。

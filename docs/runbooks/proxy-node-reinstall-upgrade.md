# 代理节点重装 / 升级 runbook（3x-ui + Xray）

> 最后更新：2026-08-09  
> 来源：`tizi-cyp` AlmaLinux+S-UI → Debian 13+3x-ui 整装；对照 `tizi-ddy` 基线与 Shadowrocket/`minClientVer` 踩坑。  
> 相关：`docs/solutions/best-practices/proxy-node-3x-ui-debian-upgrade-2026-08-09.md`、`docs/solutions/tizi-ddy/best-practices/3x-ui-proxy-node-aligned-with-s-ui-2026-07-28.md`、`scripts/verify-tizi-cyp-baseline.sh`

面向后续 **`tizi` / `rao-tizi` 等节点** 升级时复用。默认目标栈：

| 层 | 标准 |
|----|------|
| OS | **Debian 13 (trixie)**（代理场景优先；不必为换面板强行重装） |
| 面板 | **3x-ui + Xray**（协议只走 Xray 时不再选 S-UI/sing-box） |
| 公网 | 仅 **22 + 443/tcp** |
| 面板 | 仅 **当前 Tailscale IPv4:2095** + 随机 **webBasePath** |
| 数据面 | VLESS + REALITY `:443`，flow `xtls-rprx-vision`，**`minClientVer=1.0.0`** |
| 防火墙 | Debian：**ufw**；EL：**firewalld**（规则等价） |
| 其它 | BBR+`fq`；SSH 关密码；不装 Nginx/litellm/Docker（纯代理） |

---

## 路径选型（先选再动）

| 现状 | 建议 |
|------|------|
| 已是 Debian + 要上 3x-ui | **不重装 OS**，卸旧面板 → 装 3x-ui → 迁入站 |
| Alma/旧系统 + 要统一 Debian | 维护窗 **整装 Debian 13**（照 cyp） |
| 已是 3x-ui，只升版本 | 备份 DB → update → **复查 `minClientVer` 与客户端** |
| 仍要 HY2/TUIC 等 sing-box 协议 | 可保留 S-UI；与「全站只要 Xray」目标冲突时再迁 |

**原则：** 先统一暴露面与 REALITY 纪律，再统一版本号。整机重装是手段，不是换 3x-ui 的必选项。

---

## 维护窗前

1. 把客户端流量切到其它节点（cyp 曾是主负载机，断服成本高）。
2. **备份并 scp 回本机**（重装会抹掉 `/root/backup`）。
3. 本仓库：敏感包放 `_backups/`（已 gitignore），**密钥/UUID/私钥永不 commit**。

### 备份最小清单

```text
□ 面板库或导出：UUID、REALITY privateKey / publicKey / shortIds、SNI、域名
□ 客户端名单 + enable
□ authorized_keys（重装后云厂商可能只注入一把当前公钥）
□ 防火墙规则摘要
□ 额外 systemd（如 mssql-ref-proxy、流量月清 cron）
□ 本机 tar + sha256；确认路径可访问后再动刀
```

从 S-UI 抽字段示例（在备份机上，**勿把输出贴进 git**）：

```bash
# 客户端 UUID / 备注
sqlite3 /path/to/s-ui.db "SELECT name, enable FROM clients;"
# REALITY 在 tls 表 server/client JSON（字段因版本略异，以实际为准）
```

S-UI DB **不能**直接导入 3x-ui，只能手工/脚本按字段重建。

---

## 执行顺序

### 1. OS 基线（整装或新机）

```bash
hostnamectl set-hostname <ssh-alias>   # 如 tizi-cyp
timedatectl set-timezone Asia/Shanghai
apt-get update && apt-get install -y \
  curl wget ca-certificates locales sqlite3 ufw fail2ban socat vnstat
# locale en_US.UTF-8；/etc/default/locale
cat >/etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system
# SSH：确认公钥登录后
# PasswordAuthentication no
```

### 2. Tailscale

先 `tailscale up`，再记 **live** IP：

```bash
TS_IP=$(tailscale ip -4)
echo "$TS_IP"   # 重装后几乎一定与旧 IP 不同
```

后续 **面板 listen、socat bind** 一律用 `$TS_IP`，禁止写死旧地址。

### 3. 安装 3x-ui

```bash
export XUI_NONINTERACTIVE=1
# 可选：XUI_PANEL_PORT=2095 等（以当前 install.sh 支持的环境变量为准）
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

- 凭据：`/etc/x-ui/install-result.env`（600），不入库。
- 安装完成后立刻绑面板：

```bash
TS_IP=$(tailscale ip -4)
/usr/local/x-ui/x-ui setting -listenIP "$TS_IP" -port 2095
systemctl restart x-ui
ss -tlnp | grep 2095   # 必须是 100.x:2095，不能是 0.0.0.0:2095
```

- 订阅不用则 sub 绑本机：`subListen=127.0.0.1`（settings 表或面板 UI）。

### 4. 数据面 REALITY（身份连续时「原样迁移」）

要对齐旧客户端、避免全家改配置时：

| 字段 | 处理 |
|------|------|
| 每客户端 UUID | 与备份一致 |
| REALITY privateKey / shortIds / publicKey | 与备份一致 |
| SNI / dest | 现网常用 `assets-xbxweb.xbox.com:443` |
| flow | `xtls-rprx-vision` |
| **minClientVer** | **`1.0.0`**（否则新 Xray 默认门槛会拒 Shadowrocket 等） |
| sockopt | 建议 `domainStrategy=UseIPv4`（无公网 v6 时防 handshake 走 AAAA） |
| share 域名 | `shareAddrStrategy=custom` + 节点域名（如 `cyp-tz.skysms.xyz`） |

可面板手建，或参考 cyp 用 sqlite 写入 `inbounds` / `clients` / `client_inbounds` / `client_traffics` 后 `systemctl restart x-ui`（先停服务再写库更稳）。

**新节点、不要求兼容旧客户端**时：密钥在面板内新生成即可，**不要**跨节点复制同一套 REALITY 私钥（防关联）。

### 5. ufw（Debian）

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 443/tcp
ufw allow in on tailscale0
ufw --force enable
ufw status verbose
```

**先保证 SSH 规则写好再 enable。**

### 6. 旁路服务（若有）

例：`mssql-ref-proxy` 只绑 TS：

```ini
ExecStart=/usr/bin/socat \
  TCP-LISTEN:1433,bind=<当前TS_IP>,fork,reuseaddr,keepalive \
  TCP:100.124.140.78:1433,keepalive
```

`MemoryMax=256M`，`Requires=tailscaled.service`。

### 7. 验收

```bash
# cyp 可直接：
bash scripts/verify-tizi-cyp-baseline.sh

# 通用检查：
hostname
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc   # bbr / fq
ss -tlnp    # *:443=xray；100.x:2095=x-ui；无 0.0.0.0:2095/1433
ufw status
# 对账：启用中 UUID + privateKey 是否在 /usr/local/x-ui/bin/config.json
# 可选 TLS 探针（应见伪装站证书，如 *.xbox.com）：
# echo | openssl s_client -connect <公网IP>:443 -servername assets-xbxweb.xbox.com 2>/dev/null | openssl x509 -noout -subject
```

抽测 1～2 个真实客户端（含 iOS Shadowrocket）后再关维护窗。

### 8. 文档

- 追加 `docs/operations/<server>.md`（时间倒序）
- `git commit` 在 `main`；**无** 私钥、UUID 清单、面板密码、TS auth key

---

## 常见坑（速查）

| 现象 | 原因 | 处理 |
|------|------|------|
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | 重装换了 host key | `ssh-keygen -R <IP>`；再确认指纹 |
| 面板 `http://TS:2095/` **404** | 未带 **webBasePath** | 见下节完整 URL |
| install-result 的 ACCESS_URL 打不开 | 仍是安装时公网+随机端口 | 以 live `webListen`+`webPort`+`webBasePath` 为准 |
| Shadowrocket 连不上、桌面 Xray 可以 | 缺 `minClientVer` | 设为 `1.0.0` 并 restart x-ui |
| 跳板/面板 bind 失败 | 仍用旧 TS IP | `tailscale ip -4` 后改正 unit/settings |
| 密钥登录失败 | 镜像只写了部分 pubkey | 控制台写入 `authorized_keys` |
| S-UI 库导入 3x-ui | 格式不兼容 | 只迁字段，不迁文件 |

---

## webBasePath 是什么？

3x-ui 安装时生成的**随机 URL 路径前缀**，面板**不在** `/`。  
根路径访问会 **404**（服务正常，路径不对）。

```bash
# 查完整入口（在节点上）
python3 - <<'PY'
import sqlite3
c=sqlite3.connect("/etc/x-ui/x-ui.db")
listen=c.execute("SELECT value FROM settings WHERE key='webListen'").fetchone()[0]
port=c.execute("SELECT value FROM settings WHERE key='webPort'").fetchone()[0]
base=c.execute("SELECT value FROM settings WHERE key='webBasePath'").fetchone()[0]
if not base.startswith("/"): base="/"+base
if not base.endswith("/"): base+="/"
print(f"http://{listen}:{port}{base}")
PY
# 账密：cat /etc/x-ui/install-result.env   # 600，勿入库
```

浏览器须已接入 **Tailscale**。

---

## 回滚要点

- **未重装 OS、只换面板**：保留旧面板 DB 备份，卸 3x-ui 后按厂商文档回装旧栈（成本高，优先保证 3x-ui 迁对身份）。
- **已整装**：只能从本机 `_backups/` 重建；公网 IP/DNS 一般不变，客户端配置可保持。
- **单服务**：`systemctl restart x-ui` / 关 `mssql-ref-proxy` / `ufw delete` 某条规则——按 operations 时间线里的回滚命令。

---

## 节点对照（2026-08-09）

| 节点 | 栈 | 备注 |
|------|-----|------|
| tizi-cyp | Debian 13 + 3x-ui | 本 runbook 主来源；TS IP 重装后已变 |
| tizi-ddy | Debian 13 + 3x-ui | 扩容模板；`minClientVer` 先例 |
| tizi / rao-tizi | 历史上 S-UI 为主 | 升级时优先对照本 runbook + 各自 operations |

上线后若有新坑，追加到对应 `docs/operations/<server>.md`，可复用经验再 compound 进 `docs/solutions/`。

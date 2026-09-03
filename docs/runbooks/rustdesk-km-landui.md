# RustDesk 自托管（km-landui）

> 服务器：`km-landui`（`43.228.79.237`，昆明）  
> 版本：OSS `hbbs`/`hbbr` 1.1.16  
> 用途：主控 / 被控都在国内时的 ID + 中继。不要拿去控香港阿里云等打不通这台机的主机。

## 客户端怎么填

两端（你的电脑 + 被控电脑）都要改 **设置 → 网络**：

| 字段 | 值 |
| --- | --- |
| ID 服务器 | `43.228.79.237` |
| 中继服务器 | `43.228.79.237` |
| API 服务器 | **留空**（OSS 没有控制台） |
| 密钥 | `mLupdW95mI8GfMLicW0sJbHL6tR6IVgyk2HRN6sL+Gs=` |

填完后重启 RustDesk 客户端。被控端应显示在线，ID 是一串数字。

客户端安装包：[RustDesk 官网](https://rustdesk.com/) 或 [GitHub Releases](https://github.com/rustdesk/rustdesk/releases)。

## 服务端速查

```bash
ssh km-landui
systemctl status rustdesk-hbbs rustdesk-hbbr
journalctl -u rustdesk-hbbs -u rustdesk-hbbr -n 50
ss -lntup | grep 2111
```

| 项 | 值 |
| --- | --- |
| 单元 | `rustdesk-hbbs.service`、`rustdesk-hbbr.service`（enabled） |
| 二进制 | `/usr/local/bin/hbbs`、`/usr/local/bin/hbbr` |
| 数据 / 密钥 | `/var/lib/rustdesk-server/`（用户 `rustdesk`） |
| 公钥 | `id_ed25519.pub`（可给客户端） |
| 私钥 | `id_ed25519`（**不要**拷出、不要进 git） |
| 公网端口 | TCP `21115–21117`、UDP `21116` |
| 故意不开 | TCP `21118`/`21119`（Web Client） |
| 未改 | `derper`（仍占 443 / UDP 3478） |

停用（回滚）：

```bash
systemctl disable --now rustdesk-hbbs rustdesk-hbbr
```

数据目录默认保留，再次 `enable --now` 即可用回同一把密钥。

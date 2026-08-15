# cursor-box 运维操作时间线

Cursor Cloud Agent 沙箱。容器内 hostname 是 `cursor`，Tailscale 节点名是 `3x-ui`（`100.102.171.1` / `3x-ui.taila93443.ts.net`）。**不是** `tizi-ddy` 上的 3x-ui 代理面板。

登录：`ssh box@100.102.171.1`（用户 `box`，无密码 sudo）。会话结束或 Cursor 回收后节点可能消失，不要当常驻生产机。

## 2026-08-15 12:17 CST - 只读盘点 VM / 容器规格

- 服务器：`cursor-box`（Tailscale `3x-ui` / `100.102.171.1`）
- 操作人：`Grok`
- 原因：用户要求 `ssh box@100.102.171.1` 查看这台 VM 的配置；仓库此前无记录。
- 影响：只读（`hostname` / `lscpu` / `free` / `df` / `ss` / `ps` / `tailscale status`）；未改配置、未重启、未装软件。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：经 Tailscale SSH 登录 `box@100.102.171.1`，采集 OS / CPU / 内存 / 磁盘 / 网络 / 进程 / 工具链。
- 验证结果（2026-08-15 04:15 UTC 快照，开机约 20 分钟）：

  | 项 | 值 |
  | --- | --- |
  | 形态 | KVM 宿主机上的 Docker 容器（PID 1 = `tini`，根文件系统 overlay，cgroup `/agent`） |
  | OS | Debian GNU/Linux 13.6 (trixie)，kernel `6.12.94+` x86_64 |
  | CPU | 8 vCPU，`Intel(R) Xeon(R) Processor`，2.4 GHz，无超线程 |
  | 内存 | 16 GiB（约 15.6 GiB 可见），已用约 1.6 GiB，无 swap |
  | 磁盘 | `vda` 128G，overlay `/` 已用 5.5G / 126G（5%） |
  | 用户 | `box` uid 1000，`(ALL) NOPASSWD: ALL` |
  | 局域网 | `enp0s3` = `172.30.0.2/24`，网关 `172.30.0.1` |
  | Tailscale | `100.102.171.1` / `fd7a:115c:a1e0::3a:ab02`，DERP `sea`；本机到 `macbook-air` 走 relay `km` |
  | 公网出口 | AWS `us-west-2` 量级（endpoint `44.235.249.110`，`ifconfig.me` 见 `54.188.181.83`） |
  | 桌面 | 两套 Xvfb `:1`/`:2` 1280x800 + XFCE/`plank` + x11vnc + noVNC `6080`/`6081` |
  | Agent 栈 | `sand-host` `89ce35b`、`exec-daemon`、`sand-supervisor`；工作区 `/workspace` 几乎空 |
  | 工具链 | Node 20.19.2、Python 3.13.5、Go 1.24.4、Rust 1.85.0、git 2.47.3、Tailscale 1.102.2 |
  | 时区 | 容器时钟 UTC；Cursor 设置 `userTimeZone=Asia/Singapore` |

- 备注：
  - `tailscale status` 健康告警：宿主机内核缺 `connmark`/`CONNMARK` 模块；`--accept-routes` 为 false（其它节点在广告路由）。
  - locale `en_US.UTF-8` 未装全，SSH 会话会报 `setlocale` 警告，不影响只读采集。
  - 未写入 `~/.ssh/config` 别名。需要常驻接入时再加 `Host cursor-box`。

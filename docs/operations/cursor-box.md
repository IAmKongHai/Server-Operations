# cursor-box 运维操作时间线

Cursor Cloud Agent 沙箱。容器内 hostname 是 `cursor`，Tailscale 节点名是 `3x-ui`（`100.102.171.1` / `3x-ui.taila93443.ts.net`）。**不是** `tizi-ddy` 上的 3x-ui 代理面板。

登录：`ssh box@100.102.171.1`（用户 `box`，无密码 sudo）。会话结束或 Cursor 回收后节点可能消失，不要当常驻生产机。

网卡上**没有独立公网 IPv4**。网卡只有 `172.30.0.2/24` 和 Tailscale `100.102.171.1`。出站经宿主机 NAT（当前源 IP 表现为 Cloudflare `104.30.175.37`），入站只能走 Tailscale / Cursor 控制面，不能当公网站点或代理节点。

**不要**在这台沙箱上注册 GitHub Actions runner：无公网 IP 不影响 runner 出站，但机器是 Cursor 临时容器、无 Docker、凭证会落到非自管环境。CI 继续用 `docs/runbooks/ci-runner-pools.md` 里的自管机。

## 2026-08-15 12:31 CST - 评估能否当 GitHub runner

- 服务器：`cursor-box`
- 操作人：`Grok`
- 原因：用户问能否用这台无公网 IP 的沙箱做 GitHub runner。
- 影响：只读（查 docker / 磁盘 / 是否已有 Runner.Listener）；未安装 runner、未改配置。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：对照 `docs/runbooks/ci-runner-pools.md`，并复查本机 Docker 与持久化。
- 验证结果：
  - 无 `docker` 二进制、无 `/var/run/docker.sock`；`:2375` 在听但不是可用的 CI Docker。
  - 根盘是 overlay，无已装 `actions-runner`。
  - 规格 8c / 16G / 128G 对 Linux job 够用，但生命周期与安全不满足自管 runner 要求。
- 结论：协议上能装（runner 只出站），**不要装**。需要 Linux 容量时扩 `mas-go-dev-ci` 或 `dev-cypresso`，不要用 Cursor 沙箱。

## 2026-08-15 12:24 CST - 确认无独立公网 IP

- 服务器：`cursor-box`（Tailscale `3x-ui` / `100.102.171.1`）
- 操作人：`Grok`
- 原因：用户问这台沙箱是否没有公网 IP、以及这种形态能做什么。
- 影响：只读（`ip addr` / `ip route` / 出站 `curl` / `ss` / `tailscale`）；未改配置。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：复查网卡、默认路由、出站源 IP、监听端口、Tailscale endpoint。
- 验证结果：
  - 接口：`enp0s3=172.30.0.2/24`，`tailscale0=100.102.171.1`，无 `1.x/8` 以外的公网地址。
  - 默认路由：`default via 172.30.0.1 dev enp0s3 src 172.30.0.2`。
  - 出站探测（ifconfig.me / ipify / icanhazip / ipinfo）均回 `104.30.175.37`（Cloudflare，San Jose），说明有出网、但源 IP 是共享出口，不是本机专属。
  - Tailscale `Addrs` 含 AWS `100.22.162.62:38454`，这是宿主机 NAT 映射给 WireGuard 打洞用的，不是沙箱的 inbound 公网 IP。
  - 本机大量端口听在 `0.0.0.0`，但公网到不了；tailnet 内可经 `100.102.171.1` 访问。
- 结论：适合当隔离开发/跑 Agent/出站拉代码调 API；不适合当公网站点、webhook 接收端、3x-ui 代理节点。需要对外暴露时另开 Tailscale Funnel / Cloudflare Tunnel，且仍受沙箱生命周期限制。

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

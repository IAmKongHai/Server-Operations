# qingfan-prod 运维操作时间线

## 2026-11-14 13:31 CST - 通过自定义镜像迁移至同配置香港轻量新实例 `8.217.180.182`（解决 `8.210.153.241` 被墙）

- 服务器：新 `qingfan-prod`（实例 `64554ead28484ec19f550547435b4418`，公网 `8.217.180.182`，内网 `172.21.63.216`）← 旧实例 `68c002bd79054bd2bdaffdfef2321cce`（`8.210.153.241` / `172.21.63.215`）
- 操作人：Antigravity（用户确认并完成新实例下单付款）
- 原因：旧实例公网 IP `8.210.153.241` 在中国大陆三大运营商全网 100% 丢包不可达，且阿里云轻量不支持单独更换公网 IP；赶在旧实例 5 天无理由退订截止（`2026-11-14 18:01:50 CST`）前通过自定义镜像新开同配实例切换。
- 影响：应用切换窗口约 15 秒；数据库位于同地域 RDS `pgm-j6cd36m59smx6n9g`，数据零变更；打快照至切换期间 `/var/lib/qingfan` 无文件新增，零数据丢失。
- 备份：
  - 系统盘快照：`s-j6c26v4rfczskai5tp8v`（`qingfan-prod-migrate-20261114`）
  - 自定义镜像：`m-j6ccgmgyr80s1o747hp3`（`qingfan-prod-migrate-20261114`）
  - 本机 SSH 配置：`~/.ssh/config.bak.20261114`
- 回滚方式（旧机退订前）：停止新机 `qingfan-green` 与 `tk-flywheel`；在旧机 `8.210.153.241` 执行 `docker update --restart=unless-stopped qingfan-green && docker start qingfan-green && systemctl start tk-flywheel nginx`；恢复 `~/.ssh/config.bak.20261114` 与 Cloudflare DNS。
- 变更时序：
  1. `12:54 CST`：对旧机系统盘 `d-j6cc43u7chuzdtv45vgv` 创建快照 `s-j6c26v4rfczskai5tp8v`，`12:57` 完成；`12:58` 基于该快照生成自定义镜像 `m-j6ccgmgyr80s1o747hp3`。
  2. `13:16 CST`：用户基于自定义镜像 `m-j6ccgmgyr80s1o747hp3` 新购同规格（`swas.s.c4m8s70b1.linux`，4C/8G/70G ESSD，1 年）香港轻量实例 `64554ead28484ec19f550547435b4418`，分配公网 `8.217.180.182`、内网 `172.21.63.216`。
  3. `13:23 CST`：核实新实例自动继承 4 条防火墙规则（TCP `22/80/443` + ICMP `0.0.0.0/0`）；SSH 登录新机先暂停 `qingfan-green` 与 `tk-flywheel`，避免双 worker 并发。
  4. `13:25 CST`：Globalping 全国多省三网检测新 IP `8.217.180.182`：广州电信 21ms、东莞电信 23ms、台山移动 25ms、宁波移动 47ms、长沙移动 65ms、武汉联通 61ms、荆州联通 73ms，`TCP:443` / `TCP:22` **全部 0% 丢包**。（注：云南 `km-landui` 因本省对阿里云香港全网段阻断仍超时，属预期。）
  5. `13:26 CST`：将新机内网 IP `172.21.63.216` 追加至 RDS `pgm-j6cd36m59smx6n9g` 白名单分组 `swas_hk`（`172.21.63.215,172.21.63.216`），将新实例重命名为 `qingfan-prod`，实测 `qingfan` / `tk_flywheel` 两库内网连通正常。
  6. `13:30 CST`：核查旧机 `/var/lib/qingfan`、`/opt`、`/etc` 自快照起无任何文件改动；停掉旧机 `qingfan-green`（设 `--restart=no`）、`tk-flywheel`、`nginx`，启动新机 `qingfan-green` 与 `tk-flywheel`。
  7. `13:31 CST`：更新 GitHub `IAmKongHai/qingfan`（`DEPLOY_HOST`、`DEPLOY_KNOWN_HOSTS`）、`IAmKongHai/tk-flywheel`（`PRODUCTION_KNOWN_HOSTS`）及本机 `~/.ssh/config` 的 `qingfan-prod` 指向 `8.217.180.182`。
- 验证：
  - `--resolve` 指向 `8.217.180.182` 测试 `qingfan.app/healthz`、`/`、`/admin/`、`flywheel.qingfan.app/healthz` 均返回 `HTTP 200`，`/version.txt` 返回 `b6d024bf6e7bcf5f0da9055fe275955495306a43`。
  - `ssh qingfan-prod` 正常登录新主机 `iZj6cg6lmcje31wwguao8bZ`。
  - 待用户在 Cloudflare 将 `qingfan.app`、`flywheel.qingfan.app` A 记录切至 `8.217.180.182`，并在 `18:01 CST` 前于阿里云控制台完成旧实例五天无理由退订。

## 2026-11-14 12:35 CST - 复查国内访问 `qingfan.app`（结论不变：`8.210.153.241` 整 IP 不通）

- 服务器：`qingfan-prod`（`8.210.153.241`），对照组 `nyh-prod-2026`（`8.217.145.133`），国内跳板 `km-landui` + Globalping 国内节点
- 操作人：Claude（只读，没有改任何东西）
- 原因：用户再次反馈国内访问不到 `qingfan.app`，要求用 `km-landui` 做跳板测试。
- 影响：无。
- 回滚方式：不需要。
- 结果：
  1. `km-landui` → `8.210.153.241` 的 `:443` / `:80` / `:22` 和 ICMP 全部超时；`curl https://qingfan.app/` 返回 `000`（超时）。但它到对照组 `8.217.145.133`、阿里云香港 `47.242.0.1` 也一样不通，到美国 `137.184.127.196:443`、Cloudflare `104.16.132.229:443` 正常。所以 `km-landui` 只能看出“到阿里云香港不通”，分不出是不是这个 IP 的问题。TCP traceroute 每一跳都是 `*`，拿不到中间路由。
  2. Globalping 用同一批 8 个国内探针做 `TCP:443` 对比：
     - `8.210.153.241`：武汉联通、长沙联通、无锡联通、北京腾讯、上海腾讯、盐城电信全部 **100% 丢包**（另外 2 个探针本身没跑成）。
     - `8.217.145.133`：武汉联通 68ms、长沙联通 65ms、上海腾讯 35ms，**0% 丢包**（其余探针没跑成）。
  3. 从香港 `nyh-prod-2026` 访问 `https://qingfan.app/` 返回 200（74ms），`flywheel.qingfan.app/healthz` 返回 200，源站正常。
- 结论：和 12:27 的条目一致。同机房同类型机器国内能通，只有 `8.210.153.241` 全国三网都不通，是这个公网 IP 被封了，不是服务、域名或 DNS 的问题。要恢复国内访问只能换 IP 或在前面加一层国内能访问的入口，需要用户确认方案后再动。

## 2026-11-14 12:27 CST - 只读排查中国大陆无法访问 `qingfan.app`（确诊 `8.210.153.241` 整 IP 被墙）

- 服务器：`qingfan-prod`（`8.210.153.241`），配合国内跳板 `km-landui`（`43.228.79.237`）及 Globalping 中国大陆多省节点
- 操作人：Antigravity（只读排查，未做任何配置或服务改动）
- 原因：用户反馈从中国国内访问不到 `qingfan.app` 的服务器。
- 影响：无（纯只读探测）。
- 回滚方式：无需回滚。
- 排查过程与结论：
  1. **源站与海外访问正常**：`qingfan-prod` 上 `nginx`（`:80`/`:443`）、`qingfan-server`（`127.0.0.1:8091`）、`flywheel`（`127.0.0.1:8087`）均在线；本机 `iptables`/`nftables` INPUT 策略为 ACCEPT。从境外访问 `https://qingfan.app/` 返回 `HTTP/2 200`。
  2. **排除 DNS 污染**：在 `km-landui` 查询 `119.29.29.29`、`114.114.114.114`、`180.76.76.76`、`223.5.5.5`，并通过 Globalping 在广州、武汉、北京、长沙、深圳、昆明等国内节点查询 `qingfan.app` / `flywheel.qingfan.app` A 记录，均正确返回 `8.210.153.241`。
  3. **排除域名 TLS SNI / HTTP Host 阻断**：从 `km-landui` 携带 `SNI: qingfan.app`、`SNI: flywheel.qingfan.app` 及 `Host: qingfan.app` 请求国内可达的境外 IP（`137.184.127.196:443` / `:80`），TLSv1.3 握手与 HTTP 响应均完整往返，无 TCP RST 或丢包，证明域名本身未被 GFW 封锁。
  4. **剥离 `km-landui` 云南省际跨境干扰**：实测 `km-landui`（昆明蓝队云）对整个阿里云香港网段（含对照组 `nyh-prod-2026` `8.217.145.133:443`）及 `1.1.1.1:443`、`8.8.8.8:443` 均存在省际/机房级 TCP 阻断（而连美国 `137.184.127.196:443`、`140.82.113.4:443` 及 Cloudflare Anycast `104.21.32.1:443` / `104.16.132.229:443` 正常）；因此引入全国多省三大运营商节点做对照，避免单点误判。
  5. **确诊根因 —— `8.210.153.241` 公网 IP 被整 IP 封锁（IP 黑洞）**：
     - 对照组 `nyh-prod-2026`（`8.217.145.133`，同为阿里云香港轻量）：全国多省节点（武汉/长沙/福州/桂林联通、北京/广州腾讯）测 `TCP:443` **0% 丢包**（RTT 14～80ms）。
     - 实验组 `qingfan-prod`（`8.210.153.241`）：同一批全国电信、联通、移动节点测 **ICMP、`TCP:443`、`TCP:22` 全部 100% 丢包**；`qingfan-prod` 侧未收到来自 `km-landui` 的 SYN；从 `qingfan-prod` 反向 TCP traceroute 去国内在广州电信国际出口 `202.97.12.38` / `202.97.94.97`（AS4134）后全部中断。
     - 检查 `/var/log/nginx/access.log*`（自 11-10 建机以来），历史请求主要来自 `tizi-kh`（`74.211.103.83`）、`tizi-cyp`（`89.208.242.203`）等境外出口，基本无中国大陆直连 IP 记录，高度疑似 11-10 新开香港轻量时分配到了已被墙的回收 IP。

## 2026-11-11 23:10 CST - 撤掉 DO-1 迁移用的 hk-migrate 受限入口

- 服务器：`qingfan-prod`
- 操作人：Claude（用户确认）
- 原因：DO-1 上的 qingfan / tk-flywheel 已经彻底删除（见 `docs/operations/do-1.md` 同日条目），迁移计划写明切换后要撤掉这个入口。
- 影响：去掉 root `authorized_keys` 里只允许 `137.184.127.196` 使用的 `hk-migrate` 强制命令密钥；其它密钥（`konghai@konghai.me`、`hon-2026`、`tk-flywheel-github-deploy`）不动，业务不受影响。
- 备份：`/root/.ssh/authorized_keys.bak.20261111`；本机 `_backups/do-1-qingfan-flywheel-removal-20261111/qingfan-prod-hk-migrate.tgz`（`authorized_keys` 和两个脚本）。
- 回滚方式：`cp -p /root/.ssh/authorized_keys.bak.20261111 /root/.ssh/authorized_keys`，再从 tgz 恢复脚本。
- 做了什么：删掉 `authorized_keys` 里的 `hk-migrate` 那一行；删除 `/usr/local/sbin/hk-migrate-{recv,db}` 和 `/var/lib/hk-migrate/`（75M，是 11-09 演练留下的旧 dump）；删除临时中转目录 `/root/relay-do1-20261111`。
- 验证：新开 SSH 连接正常；`qingfan.app`、`flywheel.qingfan.app` 的 `/healthz` 都返回 200。
- 另外发现：qingfan 现在由 Docker 容器里的 `qingfan-server` 监听 `127.0.0.1:8090`（11-11 08:29 UTC 起），systemd `qingfan@blue` 是 inactive。README 的服务表还是旧写法，已标为待核实。

## 2026-11-10 11:20 CST - 只读评估是否需要启用 swap

- 服务器：`qingfan-prod`
- 操作人：`Claude`（只读排查，未做任何改动）
- 原因：用户问是否有必要启用 swap。
- 结论：现在没有必要。可以加一个小 swap 当保险，等用户决定。
- 观察：
  - 总内存 7.2G，used 约 509M，available 约 6.9G。buff/cache 6.9G 是可回收的页缓存，不算内存压力。
  - 两个应用的常驻内存都很小：`flywheel` 约 28M，`qingfan-server` 约 25M。数据库在 RDS 上，不占本机内存。
  - 内核日志里没有 OOM 记录。`vm.swappiness=60`，两个服务的 `MemoryMax` / `MemoryHigh` 都没有设置。
  - `sar` 没有历史数据，开机到现在也才 18 小时左右，所以看不到峰值。

## 2026-11-10 11:05 CST - 纳入仓库：加 ssh 别名、建档案、加同事 hon 公钥

- 服务器：`qingfan-prod`（`root@8.210.153.241`，阿里云香港）
- 操作人：`Claude`（用户要求）
- 原因：新增 qingfan 项目生产服务器，需要快捷登录、档案，并给同事 hon 开登录权限。
- 影响：只追加了一行 `authorized_keys`，没有重启任何服务。
- 备份：
  - 本机 `~/.ssh/config.bak.20261110`
  - 服务器 `/root/.ssh/authorized_keys.bak.20261110`
- 回滚方式：
  - 去掉 hon 的权限：在服务器上删掉 `authorized_keys` 里注释为 `hon-2026` 的那一行（或用备份覆盖回去）。
  - 别名：删掉本机 `~/.ssh/config` 末尾的 `Host qingfan-prod` 段。
- 做了什么：
  1. 本机 `~/.ssh/config` 追加 `Host qingfan-prod`：`HostName 8.210.153.241`、`User root`、`IdentityFile ~/.ssh/id_ed25519`、`IdentitiesOnly yes`。
  2. 只读采集系统、服务、nginx、数据库连接等信息，写成档案 `qingfan-prod/README.md`。
  3. 往 `/root/.ssh/authorized_keys` 追加 `ssh-ed25519 …HzYPDW5HZfjPj hon-2026`（追加前先检查过，没有重复）。
- 验证：
  - `ssh qingfan-prod` 能登录，`hostname` 为 `iZj6cfbbt4l6yxdiqkoqnfZ`。
  - `authorized_keys` 现在有 4 行：`konghai@konghai.me`、`tk-flywheel-github-deploy`、`hk-migrate`、`hon-2026`，权限 `600 root:root`；`ssh-keygen -lf` 解析出 hon 公钥指纹 `SHA256:t5JxvwYZEe9z6KOnXyd08lYm/3rRTIrfzSM8J1k3e+0`。
  - hon 那边能不能登录还需要同事自己验证一次。

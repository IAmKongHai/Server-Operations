# office-router 运维操作时间线

## 2026-08-28 13:02 CST - PassWall Geo 改为 tmpfs bind-mount，挡住自动更新写爆闪存

- 服务器：`office-router`（Kwrt / OpenWrt 25.12-SNAPSHOT，LAN `192.168.6.1`）
- 操作人：`Grok`
- 原因：overlay 只有约 39MB，未压缩的 `geoip.dat`（16MB）+ `geosite.dat`（11MB）合计约 27MB，超过当时约 17MB 空闲。当天中午的软链+xz 临时方案挡不住 PassWall `rule_update.lua` 的 `mv /tmp/*.dat → /usr/share/v2ray/`（busybox `mv` 会拆掉软链、把普通文件写回闪存）。
- 选型：不改 PassWall 本体（避免 opkg 升级冲掉补丁），把 `/tmp/v2ray-geo` bind-mount 到 `/usr/share/v2ray`。更新仍走原路径，但落点在内存；闪存只保留 xz。后台每 120 秒对比 md5，有变化再压回 `/usr/lib/v2ray-geo/`。
- 影响：
  - 未重启 PassWall / xray / 网络 / 防火墙。xray PID 保持 `14833`。
  - 办公室透明代理继续走节点 `cyp-tizi`。
  - 开机多一次 xz 解压（约 28MB RAM，机器 489MB 够用）。
  - PassWall 规则自动更新真正生效：每天 04:00 跑 `rule_update.lua`（原先 UCI 只剩旧字段 `week_update`/`time_update`，新版读 `update_week_mode`，crontab 实际是空的）。
- 备份：
  - 路由器 `/root/backup-v2ray-geo-20260828/`（旧 init、`passwall` UCI export、crontab）
  - 本仓库 `scripts/office-router-v2ray-geo.init`
- 回滚方式：
  1. `/etc/init.d/v2ray-geo stop`（会先 persist，再 umount）
  2. 用 `/root/backup-v2ray-geo-20260828/v2ray-geo.init.bak` 覆盖 `/etc/init.d/v2ray-geo`
  3. 按需 `uci import` 那份 `passwall.uci.bak`，crontab 从 `crontab.root.bak` 恢复
  4. 不要把未压缩 `.dat` 拷回 `/usr/share/v2ray/`，会再次写满 overlay
- 变更时序：
  1. 只读确认：overlay 54% / 空闲 17.3MB；`/usr/share/v2ray/*.dat` 是指向 `/tmp/v2ray-geo` 的软链；xz 约 3.9MB 在闪存。
  2. 备份 init / UCI / crontab。
  3. 安装新 `/etc/init.d/v2ray-geo`（`START=19`，已 enable）。
  4. `/etc/init.d/v2ray-geo start`：把 xz 迁到 `/usr/lib/v2ray-geo/`，bind-mount，拉起 persist 循环。
  5. 用 2MB 探测文件 `mv` 到 `/usr/share/v2ray/`：出现在 `/tmp/v2ray-geo/`，overlay Used 未增加。
  6. `geoview` 从 `geoip.dat` 抽出 `cn` 共 6222 条，文件可读。
  7. UCI：`update_week_mode=7`，`update_time_mode=4:00`（`geoip_update`/`geosite_update` 本来就是 1）。
  8. crontab 追加 `0 4 * * * lua /usr/share/passwall/rule_update.lua log all cron`（未重启 crond；busybox crond 会自行重读）。
  9. `/etc/sysupgrade.conf` 保留 init 与 `/usr/lib/v2ray-geo/`。
- 验证：
  - `/proc/mounts`：`tmpfs /usr/share/v2ray`
  - overlay 仍约 `20.1M/39.4M`（54%），空闲 17.3MB
  - persist：`geoip.dat.xz` 1.7M + `geosite.dat.xz` 2.2M，md5 与 RAM 文件一致
  - xray 仍在跑，未重启
  - PassWall 12:51 那次启动日志是成功的（ChinaDNS-NG + nftables + 节点 `cyp-tizi`）；本次未再改代理规则
- 备注：
  - 本机 `~/.ssh/config` 里 `Host office-router` 仍指向 `192.168.8.1`，这次实际操作的是 LAN `192.168.6.1`
  - overlay 大头仍是 `/usr/bin/xray`（约 31MB）；本次未动
  - PassWall 日志里 Dnsmasq 2.91 < 2.92 只是建议，未升级
  - 方案说明：`docs/solutions/office-router/best-practices/passwall-geo-small-flash-2026-08-28.md`

## 2026-06-30 12:28 CST - 移除闲置 GitHub Actions runner

- 服务器：`office-router`
- 操作人：`Codex`
- 原因：该路由器上的 GitHub Actions self-hosted runner 已不再使用，需要停止 runner 并释放 Docker 镜像、volume 和运行进程占用的资源。
- 影响：
  - 停止并删除 Docker 容器 `github-runner-office`。
  - 删除 runner 使用的 Docker volume：`office-runner-home`、`office-runner-work`。
  - 删除不再被其它容器使用的镜像 `ghcr.io/actions/actions-runner:latest`。
  - 删除原始操作目录 `/opt/github-runner`，避免后续误执行 `start.sh` 重新拉起 runner。
  - 未重启路由器，未停止 Docker daemon，未修改网络、防火墙、SSH 或其它业务配置。
- 备份：
  - `/opt/github-runner-backup-20260630-122752/`，权限 `700`，包含原 `/opt/github-runner` 配置目录、清理前 `docker inspect`、`docker ps` 和 `docker system df` 输出。
- 回滚方式：
  1. 从 `/opt/github-runner-backup-20260630-122752/github-runner` 恢复 `/opt/github-runner`。
  2. 在 GitHub 页面重新生成 self-hosted runner 注册 token，并更新 `/opt/github-runner/runner.env`。
  3. 执行 `/opt/github-runner/start.sh` 重新创建 volume、拉取镜像并注册 runner。
  4. 如 GitHub 页面仍保留旧的离线 `office-router-light-ci-1` runner，需要在 GitHub UI/API 中手动删除。
- 变更：
  1. 清理前确认 runner 形态：
     - 容器：`github-runner-office`
     - 镜像：`ghcr.io/actions/actions-runner:latest`
     - 重启策略：`unless-stopped`
     - volume：`office-runner-home` 挂载到 `/home/runner`，`office-runner-work` 挂载到 `/home/runner/_work`
     - runner 进程：`/home/runner/bin/Runner.Listener run`
  2. 创建备份目录并保存现状。
  3. 执行 `docker rm -f github-runner-office` 停止并删除容器。
  4. 执行 `docker volume rm office-runner-home office-runner-work` 删除 runner 数据卷。
  5. 执行 `docker image rm ghcr.io/actions/actions-runner:latest` 删除闲置 runner 镜像。
  6. 删除 `/opt/github-runner` 原始操作目录。
- 验证：
  - `docker ps -a` 无容器。
  - `docker volume ls` 无 volume。
  - `docker images` 无镜像。
  - `docker system df` 显示 Images / Containers / Local Volumes 均为 `0B`。
  - `ps w` 未发现 `Runner.Listener`、`Runner.Worker`、`actions-runner` 或 `github-runner-office` 进程。
  - `/opt/github-runner` 已不存在，备份目录 `/opt/github-runner-backup-20260630-122752` 保留。
  - `/opt` 从清理前约 `2.2G` 已用降至 `2.7M` 已用。

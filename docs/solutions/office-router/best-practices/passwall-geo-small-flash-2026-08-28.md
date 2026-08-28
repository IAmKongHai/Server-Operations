---
title: 小闪存 OpenWrt 上 PassWall Geo 库不能直接落 overlay
date: 2026-08-28
category: docs/solutions/office-router/best-practices
server: office-router
module: office-router / PassWall / Xray GeoIP Geosite
problem_type: best_practice
component: infrastructure
severity: high
applies_when:
  - OpenWrt overlay 只剩十几 MB，却要跑 luci-app-passwall
  - PassWall 开启 geoip/geosite 自动更新（rule_update.lua 会 mv 到 v2ray_location_asset）
  - 想用软链把 .dat 指到 /tmp，指望更新也写内存
tags:
  - office-router
  - passwall
  - geoip
  - geosite
  - overlay
  - bind-mount
  - xray
  - openwrt
---

# 小闪存 OpenWrt 上 PassWall Geo 库不能直接落 overlay

## Context

`office-router`（Kwrt，OpenWrt 25.12-SNAPSHOT，mediatek/filogic，LAN `192.168.6.1`）overlay 总共约 39MB。PassWall 用 Loyalsoldier `geoip.dat`（约 16MB）+ `geosite.dat`（约 11MB），未压缩合计约 27MB。空闲一旦低于这个数，自动更新会把 overlay 写满。

操作时间线：`docs/operations/office-router.md`（2026-08-28 bind-mount 条目）。  
可部署脚本：`scripts/office-router-v2ray-geo.init`。

## 为什么软链挡不住更新

PassWall `rule_update.lua` 的 `fetch_geofile()` 流程是：

1. curl 下载到 `/tmp/geoip.dat`（或 `geosite.dat`）
2. `mv -f` 现有 asset 文件到 `/tmp/bak_v2ray/`（备份在内存，这一步安全）
3. `mv -f /tmp/geoip.dat /usr/share/v2ray/geoip.dat`

busybox `mv` 遇到目标是软链时，会先拆掉软链再落下普通文件。结果：

- `/usr/share/v2ray/geoip.dat` 从「指向 `/tmp` 的软链」变成 overlay 上的 16MB 真文件
- 两个 dat 一起写，超过当时约 17MB 空闲，更新失败或 overlay 100%

`v2ray_location_asset` 默认就是 `/usr/share/v2ray/`。xray 启动时 `V2RAY_LOCATION_ASSET` / `XRAY_LOCATION_ASSET` 也读这个 UCI。

## 方案：tmpfs bind-mount + xz 持久化

不要补丁 PassWall（opkg 升级会冲掉）。让 asset 目录本身就是内存：

| 路径 | 作用 |
| --- | --- |
| `/tmp/v2ray-geo/*.dat` | 运行时未压缩库（RAM） |
| `/usr/share/v2ray` | bind-mount 到上面那个目录；PassWall / xray 仍用原路径 |
| `/usr/lib/v2ray-geo/*.dat.xz` | 闪存上的压缩副本，约 3.9MB |
| `/etc/init.d/v2ray-geo` | `START=19`，先于 PassWall `S99` |

开机：解压 xz → bind-mount → 拉起 persist 循环（每 120 秒看 md5，有变化再 `xz` 回闪存）。overlay 空闲低于 4MB 时跳过 persist，避免压的过程把闪存写满。

手动命令：

```bash
/etc/init.d/v2ray-geo start     # 解压 + bind-mount + persist 循环
/etc/init.d/v2ray-geo persist   # 立刻把 RAM 中的新 dat 压回闪存
/etc/init.d/v2ray-geo stop      # 先 persist，再 umount（会让 xray 暂时看不到 geo，不要在代理运行时随便停）
```

验证更新不会写闪存：

```bash
df -k /overlay
# 随便 mv 一个文件到 /usr/share/v2ray/，应出现在 /tmp/v2ray-geo/，且 overlay Used 不变
grep " /usr/share/v2ray " /proc/mounts   # 应为 tmpfs
```

## PassWall 自动更新字段

`luci-app-passwall` 26.8.x 的规则页用的是：

- `update_week_mode`：空=关，`7`=每天，`8`=循环
- `update_time_mode`：例如 `4:00`
- `geoip_update` / `geosite_update`

旧字段 `auto_update` / `week_update` / `time_update` 还在 UCI 里也不会进 crontab。`app.sh start_crontab()` 只看新字段，所以「界面以为每天更新」时 crontab 可能是空的。

每天 04:00 应对应：

```
0 4 * * * lua /usr/share/passwall/rule_update.lua log all cron > /dev/null 2>&1 &
```

PassWall 下次正常重启时会按 UCI 重写这条；不要再手写一套冲突的 cron。

## 不要做的事

- 不要把未压缩 `.dat` 拷回 `/usr/share/v2ray/` 当「恢复」
- 不要在 LuCI 里把 `v2ray_location_asset` 改到别的闪存路径
- 不要为了省事 `opkg remove xray-core`：overlay 大头确实是 `/usr/bin/xray`（约 31MB），但运行中的二进制在 `/tmp/etc/passwall/bin/xray`，删包前要先有替代方案
- 固件升级后确认 `/etc/sysupgrade.conf` 仍包含 `/etc/init.d/v2ray-geo` 和 `/usr/lib/v2ray-geo/`

## 回滚

路由器本地备份：`/root/backup-v2ray-geo-20260828/`。回滚后仍须保持「闪存只有 xz、运行时在 RAM」，否则下一次 Geo 更新还会写满 overlay。

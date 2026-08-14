---
title: ToDesk 残留服务导致快切用户后鼠标几乎不能动
date: 2026-08-14
category: docs/solutions/best-practices
server: (适用所有 macOS)
module: macOS / ToDesk / Fast User Switching
problem_type: best_practice
component: tooling
severity: high
applies_when:
  - 锁定账户 A 再快切到账户 B 后，只有鼠标极卡、键盘正常
  - 锁屏界面鼠标同样卡，切回原账户又恢复
  - 以为已卸载 ToDesk，但 LaunchDaemon / 虚拟声卡 / Session Proxy 还在
tags: [todesk, macos, fast-user-switching, mouse-lag, leftover-daemon, virtual-audio]
---

# ToDesk 残留服务导致快切用户后鼠标几乎不能动

只把 `/Applications/ToDesk.app` 丢进废纸篓不算卸载。系统级 `ToDesk_Service`、挂在 LoginWindow 上的 `ToDesk_Session_Proxy`、以及 `ToDeskOutputDriver` 虚拟声卡都会留下来，并在每个用户会话里反复拉起。

## Context

2026-08-14 在 MacBook Air M5（macOS 26.5.2）上确认：`konghai` 不退出、锁定后再登 `xxk`，触控板几乎不能移动，键盘正常；锁小小空后锁屏仍然卡，切回 `konghai` 立刻恢复。卸载 App 后症状仍在。

本机查到：

- App 已不在 `/Applications`，但 `ToDesk_Service` / `ToDesk_Session_Proxy` 仍从废纸篓里的包运行
- LaunchAgent `com.youqu.todesk.desktop` 的 `LimitLoadToSessionType` 包含 `LoginWindow` 和 `Aqua`，`KeepAlive=true`
- 小小空会话 `gui/502` 每约 10 秒重试一次，失败于 `Unable to set current working directory ... /Applications/ToDesk.app`
- `ToDesk Virtual Audio` 曾是默认输出设备
- WindowServer 同时在报 `Cursor disabled: failed set_cursor_surface`

清干净 ToDesk 残留并重启后，**不退出 BetterAndBetter / iShot** 再登小小空，鼠标恢复正常。因此可以认定是 ToDesk 残留，不是辅助功能软件。

同一天在 `mac-mini` 上扫到完整安装仍在跑：`ToDesk_Service` 自 2026-07-21 起累计约 890 小时 CPU，并给 uid 501/503/505（`konghai` / `ziyi` / `coding`）各挂了一份服务。`mac-mini` 上的卸载因远程 sudo 需要本机密码，脚本已放到该机，待在图形会话里执行。

## Guidance

不要用「把 App 扔进废纸篓」判断 ToDesk 是否卸干净。用仓库脚本一次扫完并删掉服务、开机项、虚拟声卡和安装收据：

```bash
# 推荐：终端里直接 sudo（不要用图形密码框）
sudo /path/to/scripts/uninstall-todesk.sh --apply

# 只看残留、不改动
/path/to/scripts/uninstall-todesk.sh --dry-run
```

脚本若放在「下载」里，`osascript` 图形提权常会在密码通过后仍失败（TCC 不让特权进程读 Downloads），看起来像密码错了。用 `sudo` 即可。

脚本路径：`scripts/uninstall-todesk.sh`。

它只匹配优趣 ToDesk（`com.youqu.todesk` / `ToDesk.app`），不会删 Cursor / Notion Calendar 使用的 ToDesktop（`com.todesktop.*`）。

给朋友的机器：把该脚本拷过去，在那台 Mac 的终端运行第一行即可。纯 SSH、看不到被控屏时，改用 `--apply` 加 `sudo`。

卸完后重启一次再验证快切。只锁屏不重启，launchd 里的 disabled 空标签和 coreaudiod 缓存可能还在。

## Why This Matters

`ToDesk_Session_Proxy` 设计上要在锁屏和其它用户会话里截屏/注入指针。App 删了之后：

- 原用户会话里的旧进程还在废纸篓路径上活着
- 新用户 / 锁屏会话按 plist 去 `/Applications/ToDesk.app` 拉起，目录不存在就 KeepAlive 死循环
- 指针走 WindowServer 光标 surface，键盘不走，于是「只有鼠标死」

快切会让两套 GUI 加上远控代理同时活着，把这个问题放大。

## When to Apply

- 任何 macOS 上卸载 ToDesk，或怀疑 ToDesk 没卸干净
- 快切用户后鼠标卡、键盘正常，尤其锁屏也卡
- `ps` / `launchctl` 还能看到 `ToDesk_Service`、`ToDesk_Session_Proxy`、`com.youqu.todesk.*`

## Examples

判断没卸干净的信号：

```bash
ps aux | grep -E 'ToDesk_Service|ToDesk_Session_Proxy' | grep -v grep
launchctl print system | grep -i youqu
ls /Library/Audio/Plug-Ins/HAL/ToDeskOutputDriver.driver
```

本机清干净后的对照：进程无、HAL 无驱动、pkgutil 无 `com.youqu.todesk.*`、声音设备列表无 ToDesk Virtual Audio。`launchctl` 里若只剩 `=> disabled` 且没有对应 plist，不会再启动，重启后多半消失。

## Related

- 脚本：`scripts/uninstall-todesk.sh`
- 本机记录：`docs/operations/konghai-macbook-air.md`
- `mac-mini` 记录：`docs/operations/mac-mini.md`

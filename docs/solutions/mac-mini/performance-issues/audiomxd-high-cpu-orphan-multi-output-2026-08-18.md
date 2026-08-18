---
title: audiomxd 因残缺多输出设备和残留虚拟声卡而长期高 CPU
date: 2026-08-18
category: docs/solutions/mac-mini/performance-issues
server: mac-mini
module: mac-mini / Core Audio / audiomxd
problem_type: performance_issue
component: tooling
symptoms:
  - "活动监视器里 audiomxd（看起来像 audiomad）长期占 70% 以上 CPU"
  - "卸掉某个远控虚拟声卡并重启后才开始飙，coreaudiod 本身几乎不占 CPU"
  - "声音设备列表里还有「多输出设备」或已卸载软件的虚拟声卡，且它是默认输入"
root_cause: incomplete_setup
resolution_type: config_change
severity: medium
related_components:
  - macos-core-audio
  - virtual-audio-hal
tags:
  - mac-mini
  - audiomxd
  - coreaudiod
  - virtual-audio
  - blackhole
  - splashtop
  - todesk
---

# audiomxd 因残缺多输出设备和残留虚拟声卡而长期高 CPU

## Problem

macOS 的 `/usr/libexec/audiomxd`（Audio Mixer）在设备图不完整时会单线程空转。活动监视器里名字容易看成 `audiomad`。2026-08-15 卸 ToDesk 并重启后，mac-mini 上这个进程连续约 3.5 天占 **72% CPU**。

## Symptoms

- `ps` 里 `_audiomxd` 的 `/usr/libexec/audiomxd` 长期 `R`，累计 CPU 可达数千分钟；`coreaudiod` 接近 0%
- 默认输出正常（这里是 LG UltraFine），但默认输入是某个已没 App 的虚拟声卡
- 「音频 MIDI 设置」里有「多输出设备」，子设备包含已经不存在的 BlackHole / 同类 loopback
- `/Library/Audio/Plug-Ins/HAL/` 里还能看到远控软件的 `.driver`，`/Applications` 里对应 App 已不在

## What Didn't Work

- 只查 ToDesk 残留不够。`ToDeskOutputDriver.driver` 和当前 `SystemSettings.plist` 里的 ToDesk 键都已经在 8 月 15 日清掉了，备份 `SystemSettings.plist.bak.20260815` 才能看到当时删过什么。
- 远程 SSH 没有免密 sudo，图形 `osascript with administrator privileges` 会报「管理员用户名或密码不正确」（和卸 ToDesk 同一条 TCC 坑）。必须在本机终端 `sudo /tmp/... --apply`。
- 只改「默认输入」做不到：Mac mini 没有内置麦克风，Splashtop 是当时唯一输入设备，不卸 HAL 系统还会选它。

## Solution

1. 备份 `/Library/Preferences/Audio/com.apple.audio.{System,Device}Settings.plist`。
2. 从 `SystemSettings.plist` 删掉 `MetaDevice.~:AMS2_StackedOutput:0`、`Meta_UIDList` 里对应项，以及首选设备里的 BlackHole / Splashtop UID。
3. 删除残留 HAL 和指向已删除 App 的 launchd：
   - `/Library/Audio/Plug-Ins/HAL/SplashtopRemoteSound.driver`
   - `/Library/LaunchDaemons/com.splashtop.streamer-daemon.plist`
   - `/Library/LaunchAgents/com.splashtop.streamer.plist`
4. `sudo killall coreaudiod audiomxd`，等若干秒让 launchd 拉起新进程。

仓库脚本：`scripts/fix-mac-mini-audiomxd.sh`。

```bash
# 先扫描
./scripts/fix-mac-mini-audiomxd.sh --dry-run

# 本机终端提权执行（不要走「下载」目录的图形密码框）
sudo /tmp/fix-mac-mini-audiomxd.sh --apply
```

2026-08-18 13:51 在 mac-mini 执行后：新 `audiomxd` 为 **0.0%**，设备列表只剩 LG UltraFine（默认输出）和 Mac mini Speakers，HAL 只剩系统自带 `ParrotAudioPlugin.driver`。不要删 Parrot，那是 Apple 插件。

回滚：还原同目录下 `*.bak.20260818-135146`，再 `sudo killall coreaudiod audiomxd`。虚拟声卡本身要重装对应软件。

## Why This Works

`audiomxd` 负责多设备混音和漂移补偿。Stacked「多输出设备」一边是还在的内置喇叭，一边是已经卸掉的 BlackHole 时，混音线程会一直重试同步。卸 ToDesk 后的重启只是触发 Core Audio 重建设备图，把这个残缺图和「只剩 Splashtop 当默认输入」（44.1 kHz vs 输出 48 kHz）暴露出来，不是 ToDesk 驱动没卸干净。

## Prevention

- 卸远控 / 虚拟声卡后不要只看 App 是否还在。对照：`ps` 无对应进程、`/Library/Audio/Plug-Ins/HAL/` 无其 `.driver`、`system_profiler SPAudioDataType` 无其设备名、「音频 MIDI 设置」里没有指向幽灵设备的聚合 / 多输出。
- 同类残留见 ToDesk：[todesk-incomplete-uninstall-fast-user-switch-mouse-lag-2026-08-14.md](../../best-practices/todesk-incomplete-uninstall-fast-user-switch-mouse-lag-2026-08-14.md)。
- `launchctl` 里只剩 `=> disabled` 且没有对应 plist 的空标签，重启后多半自己消失，不必再删。

## Related Issues

- [ToDesk 残留服务导致快切用户后鼠标几乎不能动](../../best-practices/todesk-incomplete-uninstall-fast-user-switch-mouse-lag-2026-08-14.md)
- 操作记录：`docs/operations/mac-mini.md`（2026-08-18 13:45 排查、13:52 修复）

# nyh-prod-2026 运维操作时间线

## 2026-11-10 14:05–14:25 CST - 纳入仓库，卸载云盾，Debian 12 原地升级到 13

- 服务器：`nyh-prod-2026`（`root@8.217.145.133`，阿里云香港轻量服务器，实例 `a9670f44600c4671a95c2a46a795657a`）
- 操作人：`Claude`（用户要求）
- 原因：用户新购这台机器替代 `nyh-prod`，要求先能用公钥登录，再升级到 Debian 13。
- 影响：空机器，没有业务；共重启 2 次。
- 备份：
  - 快照 `s-j6cf8ldl9p1wznd46hrm`（`debian12-before-upgrade`，升级前）
  - 服务器：`/root/.ssh/authorized_keys.bak.20261110`（原为空）、`/root/grub.default.bak`、`/root/grub.default.pre-efi.bak`、`/root/sources.list.bookworm.bak`
  - 本机：`~/.ssh/config.bak.20261110`
- 回滚方式：`aliyun swas-open stop-instance` → `reset-disk --disk-id d-j6c31h3s5ffawxajzmpq --snapshot-id s-j6cf8ldl9p1wznd46hrm` → `start-instance`（`--profile default --biz-region-id cn-hongkong`），回滚后 `ssh-keygen -R 8.217.145.133`。回滚后云盾会回来。
- 做了什么：
  1. 本机公钥（`id_ed25519` / root / `ecs-user` / `admin` 等组合）全部 `Permission denied`：镜像里 root 的 `authorized_keys` 是空的。在 aliyun `default` profile 下找到这台实例，云助手在线，用 `swas-open run-command` 把 `~/.ssh/id_ed25519.pub` 写入 `/root/.ssh/authorized_keys`。
  2. 本机 `~/.ssh/config` 追加 `Host nyh-prod-2026`。
  3. 按手册 2.2 节核对，镜像特征完全一致：`grub-pc` + `grub-efi-amd64-bin/signed`，无 `grub-efi-amd64`；`cloud-init` 被 hold；`GRUB_SERIAL_COMMAND="serial --speed=115200n8"`；云盾 `AliSecGuard` 模块已加载。
  4. 打快照 `debian12-before-upgrade`。
  5. 卸载云盾（用户确认）：加开机参数 `systemd.mask=aegis.service module_blacklist=AliSecGuard` 重启 → 跑官方 `uninstall.sh` / `quartz_uninstall.sh` → 删残留 → 还原 `/etc/default/grub`。
  6. `systemd-run --unit=upgrade-trixie` 后台跑 `/root/upgrade-trixie.sh`（日志 `/root/upgrade-trixie.log`），`Result=success`，无 `E:` / `dpkg: error`。
  7. 修 grub：预设 debconf（ESP `/dev/disk/by-id/virtio-j6c31h3s5ffawxajzmpq-part2`、`force_efi_extra_removable`），修正 `GRUB_SERIAL_COMMAND`，`grub-pc` 换成 `grub-efi-amd64`，`grub-install --target=x86_64-efi --uefi-secure-boot --force-extra-removable`，`update-grub`。
  8. 重启前检查全部通过后重启。
  9. 打基线快照 `s-j6ch07g86tunb409g1tf`（`debian13-baseline-20261110`）。
- 验证：
  - 重启前：模块 `2.12-9+deb13u2`、`bli.mod` 存在；ESP 两处 shim 哈希 `e103c5d02657`、grub 哈希 `425ffb5b84e8` 均与包内签名文件一致；只缺允许的 `ieee1275_fb` / `vbe` / `vga`；只装 `grub-efi-amd64`，无 hold、无半安装包；`sshd -t` 通过；cloud-init `25.1.4` 能 import。
  - 重启后一次开机成功：`13.7`、`6.12.116+deb13-amd64`、`systemctl is-system-running` = `running`、无失败 unit、`cloud-init status: done`、`eth0 routable`、时钟已同步、云助手 `active`、无 `AliYunDun` 进程。`journalctl -p err` 只有手册列出的可忽略项（RETBleed、AF_VSOCK、dhclient `/bin/true`）。
- 待办：
  - 确认稳定后删除快照 `debian12-before-upgrade`。
  - 上线业务前：关 LLMNR（5355 对公网监听）、配防火墙、决定是否保留 root 直登。

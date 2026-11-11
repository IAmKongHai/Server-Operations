# 阿里云轻量服务器 Debian 12 → 13 原地升级操作手册

> **归档说明（2026-11-11）**：迁自已废弃的 `DigitalOcean` 仓库（原 `docs/阿里云轻量服务器-Debian12原地升级13-操作手册.md`）；`qingfan-prod`、`nyh-prod-2026` 都按本手册升级。

> 2026-11-09 在香港轻量服务器 `8.210.153.241`（实例 `68c002bd79054bd2bdaffdfef2321cce`）上实际跑通，结果是 Debian 13.7 + 内核 6.12.116。
> 前两次升级后都开不了机，第三次按本手册操作后成功。阿里云轻量服务器的系统镜像里没有 Debian 13，只能在 Debian 12 上原地升级。

---

## 0. 一句话结论

**阿里云的 Debian 12 镜像里装的是 BIOS 版的 `grub-pc`，没有 `grub-efi-amd64`，可机器实际是 UEFI 启动。**
直接 `apt full-upgrade` 到 trixie 之后，`grub.cfg` 会用 2.12 版重新生成（里面有 `insmod bli`），但 `/boot/grub/x86_64-efi/` 下的模块没人更新，还停在 2.06。**重启后机器卡在 UEFI 固件菜单**，SSH、云助手都连不上。

**解决办法：升级完、重启前，把 `grub-pc` 换成 `grub-efi-amd64`，再执行一次 EFI 的 `grub-install`，检查通过后再重启。**

---

## 1. 踩过的坑（排查过程，供判断用）

| 现象 | 实际含义 |
|---|---|
| 重启后 TCP 22 能连上，但 `Connection timed out during banner exchange` | **不代表系统起来了**，系统根本没进 Linux。端口应该是阿里云前端代为应答的。不要据此判断是 sshd 或内核的问题 |
| 云助手 `run-command` 一直 Pending，`ErrorCode: ClientNotRunning` | 系统没起来 |
| VNC 救援连接显示 `Alibaba Cloud ECS / pc-i440fx-2.1` 的 UEFI 菜单（Device Manager / Boot Manager…） | 固件找不到能用的引导程序，**是 grub 的问题** |
| 在 VNC 里从文件启动 `shimx64.efi`，报 `file '/boot/grub/x86_64-efi/bli.mod' not found` | grub 引导程序和 `/boot/grub/x86_64-efi` 下的模块版本不一致，这就是根因 |
| `error: the argument '--speed=115200n8' requires an integer` | 阿里云镜像里 `GRUB_SERIAL_COMMAND` 写法有误，只是警告，但顺手修掉 |

排查时先后怀疑过两个原因，**都被证实不是根因**：
- 云盾 Aegis 的 `AliSecGuard` 内核模块：卸掉之后照样开不了机
- 6.12 新内核和老机型不兼容：最后正是用 6.12 启动成功的

**教训：第一次重启失败后，应该马上让用户开 VNC 救援连接看屏幕，不要靠 SSH 现象去猜。**

---

## 2. 前置准备

### 2.1 本机 aliyun CLI
- 轻量服务器命令需要插件：`aliyun plugin install --names aliyun-cli-swas-open`
- 参数名用 `--biz-region-id`，不是 `--region-id`
- **注意 profile**：`aliyun configure set --profile xxx` 会把当前 profile 切换过去。配完后检查 `~/.aliyun/config.json` 里的 `current`，确认没有把原来的 default 顶掉
- RAM 用户至少需要 `AliyunSWASFullAccess` 权限（快照、回滚、启停、云助手、VNC 都用它）

```bash
P=<profile>; R=cn-hongkong; IID=<轻量实例ID>
aliyun swas-open list-instances --profile $P --biz-region-id $R          # 拿到实例 ID、公网 IP、状态
aliyun swas-open list-disks --profile $P --biz-region-id $R --instance-id $IID   # 拿到系统盘 DiskId
```

### 2.2 先确认是同一种镜像（不一样的话本手册不一定适用）
```bash
ssh root@<IP> 'cat /etc/debian_version; dpkg -l | grep -E "grub|shim" | awk "{print \$1,\$2,\$3}"; ls -R /boot/efi/EFI; efibootmgr | head -8; grep SERIAL /etc/default/grub; apt-mark showhold'
```
预期特征（跟本次一样）：
- 装了 `grub-pc`、`grub-efi-amd64-bin`、`grub-efi-amd64-signed`、`grub-cloud-amd64`、`shim-signed`，**没有 `grub-efi-amd64`**
- `/boot/efi/EFI/` 下有 `BOOT/` 和 `debian/`，启动项 `debian` 指向 `\EFI\debian\shimx64.efi`
- `apt-mark showhold` 显示 `cloud-init` 被 hold 了
- `GRUB_SERIAL_COMMAND="serial --speed=115200n8"`

### 2.3 **必须先打快照**
```bash
aliyun swas-open create-snapshot --profile $P --biz-region-id $R --disk-id <DiskId> --snapshot-name debian12-before-upgrade
# 等到状态变成 accomplished（注意是小写，脚本里不要匹配大写的 Accomplished）
aliyun swas-open list-snapshots --profile $P --biz-region-id $R --snapshot-ids '["<SnapshotId>"]' | grep -E '"(Status|Progress)"'
```

---

## 3. （可选）卸载云盾 Aegis

**云盾不是开不了机的根因**，卸不卸由机主决定。本次卸掉的理由：
- 它的 `AliSecGuard` 内核模块只为 6.1 内核编译过，到了 6.12 会改用 eBPF 去 hook，这种情况没验证过
- 它的自保护会锁住自己的文件，后续想处理时会很麻烦

**如果要卸**：
- 在云安全中心控制台点"暂停保护"**没用**，内核自保护照样生效，卸载脚本会报 `Operation not permitted`，`systemctl disable` 会报 `Access denied`
- 有效做法是用开机参数让它这一次不启动，然后再卸载：

```bash
# 1) 加临时开机参数，然后重启（此时还是 Debian 12，可以放心重启）
ssh root@<IP> 'cp -a /etc/default/grub /root/grub.default.bak && sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"\"/GRUB_CMDLINE_LINUX_DEFAULT=\"systemd.mask=aegis.service module_blacklist=AliSecGuard\"/" /etc/default/grub && update-grub && grep -c "systemd.mask=aegis" /boot/grub/grub.cfg && systemctl reboot'

# 2) 重启后执行官方卸载脚本，清理残留文件，恢复 grub 配置
ssh root@<IP> 'mkdir -p /root/aegis-uninstall && cd /root/aegis-uninstall \
  && curl -fsS -o uninstall.sh http://update2.aegis.aliyun.com/download/uninstall.sh \
  && curl -fsS -o quartz_uninstall.sh http://update2.aegis.aliyun.com/download/quartz_uninstall.sh \
  && bash uninstall.sh > run.log 2>&1; bash quartz_uninstall.sh >> run.log 2>&1
  rm -rf /usr/local/aegis
  rm -f /etc/systemd/system/aegis.service
  rm -f /etc/systemd/system/multi-user.target.wants/aegis.service
  systemctl daemon-reload
  cp -a /root/grub.default.bak /etc/default/grub && update-grub
  ls /usr/local/aegis; pgrep -l AliYunDun; grep -c "aegis\|AliSec" /boot/grub/grub.cfg'
# 预期：目录不存在、没有 AliYunDun 进程、grub.cfg 里匹配数为 0
# （find 结果里的 aegis128*.ko 是 Linux 自带的加密模块，跟云盾无关）
```
卸载后，云安全中心里这台机器会显示离线或未受保护，这是正常的。

---

## 4. 升级（后台运行，**不自动重启**）

用 `systemd-run` 在后台跑，避免 SSH 断开导致 dpkg 中途被打断：

```bash
ssh root@<IP> 'cp -a /etc/apt/sources.list /root/sources.list.bookworm.bak
cat > /root/upgrade-trixie.sh <<"EOF"
#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
apt-mark unhold cloud-init          # 镜像把 cloud-init hold 在 23.2，不解除就会和 Python 3.13 不匹配
apt-get update
apt-get "${APT_OPTS[@]}" full-upgrade
sed -i "s/bookworm/trixie/g" /etc/apt/sources.list     # 阿里云内网镜像 mirrors.cloud.aliyuncs.com 有 trixie
apt-get update
apt-get "${APT_OPTS[@]}" upgrade --without-new-pkgs
apt-get "${APT_OPTS[@]}" full-upgrade
apt-get -y autoremove
echo UPGRADE_DONE
EOF
chmod +x /root/upgrade-trixie.sh
systemd-run --unit=upgrade-trixie --property=StandardOutput=file:/root/upgrade-trixie.log --property=StandardError=file:/root/upgrade-trixie.log /root/upgrade-trixie.sh'
```
在本机等它跑完（用 `run_in_background`，大约 5～10 分钟）：
```bash
until ssh root@<IP> 'grep -q UPGRADE_DONE /root/upgrade-trixie.log && exit 0; s=$(systemctl show -p ActiveState --value upgrade-trixie); [ "$s" = failed ] || [ "$s" = inactive ]'; do sleep 20; done
ssh root@<IP> 'systemctl show -p Result upgrade-trixie; grep -E "^(E:|dpkg: error)" /root/upgrade-trixie.log'
```

> ⛔ **到这一步千万不要重启。** 此时 `/boot/grub/x86_64-efi/bli.mod` 还不存在，重启必然开不了机。

---

## 5. 修 grub（关键步骤）

```bash
ssh root@<IP> 'bash -s' <<'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive
# 1) 预设 debconf：同时写入 /EFI/BOOT 回退路径；安装目标为 ESP
#    install_devices 的值以 2.2 节 debconf-show grub-pc 看到的 grub-efi/install_devices 为准（形如 /dev/disk/by-id/virtio-<盘ID>-part2）
ESP_DEV=$(debconf-show grub-pc | awk -F": " "/grub-efi\/install_devices/{print \$2}")
echo "ESP_DEV=$ESP_DEV"
echo "grub-efi-amd64 grub2/force_efi_extra_removable boolean true" | debconf-set-selections
echo "grub-efi-amd64 grub-efi/install_devices multiselect $ESP_DEV" | debconf-set-selections
# 2) 修正串口参数写法
sed -i 's/^GRUB_SERIAL_COMMAND=.*/GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"/' /etc/default/grub
# 3) 把 grub-pc 换成 grub-efi-amd64（会自动卸掉 grub-pc；grub-cloud-amd64 只依赖 *-bin 包，不受影响）
apt-get install -y -o Dpkg::Options::=--force-confold grub-efi-amd64
# 4) 再显式装一次（走签名链 shim，并同步写入 /EFI/BOOT），然后重新生成 grub.cfg
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --uefi-secure-boot --force-extra-removable
update-grub
EOF
```
> 如果 `ESP_DEV` 是空的，手动用 `ls -l /dev/disk/by-id/ | grep part2` 找 ESP 分区（vda2，vfat，挂载在 /boot/efi）。

---

## 6. 重启前检查（**全部通过才能重启**）

```bash
ssh root@<IP> 'bash -s' <<'EOF'
echo "== 1. 模块版本必须是 2.12"; grep -E "^grub_(version|package_version)=" /boot/grub/x86_64-efi/modinfo.sh
echo "== 2. bli.mod 必须存在"; ls -la /boot/grub/x86_64-efi/bli.mod
echo "== 3. ESP 两处的 shim/grub 必须和软件包里的签名文件哈希一致"
for f in /boot/efi/EFI/BOOT/BOOTX64.EFI /boot/efi/EFI/debian/shimx64.efi /boot/efi/EFI/BOOT/grubx64.efi /boot/efi/EFI/debian/grubx64.efi; do echo "$f $(sha256sum < $f | cut -c1-12)"; done
echo "shim pkg $(sha256sum < /usr/lib/shim/shimx64.efi.signed | cut -c1-12)   grub pkg $(sha256sum < /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed | cut -c1-12)"
echo "== 4. grub.cfg 里 insmod 的模块都要存在"
for m in $(grep -oE "insmod [a-z0-9_]+" /boot/grub/grub.cfg | awk "{print \$2}" | sort -u); do [ -f /boot/grub/x86_64-efi/$m.mod ] && echo "ok $m" || echo "MISSING $m"; done
echo "== 5. 包状态"; dpkg -l | grep -E "^ii\s+grub-(pc|efi-amd64) "; apt-mark showhold; dpkg -l | grep -vE "^(ii|rc)" | tail -n +6
echo "== 6. 其它"; sshd -t && echo sshd-ok; cloud-init --version; python3 -c "import cloudinit.cmd.main" && echo cloudinit-import-ok
grep -m1 -E "^\s+linux\s" /boot/grub/grub.cfg | cut -c1-60; grep -n serial /boot/grub/grub.cfg | head -2
EOF
```
判断标准：
1. `grub_package_version="2.12-…+deb13u…"`
2. `bli.mod` 存在
3. `BOOTX64.EFI` 和 `debian/shimx64.efi` 的哈希都等于 shim 包的；两个 `grubx64.efi` 的哈希都等于 grub 签名包的
4. 只有 `ieee1275_fb`、`vbe`、`vga` 可以显示 MISSING。它们在 `load_video` 函数的 else 分支里，grub 2.12 支持 `all_video`，这个分支不会执行。**除这三个以外，出现任何 MISSING 都不能重启**
5. 只装了 `grub-efi-amd64`，没有 `grub-pc`；没有 hold 的包；没有半安装状态的包
6. sshd 配置有效；cloud-init 是 25.x 版，能正常 import；默认启动项是 `vmlinuz-6.12…`

---

## 7. 重启与验证

```bash
ssh root@<IP> 'systemctl reboot'
# 正常情况下 1 分钟内就能 SSH 登录
until ssh -o ConnectTimeout=8 -o BatchMode=yes root@<IP> 'test $(cut -d. -f1 /proc/uptime) -lt 900'; do sleep 6; done
ssh root@<IP> 'cat /etc/debian_version; uname -r; systemctl is-system-running; systemctl --failed --no-legend; cloud-init status; networkctl | head -4; timedatectl | grep synchronized; journalctl -b -p err --no-pager | tail'
```
预期结果：`13.7`、`6.12.x+deb13-amd64`、`running`、`cloud-init status: done`、`eth0 routable`。

**以下几条是正常现象，可以忽略**：
- `systemctl status cloud-init` 显示 `Unit cloud-init.service could not be found`：cloud-init 25.x 改了服务单元的名字，用 `cloud-init status` 看状态
- `dhclient … execve (/bin/true …): Permission denied`：cloud-init 开机早期临时获取 DHCP 时被 AppArmor 拦了一下。网卡由 systemd-networkd 管理，不受影响
- `systemd-ssh-generator … AF_VSOCK`：虚拟机没有 vsock，跟 SSH 登录无关
- `RETBleed: WARNING`：CPU 漏洞缓解措施的提示

验证通过后**打一个 Debian 13 基线快照**；确认不再需要回滚后，再删掉 Debian 12 的快照。

---

## 8. 万一还是开不了机：回滚

```bash
aliyun swas-open stop-instance --profile $P --biz-region-id $R --instance-id $IID
# 机器卡在 UEFI 菜单时不响应正常关机，会在 Stopping 状态停约 3 分钟，之后平台会强制关机。轮询等到 "Status": "Stopped"
aliyun swas-open reset-disk --profile $P --biz-region-id $R --disk-id <DiskId> --snapshot-id <SnapshotId>
aliyun swas-open start-instance --profile $P --biz-region-id $R --instance-id $IID
ssh-keygen -R <IP>    # 回滚或重装后 host key 可能会变
```
注意：快照如果是在卸载云盾**之前**打的，回滚后云盾也会回来，需要按第 3 节再卸一次。

想看屏幕：控制台 → 实例 → 远程连接 → **救援连接（VNC）**。这个入口不依赖系统里的任何服务。

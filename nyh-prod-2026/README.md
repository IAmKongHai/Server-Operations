# nyh-prod-2026

用户 2026-11-09 在自己实名的阿里云账号下新购的香港轻量应用服务器，**用于替代 `nyh-prod`**。2026-11-10 纳入本仓库，从 Debian 12 原地升级到 Debian 13，并重装了适配 6.12 内核的云盾。目前还是空机器，没有任何业务；迁移完成后按生产对待。

## 连接

```bash
ssh nyh-prod-2026   # = ssh root@8.217.145.133，用 ~/.ssh/id_ed25519
```

| 项目 | 值 |
| --- | --- |
| 公网 IP | `8.217.145.133` |
| 云厂商 / 地域 | 阿里云**轻量应用服务器**（SWAS），`cn-hongkong` |
| 实例 | `a9670f44600c4671a95c2a46a795657a`（控制台名 `Debian-uccj`），套餐 `swas.s.c4m16s80b1.linux`，到期 `2027-11-10` |
| aliyun CLI | `--profile default`（不是 `new-hk`，那是 qingfan-prod 所在账号） |
| 系统盘 | `d-j6c31h3s5ffawxajzmpq`，ESSD 80G |
| 主机名 | `iZj6c31h3s5ffawxaon0toZ` |
| 系统 | Debian 13.7 (trixie)，内核 `6.12.116+deb13-amd64`，UEFI 启动（`grub-efi-amd64` 2.12 + shim） |
| 规格 | 4 vCPU / **16G 内存**（套餐 c4m16；`free -h` 显示 `14Gi` 是因为扣掉了 crashkernel 预留的 256M 和固件 / PCI 地址空间，再按 GiB 取整）/ 无 swap / 根分区 79G ext4（`/dev/vda3`），ESP `/dev/vda2` |
| 时区 | `Asia/Shanghai`（CST） |
| SSH | 只允许公钥（`PasswordAuthentication no`），root 可直接登录 |

### root 的 `authorized_keys`

| 注释 | 用途 |
| --- | --- |
| `konghai@konghai.me` | 本机 konghai 的 `~/.ssh/id_ed25519`，2026-11-10 经云助手写入（原文件为空） |

另有镜像自带用户 `admin`（未配置密钥）。

## 快照

| 快照 ID | 名称 | 说明 |
| --- | --- | --- |
| `s-j6cf8ldl9p1wznd46hrm` | `debian12-before-upgrade` | 升级前，**云盾还在**；确认 Debian 13 稳定后可删 |
| `s-j6ch07g86tunb409g1tf` | `debian13-baseline-20261110` | 升级完成、**还没重装云盾**时的基线（之后重装了云盾，见下） |

## 现状

- 云盾 Aegis：2026-11-10 升级后用官方免密钥脚本 `http://update2.aegis.aliyun.com/download/install.sh` 重装，客户端 `aegis_11_37`，`aegis.service` enabled，开机自动拉起。在 6.12 内核上**不加载 `AliSecGuard` 内核模块**，改用 eBPF 挂钩（`AliYunDunMonitor` 持有约 89 个 bpf fd），内核 `tainted=0`。云安全中心显示 `online`。
  - 以后升级内核，客户端会按新内核自己选择挂钩方式，不需要重装；升级后检查 `systemctl is-active aegis` 和云安全中心在线状态即可。
  - 如果又要卸载：它有内核自保护，按升级手册第 3 节用开机参数 `systemd.mask=aegis.service` 绕过后再卸。
- 云助手 `aliyun.service` 保留，用于免 SSH 应急执行命令。
- 对外监听：`22`（sshd）、`5355`（systemd-resolved 的 LLMNR，镜像默认）。上线业务前建议关掉 LLMNR 并配好轻量服务器防火墙。
- 回环：`25`（exim4）、`53`（resolved）。

## 升级参考

升级过程完全按 `/Users/konghai/Code/Project/DigitalOcean/docs/阿里云轻量服务器-Debian12原地升级13-操作手册.md`，记录见 [`docs/operations/nyh-prod-2026.md`](../docs/operations/nyh-prod-2026.md)。

**这类机器以后 apt 升级 grub 后不需要额外处理**：现在装的已经是 `grub-efi-amd64`，包脚本会自动更新 ESP 里的引导程序和模块。

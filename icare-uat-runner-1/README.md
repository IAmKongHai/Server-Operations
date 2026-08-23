# icare-uat-runner-1

Azure UAT 原构建 VM。承接 `iCare-backend` `Build Azure UAT Images` / migrate-roll，以及 frontend `Deploy MAS to Azure UAT`；同机另跑 wait slot `icare-2-uat-wait`（**不在** runner group `icare-2-uat`）。

按生产对待：改 runner / Docker / `/var/cache/buildx` / SSH 前先备份并确认。挂了会挡住 Azure UAT 发版。

日常操作时间线：[`docs/operations/icare-uat-runner-1.md`](../docs/operations/icare-uat-runner-1.md)

## 连接

```bash
ssh icare-uat-runner-1
# 兼容旧别名
ssh icare-uat-runner
```

| 项目 | 值 |
| --- | --- |
| SSH 别名 | `icare-uat-runner-1`（兼容 `icare-uat-runner`） |
| 内网 IP | `10.30.6.4/24`，网关 `10.30.6.1` |
| SSH 用户 | `icareadmin`（sudo + docker） |
| 主机名 | `icare-2-uat-ci-runner` |
| 区域 / 资源组 | `southeastasia` / `iCare-2.0-UAT` |
| Azure SKU | `Standard_B2s`（2 vCPU / 3.8 GiB，无 swap） |
| OS | Microsoft Azure Linux 3.0（`azurelinux` 3.0.20260706，kernel `6.6.143.1-1.azl3`） |
| 时区 | UTC |
| 根盘 | ext4 `/dev/sda3` 98G（盘点时约 35G used / 60G avail） |
| `/tmp` | tmpfs **2.0G**（Buildx cache **禁止**写这里） |

无独立公网 SSH；从本机走已有跳板 / VPN 到 `10.30.6.0/24`。

## GitHub Actions runner

| Slot | 目录 | systemd | GitHub 名 | Group / pool | Labels |
| --- | --- | --- | --- | --- | --- |
| 构建 | `/opt/actions-runner` | `actions.runner.cypressoai.icare-2-uat-runner` | `icare-2-uat-runner`（agentId 34） | group `icare-2-uat`（pool 4） | `self-hosted`, `Linux`, `X64`, `azure`, `uat` |
| Wait | `/opt/actions-runner-uat-wait` | `actions.runner.cypressoai.icare-2-uat-wait` | `icare-2-uat-wait`（agentId 37） | **Default**（pool 1） | `self-hosted`, `Linux`, `X64`, `uat-wait` |

Wait slot 必须留在 Default，不能进 `icare-2-uat`。frontend wait job 需要本机 `gh`（已装 2.97.0）。

工作目录：各 slot 下 `_work`。Listener 用户一律 `icareadmin`。

## Docker / Buildx

| 项目 | 值 |
| --- | --- |
| Docker | `25.0.3`，root `/var/lib/docker`，overlay2 |
| Azure CLI | `2.88.0` |
| Python | `3.12.9` |
| Buildx cache | `/var/cache/buildx` 属主 `icareadmin:icareadmin` `755` |
| 当前 slug | `icare-backend-uat`、`icare-backend-ecom-uat`、`icare-backend-sup-uat` |

workflow（CYP-2046）会 `mkdir -p /var/cache/buildx`。`/var/cache` 属 root，目录必须事先存在。不要把 cache 放到 `/tmp`（本机 tmpfs 只有 2G）。

## 操作边界

- 只读：`ls` / `ps` / `systemctl status` / `docker version` / `df`。
- 需要确认：重启 runner service、重启 Docker、删 `/var/cache/buildx`、改防火墙 / SSH。
- 不要 `./svc.sh install` 再装一份，以免和现有 systemd unit 双开。
- 不要在这台 2 核 / 4G 机上叠日常 PR CI。

## 相关

- 突发扩容机：[`../icare-uat-runner-2/README.md`](../icare-uat-runner-2/README.md)
- Runner 池：[`../docs/runbooks/ci-runner-pools.md`](../docs/runbooks/ci-runner-pools.md)

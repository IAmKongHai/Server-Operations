# icare-uat-runner-2

CYP-2263 临时 D8s_v5 burst VM。与原机同属 runner group `icare-2-uat`，用来加速 UAT 镜像构建；**不跑** `uat-wait` slot。

按生产对待：改 runner / Docker / `/var/cache/buildx` 前先备份并确认。新机上线漏预建 cache 目录会把整个 UAT 发版挡在 `Prepare backend build cache`。

日常操作时间线：[`docs/operations/icare-uat-runner-2.md`](../docs/operations/icare-uat-runner-2.md)

## 连接

```bash
ssh icare-uat-runner-2
```

| 项目 | 值 |
| --- | --- |
| SSH 别名 | `icare-uat-runner-2` |
| 内网 IP | `10.30.6.5/24`，网关 `10.30.6.1` |
| SSH 用户 | `icareadmin`（sudo + docker） |
| 主机名 | `icare-2-uat-ci-runner-2` |
| 区域 / 资源组 | `southeastasia` / `ICARE-2.0-UAT` |
| Azure SKU | `Standard_D8s_v5`（8 vCPU / 31 GiB，无 swap） |
| OS | Microsoft Azure Linux 3.0（`azurelinux` 3.0.20260706，kernel `6.6.143.1-1.azl3`） |
| 时区 | UTC |
| 根盘 | ext4 `/dev/sda3` 98G（盘点时约 16G used / 79G avail） |
| `/tmp` | tmpfs **16G**（仍不要把 Buildx cache 写这里，和 CYP-2046 约定一致） |

无独立公网 SSH；从本机走已有跳板 / VPN 到 `10.30.6.0/24`。

## GitHub Actions runner

| Slot | 目录 | systemd | GitHub 名 | Group / pool | Labels |
| --- | --- | --- | --- | --- | --- |
| 构建 | `/opt/actions-runner` | `actions.runner.cypressoai.icare-2-uat-runner-2` | `icare-2-uat-runner-2`（agentId 39） | group `icare-2-uat`（pool 4） | `self-hosted`, `Linux`, `X64`, `azure`, `uat` |

本机 **没有** wait slot，也 **没有** `gh`。frontend `Wait for backend UAT` 必须继续落在 `icare-uat-runner-1` 的 `icare-2-uat-wait`。

## Docker / Buildx

| 项目 | 值 |
| --- | --- |
| Docker | `25.0.3`，root `/var/lib/docker`，overlay2 |
| Azure CLI | `2.89.1` |
| Python | `3.12.9` |
| `gh` | **未安装** |
| Buildx cache | `/var/cache/buildx` 属主 `icareadmin:icareadmin` `755`（2026-08-23 补齐） |

上线漏了 `/var/cache/buildx` 时，`mkdir -p` 会 Permission denied。复盘：[`docs/solutions/icare-uat-runner-2/workflow-issues/buildx-cache-dir-missing-on-new-uat-runner-2026-08-23.md`](../docs/solutions/icare-uat-runner-2/workflow-issues/buildx-cache-dir-missing-on-new-uat-runner-2026-08-23.md)

新 UAT burst 机 checklist：

1. 预建 `/var/cache/buildx`，属主 `icareadmin`，权限 `755`
2. `icareadmin` 在 `docker` 组，`docker version` 免 sudo
3. 只有构建职责时不要装 wait slot、不要进 Default 以外的错组
4. 不要假设原机有的目录新机也有

## 操作边界

- 只读：`ls` / `ps` / `systemctl status` / `docker version` / `df`。
- 需要确认：重启 runner service、重启 Docker、删 cache、改防火墙 / SSH、关机（临时 burst 机）。
- 有 `Runner.Worker` 时不要 prune Docker / 删 `_work`。
- 不要 `./svc.sh install` 再装一份。

## 相关

- 原机：[`../icare-uat-runner-1/README.md`](../icare-uat-runner-1/README.md)
- Runner 池：[`../docs/runbooks/ci-runner-pools.md`](../docs/runbooks/ci-runner-pools.md)

---
title: backend SonarQube 扫描在 mas-go-dev-ci-1 上失败 —— gnupg2-minimal 缺 dirmngr 无法拉 SonarSource 公钥
date: 2026-06-10
last_updated: 2026-06-10
category: docs/solutions/mas-go-dev/integration-issues
server: mas-go-dev
module: iCare CI / GitHub Actions self-hosted runner (mas-go-dev-ci-1)
problem_type: integration_issue
component: tooling
symptoms:
  - "develop 分支 backend 的 SonarQube Scan step 在 mas-go-dev-ci-1（x86 Linux）上失败，Go 测试本身全过"
  - "CI 日志：gpg: keyserver receive failed: No dirmngr"
  - "CI 日志：Action failed: Failed to import SonarSource public key from all keyservers"
  - "同一份 workflow 的 main 版本（Sonar action @v6）在同一台机器上从不报此错"
root_cause: missing_dependency
resolution_type: dependency_update
severity: medium
tags: [sonarqube, github-actions, self-hosted-runner, mas-go-dev, gpg, dirmngr, gnupg2-minimal, signature-verification, amazon-linux-2023]
---

# backend SonarQube 扫描在 mas-go-dev-ci-1 上失败：缺 dirmngr 无法拉 SonarSource 公钥

## 现象

把 iCare-backend 的 Go 测试 + SonarQube 扫描迁到 `backend-ci` 共享 runner 池后，PR（base=`develop`）触发的 `SonarQube Scan` job 落到 `mas-go-dev-ci-1`（PVE 上的 Amazon Linux 2023 VM，x86）时失败：

- `Setup Go` / `Run Tests with Coverage` 等步骤全部成功
- 挂在 `SonarQube Scan`（scanner 上报）这一步
- 关键日志：

```text
gpg: keyserver receive failed: No dirmngr
##[error]Action failed: Failed to import SonarSource public key from all keyservers.
Primary (hkps://keyserver.ubuntu.com): The process '/usr/bin/gpg' failed with exit code 2.
Fallback (hkps://keys.openpgp.org): The process '/usr/bin/gpg' failed with exit code 2
```

## 根因

两层叠加：

1. **develop 版 workflow 才会触发 GPG 签名校验。** iCare-backend 的 `develop` 分支把 `SonarSource/sonarqube-scan-action` **pin 到 SQSCANGHA-135 修复 commit**（`358113921641...`），这个版本会校验下载的 Scanner CLI 的 GPG 签名，需要先从 keyserver 拉取 SonarSource 公钥（key `679F1EE92B19609DE816FDE81DB198F93525EC1A`）。`main` 分支用的是 `@v6`，不做此校验——所以在该 runner 上跑 main 版 workflow（PR #574/#580）从未暴露此问题，只有 develop 版才触发。

2. **该 VM 装的是 `gnupg2-minimal`，没有 `dirmngr`。** Amazon Linux 2023 默认只装 `gnupg2-minimal`，它提供 `/usr/bin/gpg` 但**不含 `dirmngr`**——而 `dirmngr` 正是 gpg 用来访问 keyserver 的网络组件。没有它，`gpg --recv-keys` 直接报 `No dirmngr`，公钥拉不下来，签名校验无法进行，action 报错退出。

## 解决

在 runner 所在 VM 上把 `gnupg2-minimal` 替换为完整 `gnupg2`（含 dirmngr）：

```bash
# AL2023 上 gnupg2-minimal 与完整 gnupg2 互斥（都提供 /usr/bin/gpg），
# 且没有独立的 dirmngr 包，必须用 --allowerasing 让 dnf 用完整包替掉 minimal 包
sudo dnf install -y --allowerasing gnupg2
```

`gpg` 版本不变（2.3.7）、路径不变，只是从 minimal 变体换成完整变体，多出 `dirmngr`、`gpg-agent` 等组件。

验证修复（模拟 CI 那步，应返回 `imported: 1`、exit 0）：

```bash
command -v dirmngr            # /usr/bin/dirmngr
TMPHOME=$(mktemp -d)
gpg --homedir "$TMPHOME" --batch \
  --keyserver hkps://keyserver.ubuntu.com \
  --recv-keys 679F1EE92B19609DE816FDE81DB198F93525EC1A
rm -rf "$TMPHOME"
```

前提：runner 所在 VM 要能出网访问 keyserver（`keyserver.ubuntu.com:443` / `keys.openpgp.org:443`）。mas-go-dev 实测可达（均 200）；若未来 runner 落在更严格的内网环境，需另想公钥分发方式（预置 keyring 或内网 keyserver 镜像）。

修复后重跑原失败的 run，`SonarQube Scan` step 在同一台 mas-go-dev-ci-1 上成功通过，确认问题解决。

## 预防

- **任何要承接 backend SonarQube 扫描的 self-hosted runner，都必须具备：完整 `gpg` + `dirmngr` + 能出网拉 keyserver 公钥。** 把这三项纳入新 runner 上线检查清单。
- 排查"某 job 在共享池里时好时坏"时，先确认它**落在哪台 runner** 以及**触发分支的 workflow 版本**——本例就是 develop 版（带签名校验）+ 特定 runner（缺 dirmngr）两个条件同时满足才暴露，单看任一面都会漏判。

## 相关

- mac-mini 同源的 Sonar GPG 坑（不同表现：PATH 缺 gpg + runner `_work/_temp` 路径过深导致 gpg-agent socket `File name too long`）：`docs/solutions/mac-mini/integration-issues/sonarqube-scanner-cli-cache-never-hits-4part-version-2026-06-09.md`
- backend CI 共享 runner 池调度的来龙去脉：见 `docs/operations/mas-go-dev.md`（2026-06-10 19:10 / 19:35 / 19:50 三条）

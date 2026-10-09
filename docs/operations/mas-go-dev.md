# mas-go-dev 运维操作时间线

## 2026-10-10 01:35 CST - 为 AcquiLangAI 增加仓库级 CI runner

- 服务器：`mas-go-dev`；仓库 `IAmKongHai/AcquiLangAI`。
- 操作人：`Grok`。用户要求把一部分 CI 分到这台机器。
- 原因：mac-mini 10 核负载到 14–20，AcquiLang 的 Jest 被拖过超时。`lemon-imac` 和 `umacbook-pro` 当时连不上。这台机器 4 核，负载约 0.12，可用内存约 5.2 GiB。
- 影响：新增一个仓库级 slot，最多 2 核、2 GiB。backend、admin、web 和 CI 汇总在 workflow 合入后可以调度到这里，也可以继续落在 mac-mini 的 `ci-1` … `3`。native 仍要求 macOS。Sonar 不来这台机器。没有给 iCare、shared-sit、tk-flywheel runner 加 label，没有改它们的服务，没有动数据库。
- 备份：`/var/backups/acquilang-ci-20261010-0132/pre-state.txt`（root 700）。记录安装前的 runner 服务、内存、磁盘和容器状态。没有数据库变更。
- 回滚方式：确认没有 job 后，只停止并禁用 `actions.runner.IAmKongHai-AcquiLangAI.mas-go-dev-acquilang-ci-1.service`。保留用户、目录和注册。不要停止共享 PostgreSQL、SIT 容器或其他 runner。workflow 侧把 `acquilang-build` 的 job 改回带 `macos` 和 `arm64` 的 `acquilang-ci`。
- 做了什么：
  1. 新建系统用户 `acquilang-ci`（uid 991），无 sudo、不在 `docker` / `wheel` 组。目录 `/opt/acquilang-ci/{runner,work,cache}` 为 700。
  2. `dnf install python3.12`（3.12.12）。pnpm 11 的二进制还缺 `libatomic.so.1`，补装 `libatomic`。没有升级 Amazon Linux 发行版。
  3. 下载 runner `2.337.0` 的 linux x64 包，SHA-256 `70920811…16613` 校验通过。注册为 `mas-go-dev-acquilang-ci-1`（GitHub id `27`），labels `self-hosted,Linux,X64,acquilang-build`，工作目录 `/opt/acquilang-ci/work`。
  4. `svc.sh install acquilang-ci` 后加上 override：CPUQuota 200%、MemoryMax 2G、MemoryHigh 1536M、TasksMax 512。`.env` 只写 pnpm / npm 缓存路径，没有数据库密码。
- 验证：
  - 服务 active，日志 `Connected to GitHub`，GitHub 状态 online。
  - [PR #64 首轮 CI 37967388870](https://github.com/IAmKongHai/AcquiLangAI/actions/runs/37967388870) 全部 success。backend 在这台 runner，汇总当时还没分开；admin、native、web、Sonar 在 mac-mini。
  - rebase 后的 [CI 37968188235](https://github.com/IAmKongHai/AcquiLangAI/actions/runs/37968188235) 里，admin 和 native 先因缺少 `libatomic.so.1` 失败。补包后 admin 在这台 runner 上 success。native 的邮箱验证门禁用例报 `render function has not been called`，已改回只在 macOS 上跑。
  - 改完后的 [CI 37969469480](https://github.com/IAmKongHai/AcquiLangAI/actions/runs/37969469480) 全部 success。backend 和 web 在 `mas-go-dev-acquilang-ci-1`，native、admin、Sonar 在 mac-mini。
  - 跟上 main 后再跑的 [CI 37970059168](https://github.com/IAmKongHai/AcquiLangAI/actions/runs/37970059168) 也全部 success。admin 和 backend 在这台 runner，web、native、Sonar 在 mac-mini。PR #64 已 squash 合并为 `cb613601`。
  - 跑完 backend 后 cgroup 内存约 533 MiB，没有顶到 2G。`shared-sit-postgres` 仍是 Up 3 weeks。iCare / shared-sit / tk-flywheel 的 runner 服务仍是 active。
- 档案：[acquilang-ci/README.md](../../mas-go-dev/acquilang-ci/README.md)。

## 2026-10-05 02:02 CST - moo-ticket CI 改到自托管 runner

- 服务器：GitHub org `cypressoai` runner group `mas-go-dev`（id 3）；对照本机 `mas-go-dev-ci-1` / `mas-go-dev-ci-2`
- 操作人：`Grok`
- 原因：`cypressoai/moo-ticket` 的 CI 还在 GitHub-hosted `ubuntu-latest`。backend 要临时 Postgres，image 要 `docker build`，唯一同时有 `Linux`、`docker`、`backend-ci` 的是 `mas-go-dev-ci-1`。它在 selected 组里，名单原先不含这个仓库，job 会一直排队。
- 影响：该仓库的 CI 可以调度到这个组的三台 runner。部署 runner `mas-go-dev` 没有 `backend-ci`，CI 不会落到它头上。未改本机 systemd、Docker、label，未动 iCare / EVP 容器。部署 workflow 仍走 `dev-cypresso-ci`。
- 备份：加仓前名单为 `evp`、`iCare-backend`、`iCare-frontend-mas`、`iCare-Operations-backend`、`iCare-Operations-frontend`、`iCare-public-backend`、`iCare-public-frontend`、`vps-traffic-monitor`。
- 回滚方式：
  1. `DELETE orgs/cypressoai/actions/runner-groups/3/repositories/1353401174`（`cypressoai/moo-ticket`）。
  2. 把 `.github/workflows/ci.yml` 的 job 改回 `ubuntu-latest`，并恢复 `services.postgres`。
- 选型：
  - backend / image：`[self-hosted, Linux, docker, backend-ci]`。`docker run -p 127.0.0.1::5432` 拿随机端口，结束 `docker rm -f`。不用 GHA `services:` 映射宿主机 5432。
  - frontend：`[self-hosted, frontend-quality-ci]`。
  - 分支保护仍要求名为 `CI` 的汇总 check，`runs-on: [self-hosted, backend-ci]`。
  - `setup-go` / `setup-node` 不走 GitHub Cache API。
- 做了什么：
  1. 只读确认 `actions-runner` 可用 docker、gcc、python3；`127.0.0.1:5432` 与 `100.109.223.53:5432` 已被占用；可用内存约 5.6GiB。
  2. `PUT orgs/cypressoai/actions/runner-groups/3/repositories/1353401174`。
  3. workflow 放在分支 `ci/self-hosted-runners`。[PR #46](https://github.com/cypressoai/moo-ticket/pull/46)。`main` 要求走 PR，直接推送被拒。
- 验证结果：
  - 组内仓库现为 9 个，含 `cypressoai/moo-ticket`。
  - [CI run 37222299995](https://github.com/cypressoai/moo-ticket/actions/runs/37222299995) `success`。`frontend`（47 秒）、`image`、`backend` 都在 `mas-go-dev-ci-1`，汇总 `CI` 在 `mas-go-dev-ci-2`。没有 GitHub-hosted job。
  - 跑完后本机没有 `moo-ci=postgres` 容器，也没有名为 `moo-ci-pg-*` 或 `moo-ticket-check` 的残留容器。
- 观察：`mas-go-dev-ci-1` 同时带 `frontend-quality-ci`，这轮 frontend 也落在它上面，backend 和 image 因此串行。三步合计约 7 分钟，没有把机器打满。

## 2026-09-23 21:27 CST - 补 .env.accredited 占位文件，恢复 Backend Deploy 部署 ecom / sup

- 服务器：`mas-go-dev`
- 操作人：Claude（用户确认创建文件并重跑 CI）
- 原因：iCare-backend CYP-2890（PR #1993，2026-09-14 合入 develop）在 `backend.compose.yaml` 的 `external-api` profile 下新增 `accredited-api`，声明 `env_file: ${ACCREDITED_ENV_FILE:-.env.accredited}`。`scripts/deploy_external_api.sh` 以 `--profile external-api` 调 compose，compose 加载 project 时检查该 profile 下所有服务的 env_file，本机没有这个文件，于是 `Deploy to mas-go-dev` 每次都在部署 ecom-api 这一步 exit 14。
- 影响：api / worker 在失败前已重建，不受影响；ecom-api / sup-api 自 9-14 起没有随 develop 更新（补文件前运行的是 `e77093c1`）。本次重部署 ecom-api / sup-api，各中断几秒。
- 做了什么：以 `actions-runner` 在 `/opt/mas-go-dev/backend/` 新建 `.env.accredited`（`set -C` 防覆盖，`umask 077`，经 stdin 写入，不经 `/tmp`）。文件**只有注释、没有任何变量**，说明它仅为占位、accredited-api 未部署、完成前置工作前不得跑 `profile=accredited` 的 Partner API Deploy。属主 / 权限 `actions-runner:actions-runner 600`，与 `.env.ecom` 一致。未改 compose、脚本、workflow。
- 备份：新增文件，无既有文件被改动。回滚点为补文件前运行的镜像：ecom-api `sha256:5450f22422d3`（`icare/backend-ecom:mas-go-dev-e77093c1…`）、sup-api `sha256:2420881c2950`（`icare/backend-sup:mas-go-dev-e77093c1…`）。CI 会清理旧的本地 tag，所以要以镜像 ID 为准。
- 回滚方式：
  1. 删掉 `.env.accredited`，部署会重新在 exit 14 处失败。
  2. 如需把 ecom / sup 退回旧版本：以 `actions-runner` 在部署目录执行 `up -d --no-deps --force-recreate ecom-api sup-api`，并通过对应的 `*_IMAGE` 变量显式传入上面记录的镜像 ID。
- 变更时序（UTC）：
  - 13:2x 补文件前 `sudo -u actions-runner … docker compose --profile external-api -f backend.compose.yaml config -q` 复现 `env file /opt/mas-go-dev/backend/.env.accredited not found`，exit 14
  - 13:2x 创建占位文件，同一条 `config -q` 返回 exit 0
  - 13:27 `gh run rerun 35862572320 --failed`（Backend Deploy，head `a79dd4a5`，develop 上当时最新的失败 run）
- 验证：
  - [run 35862572320](https://github.com/cypressoai/icare-backend/actions/runs/35862572320) attempt 2 `success`；日志 13:30:47 `ECOM API readiness, Swagger, and profile isolation checks passed.`，13:30:55 `SUP API readiness … passed.`
  - `icare-backend-ecom-api-1`：`icare/backend-ecom:mas-go-dev-a79dd4a5…`，StartedAt `13:30:45Z`，healthy
  - `icare-backend-sup-api-1`：`icare/backend-sup:mas-go-dev-a79dd4a5…`，StartedAt `13:30:53Z`，healthy
  - 补文件前、补文件后、CI 跑完后，`docker ps -a` 三次都没有 accredited-api 容器
  - 计划中的假设"compose 只检查 env_file 是否存在，不校验内容"已被 `config -q` 实测证实
- 已知遗留：accredited-api 仍未在本机部署。真正上线所需步骤（库账号、JWT secret、Redis、完整配置、部署方式）见 [计划](../plans/2026-09-23-2055-ops-backend-deploy-env-accredited-plan.md) 的 Scope Boundaries → Deferred 一节。应用仓的长期根治方案（env_file `required: false` 或拆出独立 profile）也在该节，本机 compose 版本为 v2.24.5，满足 `required: false` 所需的 ≥ 2.24。

## 2026-09-17 02:52 CST - 重启验证 DNS 未复发，并修复 accept-dns=false 导致的 MagicDNS 短名失效

- 服务器：`mas-go-dev`。
- 操作人：`Claude`。
- 原因：用户要求重启 VM，验证上一条目的 DNS 修复在重启后是否复发；同时用户提出 CI 里 SonarQube 服务端是 MagicDNS 短域名 `http://mac-mini:9000/`，需确认是否受 `--accept-dns=false` 影响。
- 影响：重启导致 iCare / EVP / CMM 三个项目的 SIT 环境（27 个容器）中断约 3 分钟。重启在四个组织 runner 全部 `busy=false` 时执行，未打断任何 CI job。
- 备份：本次新增 `/etc/systemd/resolved.conf.d/tailscale-magicdns.conf`，该目录原本不存在，回滚即删除文件；未修改既有配置，无需备份。
- 回滚方式：`sudo rm /etc/systemd/resolved.conf.d/tailscale-magicdns.conf && sudo systemctl restart systemd-resolved` 即回到重启后的状态（公网可用、短名不可用）。

### 重启验证结果：DNS 故障未复发

- 重启前基线：`tailscale debug prefs` 显示 `CorpDNS: false` 已持久化。
- 重启后 `/etc/resolv.conf` **仍是指向 `/run/systemd/resolve/resolv.conf` 的符号链接**（mtime 保持 `Sep 17 02:18`），未被 Tailscale 再次覆写。
- 公网解析正常：`github.com` → `172.182.252.133`，`pipelinesghubeus22.actions.githubusercontent.com` → `20.10.226.54`。
- 四个组织 runner 重启后自动 online，27 个容器全部拉起，数量与重启前一致。
- 结论：上一条目的修复在重启后稳定，原故障不再复发。

### 重启暴露的新问题：MagicDNS 短名失效

- 重启后 nameserver 只剩 `192.168.2.1`，`100.100.100.100` 消失，`getent hosts mac-mini` 失败，`curl http://mac-mini:9000` 返回 HTTP 000。
- 根因：`CorpDNS: false` 使 tailscaled 启动后不再向 systemd-resolved 注册 MagicDNS 服务器。上一条目"MagicDNS 短名仍可用"的复验结论**不成立**——当时测到的 `100.100.100.100` 是故障期间 Tailscale 写入 resolv.conf 的残留，重启后自然消失。教训：在未重启的机器上验证开机行为不可靠。
- MagicDNS 服务本身正常：`dig mac-mini.taila93443.ts.net @100.100.100.100` 能返回 `100.108.64.126`，只是没进解析链。
- 影响面：CI 中 SonarQube 扫描通过 `http://mac-mini:9000/` 提交分析报告，短名失效会导致相关 job 失败。

### 修复：用 resolved drop-in 单独路由 tailnet 域

不改回 `accept-dns=true`（那会重新引入覆写 resolv.conf 丢上游的根因），改为只把 tailnet 域交给 MagicDNS：

```ini
# /etc/systemd/resolved.conf.d/tailscale-magicdns.conf
[Resolve]
DNS=100.100.100.100
Domains=~taila93443.ts.net
```

`sudo systemctl restart systemd-resolved` 生效。`~` 前缀表示仅作为该域的路由域，不参与其它域名解析，因此公网 DNS 仍走 eth0 的 `192.168.2.1`。

### 修复后验证

| 检查项 | 结果 |
| --- | --- |
| `/etc/resolv.conf` | 仍为符号链接，nameserver 为 `100.100.100.100` + `192.168.2.1` |
| `github.com` | `172.182.252.133` |
| `pipelinesghubeus22.actions.githubusercontent.com` | `20.10.226.54` |
| `getent hosts mac-mini` | `100.108.64.126 mac-mini.taila93443.ts.net` |
| `curl http://mac-mini:9000/api/system/status` | HTTP 200 via `100.108.64.126` |
| 容器内（`--network host`）解析 + 请求 | 解析一致，SonarQube 返回 `{"status":"UP"}`，版本 26.5.0.122743 |
| 四个组织 runner | 全部 online |
| 容器数量 | 27，与重启前一致 |

### 待跟进

- ~~本次 drop-in 未经重启验证~~ → **已于 03:04 CST 二次重启验证通过**，见下方补充。
- tailnet 域名 `taila93443.ts.net` 硬编码在 drop-in 中，若将来更换 tailnet 需同步修改。
- 验证脚本放在 `/tmp/verify-dns.sh`，重启后会被清空，下次需重新上传（源文件不在仓库内，内容见本条目"修复后验证"表格的检查项）。

### 补充：2026-09-17 03:04 CST 二次重启，验证 drop-in 开机自动生效

- 原因：前述 drop-in 是在运行中的系统上 `systemctl restart systemd-resolved` 后生效的，开机行为未经证实。鉴于本条目已有一次"在未重启系统上验证开机行为"的误判，用户要求实测。
- 时机：四个组织 runner 均 `busy=false`、无 CI 临时容器时执行，未打断任何 job。SIT 再次中断约 3 分钟。
- 结果：**开机自动生效，无需人工干预**。全新启动（uptime 5 分钟）且未手动重启 systemd-resolved 的情况下，`/etc/resolv.conf` 中 `100.100.100.100` 与 `192.168.2.1` 均自动就位。
- 九项检查全部通过：resolv.conf 仍为符号链接未被覆写；`github.com` → `172.182.252.133`；`mac-mini` → `100.108.64.126`；`curl http://mac-mini:9000` HTTP 200；容器内（`--network host`）访问 SonarQube 返回 `{"status":"UP"}`；`CorpDNS: false`；四个 runner 服务 active 且 GitHub 侧 online；容器 27 个与基线一致。
- 结论：DNS 方案在重启后稳定，公网解析与 MagicDNS 短名并存，CI 依赖的 SonarQube 可达。本次 DNS 相关工作收尾。


## 2026-09-17 02:18 CST - 修复 Tailscale 覆盖 resolv.conf 导致的 DNS 故障与 runner 全体掉线

- 服务器：`mas-go-dev`。
- 操作人：`Claude`。
- 原因：`cypressoai/evp` 的 [Deploy SIT run 35169447886](https://github.com/cypressoai/evp/actions/runs/35169447886) 排队约 1 小时无人认领。排查发现组织 runner `shared-sit`、`mas-go-dev-ci-1`、`mas-go-dev-ci-2`、`mas-go-dev` 在 GitHub 侧全部 offline，但 VM 存活、五个 runner systemd 服务均 `active running`。真因是 DNS 解析失败，不是 runner 程序问题。
- 故障链条：VM 于 2026-09-16 10:44 重启（boot `8ebd32657a51408bae5b4d7f8e9ffb2f`）→ Tailscale 把 `/etc/resolv.conf` 从指向 `/run/systemd/resolve/resolv.conf` 的符号链接覆写成静态文件，只保留 `100.100.100.100` 与 `fd7a:115c:a1e0::53`，丢掉 eth0 的上游 `192.168.2.1` → 但 tailnet 未配置全局 resolver（`tailscale dns status` 显示 `no resolvers configured, system default will be used`），MagicDNS 需回落系统 DNS 而系统 DNS 已被自己冲掉 → 公网域名全部解析不了，runner 日志重复报 `Runner connect error: Name or service not known (pipelinesghubeus22.actions.githubusercontent.com:443). Retrying until reconnected.`，重试退避拉长后停在 10:59。
- 影响：EVP SIT 部署与 iCare 相关 CI 在 2026-09-16 10:44 至 2026-09-17 02:19 期间无法调度，job 只排队不执行。宿主机本身、容器与已部署 SIT 服务未受影响。
- 备份：`/etc/resolv.conf.bak.20260917`（`cp -a` 保留原属性，内容为 Tailscale 生成的静态版本）。
- 回滚方式：`sudo tailscale set --accept-dns=true`，再 `sudo cp -a /etc/resolv.conf.bak.20260917 /etc/resolv.conf` 覆盖回静态文件即可恢复原状。

### 变更时序

1. 备份当前 `/etc/resolv.conf` 到 `/etc/resolv.conf.bak.20260917`。
2. `sudo tailscale set --accept-dns=false`，交回 DNS 管理权（退出码 0）。Tailscale 不会自动还原被覆写的文件。
3. `sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf`，恢复由 systemd-resolved 管理，上游 `192.168.2.1` 回到解析链。
4. 未重启任何 runner 服务：runner 自带重连退避，DNS 恢复后自行重连。

### 验证结果

- 修复前：`getent hosts github.com` 与 `getent hosts pipelinesghubeus22.actions.githubusercontent.com` 均失败；但 `dig @192.168.2.1 github.com` 与 `dig @8.8.8.8 github.com` 都能返回 `140.82.116.3`，确认上游 DNS 正常，问题仅在本机 resolv.conf。
- 修复后：`github.com` → `140.82.116.4`，`pipelinesghubeus22.actions.githubusercontent.com` → `20.10.226.54`，解析恢复。
- `shared-sit` runner 于 02:19:02 `Connected to GitHub`、02:19:04 `Runner reconnected.`、02:19:09 接单 `Running job: Deploy to shared-sit`。四个 runner 在 GitHub 侧全部回到 online。
- 因 `shared-sit` 与 `mas-go-dev-ci-1` 重连后立即 busy=true 正在执行任务，原计划的「重启三个 runner 服务」取消执行，避免打断运行中的 job。

### 待跟进

- 这是重启时 Tailscale 与 systemd-resolved 的竞态，VM 下次重启仍可能复发。`--accept-dns=false` 通常持久化在 Tailscale 状态中，但 `/etc/resolv.conf` 符号链接是否会被再次覆写未经重启验证。下次重启 `mas-go-dev` 后需确认 `ls -la /etc/resolv.conf` 仍是符号链接、且 runner 正常上线。
- MagicDNS 短名：**重启前的"仍可用"结论不成立**，那次测到的 `100.100.100.100` 是故障期间 Tailscale 写入的残留。重启后 `CorpDNS: false` 使 Tailscale 不再向 systemd-resolved 注册 MagicDNS，nameserver 只剩 `192.168.2.1`，`mac-mini` 解析失败、`http://mac-mini:9000` 的 SonarQube 不可达（CI 依赖）。已通过 resolved drop-in 单独补回，见下方 02:56 条目。


## 2026-09-16 00:55 CST - 为 tk-flywheel 创建固定 CI 库和仓库级 runner

- 服务器：`mas-go-dev`；仓库 `IAmKongHai/tk-flywheel`。
- 操作人：`Codex`。
- 原因 / 授权：用户明确同意创建固定 `tk_flywheel_ci` 库，并把 runner 放在 mas-go-dev。
- 影响 / 选型：在现有共享 PostgreSQL 18 中新增专用数据库 / 角色；新增一个仓库级 runner slot，四个 CI job 排队。独立系统用户无 Docker / sudo 权限；最多 2 核 / 3 GiB，Go 编译并发 2。原 iCare / EVP / CMM 服务与组织 runner 配置保持原状。
- 备份：`/opt/shared-sit/backups/tk-flywheel-ci-20260916-0041`（root 700，文件 600），含 globals、postgres / evp / cmm schema、PostgreSQL Compose、原 runner service、容器启动时间和内存 / 磁盘快照。globals 含密码摘要，仅保留服务器。未制作业务数据全量备份。
- 回滚方式：还原 tk-flywheel workflow；确认空闲后仅停止 / 禁用新 runner 服务，保留数据库、角色与备份。删除数据 / 角色需另行确认，不停止共享 PostgreSQL 或其他 runner。

### 变更时序

1. 新增系统用户 `tk-flywheel-ci` 和 `/opt/tk-flywheel-ci/{runner,work,cache}`（用户目录 700）。官方下载 runner 2.337.0，SHA-256 校验通过，内置 Node.js 24 可执行。
2. 新建 LOGIN 角色和固定库 `tk_flywheel_ci`，库 owner 为 `postgres`；角色无超级用户 / 建库 / 建角色 / 复制 / 绕过 RLS 权限。库和角色各限 12 连接，角色只获目标库 `CONNECT, CREATE, TEMPORARY`，目标库与 `public` schema 撤销 PUBLIC 权限。角色默认语句 30 秒、锁 5 秒、空闲事务 30 秒超时。
3. 随机凭据写入 `/opt/shared-sit/tk-flywheel-ci/credentials.env`（root 600，目录 700），连接 `127.0.0.1:5432`；通过标准输入设置仓库 Secret `CI_DATABASE_URL`。未把密码输出到终端、写入 runner `.env` 或提交仓库。
4. 注册 `mas-go-dev-tk-flywheel-ci-1`（仓库 runner id `2`），labels 为 `self-hosted,Linux,X64,tk-flywheel-ci`，使用 `/opt/tk-flywheel-ci/work`。启用并启动 `actions.runner.IAmKongHai-tk-flywheel.mas-go-dev-tk-flywheel-ci-1.service`，GitHub 显示 online。
5. systemd override 设置 CPUQuota 200%、MemoryHigh 2560M、MemoryMax 3G、TasksMax 512、低 CPU / IO 权重和 UMask 0077；通过 `.env` 设置独立 Go / npm 缓存及 Go 并发 2。配置副本见 [runner 档案](../../mas-go-dev/tk-flywheel-ci/README.md)。
6. tk-flywheel workflow 去掉临时 PostgreSQL service，两个 job 定义都使用专用 runner label；只有 Backend 获得 Secret，缺失时直接失败。Compose 使用 PostgreSQL 18 和 `/var/lib/postgresql` volume；已有 17 数据需另行迁移，本次未迁移。
7. 提交 `78d7d0c`（连同此前 `bae4246`）并创建 [PR #3](https://github.com/IAmKongHai/tk-flywheel/pull/3)，触发 [CI 34997551965](https://github.com/IAmKongHai/tk-flywheel/actions/runs/34997551965)。PR 尚未合并，main 的配置待合并后生效。

### 验证结果

- actionlint 与缺失 Secret 检查通过。专用角色真实 TCP 认证后，事务内创建 schema / 表、插入、读取、ROLLBACK 成功；分别连接 `cmm` / `evp` / `postgres` 均返回权限拒绝。
- 完整 CI 四个 job 全部 success，均由 `mas-go-dev-tk-flywheel-ci-1` 执行，00:50:51 至 00:54:38 CST。Backend 使用 Go 1.26.2 linux/amd64；`TestPostgresFlows` 及 subscription_accounts / subscription_session_isolation / operating_skills 三个子测试全部 PASS，没有跳过数据库测试。三个 JavaScript job 的测试及适用的类型检查 / 构建通过。
- 测试后目标库遗留 test / ci_probe schema 为 0，CI 账号活动连接为 0。五个 runner 服务均 active，新 runner GitHub online / idle。与操作前快照相比，所有原容器 StartedAt 均未变化。
- 新 runner cgroup 峰值内存 1,647,980,544 字节（约 1.53 GiB），memory.events 的 high / max / oom / oom_kill 均为 0；这轮验证不能代表所有组织 runner 同时满载的容量保证。
- 正常测试退出删除各自随机 schema；强制取消 / 超时可能遗留，需核对活动连接后针对性清理，不设自动清空业务库任务。

## 2026-09-16 00:49 CST - 盘点 PostgreSQL 实例与数据库（只读）

- 操作人：`Codex`。
- 原因：用户要求核对 mac-mini 与 mas-go-dev 分别运行哪些 PostgreSQL 数据库。
- 影响：仅通过 SSH 查询 Docker 状态和 PostgreSQL 系统目录，未修改服务、配置、schema 或数据。
- 备份：只读查询，无需备份；当前状态记录如下。
- 回滚方式：无服务器变更，无需回滚。
- 做了什么：检查全部 Docker 容器及 PostgreSQL 进程；对 `shared-sit-postgres` 使用现有管理身份查询版本、库名、属主和大小。查询会话设置 `default_transaction_read_only=on`、`statement_timeout=15000`，未输出凭据。
- 验证：发现一个 PostgreSQL 容器 `shared-sit-postgres`，状态 running / healthy，版本 18.6；端口映射为 `127.0.0.1:5432` 和 `100.109.223.53:5432`。查询得到以下非模板数据库，另有 `template0` / `template1`。

| 数据库 | 属主 | 查询时大小 | 说明 |
| --- | --- | --- | --- |
| `cmm` | `cmm` | 10174 kB | 菜苗苗 SIT |
| `evp` | `evp` | 10 MB | EVP SIT |
| `tk_flywheel_ci` | `postgres` | 7678 kB | 当前已存在；本次未创建，未验证测试接入状态 |
| `postgres` | `postgres` | 7678 kB | 默认管理库 |

- 与 00:35 的历史快照相比，当前已出现 `tk_flywheel_ci`；以本次实时查询为准。本次未调查其创建来源或修改权限。库清单表示实例中存在的数据库，不代表每个库都有应用正在连接。

## 2026-09-16 00:35 CST - 核对共享 PostgreSQL 供 tk-flywheel CI 复用的条件（只读）

- 服务器：`mas-go-dev`，容器 `shared-sit-postgres`。
- 操作人：`Codex`。
- 原因：用户希望 CI 直接连接常驻数据库，询问能否使用开发库及本机共享 PostgreSQL。
- 影响 / 选型：只读核对容器、数据库清单、连接数和测试代码。可复用同一 PostgreSQL 实例，建议新建常驻专用库 `tk_flywheel_ci` 与非管理员 CI 账号；不复用 EVP / CMM 的数据库或凭据。此建议替代 00:12 记录中的临时 PostgreSQL 容器方案，尚未实施。
- 备份：未改配置或数据；关键现状记录如下。
- 回滚方式：只读排查，无需回滚。
- 做了什么 / 验证结果：
  1. `docker ps` 显示容器 healthy；`postgres --version` 为 18.6，镜像为 `postgres:18-alpine`（实际配置含 digest）。监听 `127.0.0.1:5432` 与 `100.109.223.53:5432`，限额 1 GiB / 1 CPU。
  2. 使用容器内现有管理身份执行只读 SQL：非模板数据库仅 `cmm`、`evp`、`postgres`，没有 tk-flywheel 库；`max_connections=80`，采样 `pg_stat_activity` 行数为 12（包含本次查询等进程，非连接峰值保证）。
  3. `tk-flywheel/backend/main_test.go` 的 `TestPostgresFlows` 读取 `TEST_DATABASE_URL`，创建随机 `test_*` schema，通过连接参数 `search_path` 指向该 schema，执行迁移并写入测试数据；正常退出时 `defer DROP SCHEMA ... CASCADE`。它不会直接使用开发环境的已有业务数据。强制终止进程时不能保证 defer 清理发生。
  4. `backend/main.go` 的迁移使用固定事务 advisory lock 和未限定 schema 的迁移表。共用业务 database 仍需正确的权限隔离，也可能与同库开发迁移争用锁；专用常驻 CI database 更容易限定权限与清理范围。
  5. `tk-flywheel` 已在本地提交 `bae4246` 将 CI / Compose 改为 PostgreSQL 18；本次未修改 workflow、注册 runner、创建库/角色或执行数据库测试。
- 后续条件：建库 / 角色前按约定备份并确认；限制 CI 账号权限与连接数，正常任务清理各自的 schema，异常遗留另行核对处理。移除 workflow 的 PostgreSQL `services:` 并改为连接常驻库后，不再因 service container 要求 Linux；mac-mini runner 也可通过 Tailscale 访问共享实例，需验证网络和凭据配置。

## 2026-09-16 00:12 CST - 评估 tk-flywheel 仓库级 CI runner 容量（只读）

- 服务器：`mas-go-dev`；目标仓库 `IAmKongHai/tk-flywheel`（个人账号私有仓库）。
- 操作人：`Codex`。
- 原因：用户希望将 tk-flywheel CI 改为自托管，并说明可用 Linux 主机只有 mas-go-dev；当前后端 workflow 使用 PostgreSQL 17 `services:`，需要 Linux runner。
- 影响 / 选型：只读检查宿主资源、Docker、runner 服务和端口。建议新增一个仓库级 slot 试跑，拟名 `mas-go-dev-tk-flywheel-ci-1`、专用 label `tk-flywheel-ci`，四个 CI job 在该 slot 排队。尚未注册 runner 或修改 workflow，不接入现有组织 runner 的 label 池。
- 备份：无配置变更；关键状态记录如下，作为后续安装前的参考，实施时仍需重新检查并备份。
- 回滚方式：只读排查，无需回滚。

### 检查时序与验证

1. 核对目标仓库 `.github/workflows/ci.yml`：Backend 为 Go 1.26.2 的格式 / vet / race test / build，测试依赖临时 PostgreSQL 17；JavaScript 为 frontend / extension / agent 三个 Node.js 24 job。当前均使用 `ubuntu-24.04`。GitHub 仓库 API 返回 private，仓库级 runner 数量为 0。
2. SSH 核对：Amazon Linux 2023、x86_64、4 vCPU；内存 7.7 GiB，available 5.1 GiB；swap 已用约 897 MiB。`vmstat` 后续四个间隔无 swap in/out，CPU idle 90–99%；负载 0.25 / 0.13 / 0.21。仅为低负载窗口快照，未验证 CI 高峰容量。
3. 根盘 300G，已用 92G、可用 209G（31%）；Docker Server 25.0.14，glibc 2.34，`gcc` / `git` / `tar` / `gzip` 可见。SSH 用户 PATH 未发现 `go` / `node`；安装时需验证新 runner 的工具环境，不能凭现有 runner 在线就认定依赖齐全。
4. 现有 `mas-go-dev`、`mas-go-dev-ci-1/2`、`shared-sit` 四个 systemd 服务均 active，用户均为 `actions-runner`；现场 4 个 `Runner.Listener`、0 个 `Runner.Worker`。四个服务的 CPUQuota / MemoryMax 均未设限。GitHub 组织 runner API 返回 403（当前账号权限不足），未取得接口侧 busy 状态。
5. `docker ps` / `docker stats --no-stream` 显示 iCare、EVP、CMM 和共享 SIT 服务运行中。共享 PostgreSQL 已绑定 `127.0.0.1:5432` 与 `100.109.223.53:5432`，目标 CI 的 `5432:5432` 会发生端口冲突。

### 后续实施约束（尚未执行）

- 新实例使用独立程序 / 工作 / 缓存目录及仓库注册凭据，先一个 slot；限制 Go 编译并行度并为 runner 进程设置资源上限，避免与现有 CI / SIT 争抢整机资源。
- 保留独立、每个 job 临时创建的 PostgreSQL 17 测试容器，改用回环随机宿主端口并将实际端口传入 `TEST_DATABASE_URL`；不要连接或修改共享 SIT PostgreSQL 18。
- 测试容器另外设置 CPU / 内存限制；Docker daemon 创建的容器不应被视作已受 runner systemd 资源上限约束。
- 首轮验证涵盖后端数据库测试确实执行、race test、三个 JavaScript job、超时 / 取消后的临时资源清理，以及与已有 CI 同跑时的宿主资源。是否长期承接全部 job，以试跑结果为准。

## 2026-09-12 18:04 CST - 启动菜苗苗 SIT（shared-sit 租户 + compose）

- 服务器：`mas-go-dev`（Tailscale `100.109.223.53`）
- 操作人：`Grok`
- 原因：SIT 应用、PostgreSQL 租户、Redis DB 必须离开 `nyh-prod` 和 `cmm-prod`。
- 影响：新增 compose 项目 `cmm-sit`（api/worker/admin），端口 `25880`/`25881` 只绑回环和 Tailscale。iCare `api` 与 EVP 的 `StartedAt` 未变。
- 备份：`/opt/shared-sit/backup-before-cmm-*`（建租户前状态）；`/opt/shared-sit/bootstrap.sh.bak.20260912`。
- 回滚方式：`cd /opt/cmm-sit && docker compose --env-file .deploy.env stop`。不要 `down -v`，不要 `--remove-orphans`。库/角色 `cmm` 可留着。

### 变更时序

1. 建库/角色 `cmm`（`CONNECTION LIMIT 20`），Redis DB `2` 空着。`/opt/cmm-sit` 属主 `ec2-user` mode `750`。
2. 同步 `deploy/sit` compose / nginx overlay。GHCR digest 直拉失败，从 `cmm-prod` `docker save`/`load` 生产镜像后按 digest 十六进制打 tag。
3. 独立 COS 桶 `cmm-sit-uploads-1469943699`（private、未开版本控制）+ CAM `cmm-sit-api`。未用 `cmm-prod-api`。
4. `api.env` 600。`compose --profile ops run --rm migrate` → `seed` → `verify`（production seed，不是 seed-demo）。
5. `up -d` 后 admin 因只读根上没有 `/tmp` 不健康；compose 给 admin 加 `/tmp` tmpfs 后 recreate admin，api/worker 未重建。
6. loopback `smoke.sh` 通过；公网名在 Tailscale 直连恢复后同样通过。

### 验证

- AE3：角色 `cmm` 连库 `cmm` 成功，连 `postgres` 被拒。
- `ss`：`25880`/`25881` 在 `127.0.0.1` 与 `100.109.223.53`，不是 `0.0.0.0`。`192.168.2.22:25880` 拒绝。
- `GET http://127.0.0.1:25881/v1/meta` 返回 `cmm-api` JSON（overlay）。
- `/readyz` ok；worker running；`ALLOW_DEMO_SEED=false`。
- iCare `icare-backend-api-1` StartedAt 仍 `2026-09-12T05:08:04Z`；EVP web StartedAt 仍 `2026-09-11T07:57:52Z`。

## 2026-09-12 16:25 CST - 对照 km-landui 同城 RTT（只读）

- 服务器：`mas-go-dev` → `km-landui`（`43.228.79.237`）
- 操作人：`Grok`（只读）
- 原因：评估小程序 API 改由昆明 `km-landui` 反代回本机。
- 影响：无配置变更。
- 回滚方式：无需回滚。

`ping 43.228.79.237` 4.6–5.5ms，0% 丢包；TCP 80/443/28285 通；`https://derp.nanyahui.com/` 200 / 35ms。`km-landui` 不在 tailnet 里，本机业务口仍只绑 Tailscale + 回环，对端现在打不进来。

## 2026-09-12 16:12 CST - 评估作为菜苗苗 SIT（nyh-prod 公网反代，只读）

- 服务器：`mas-go-dev`（Tailscale `100.109.223.53`）
- 操作人：`Grok`（只读；未改 Docker / 端口 / Nginx / ACL）
- 原因：用户提议本机跑 SIT，小程序 API 经 `nyh-prod` 反代进来。
- 影响：无配置变更。
- 回滚方式：无需回滚。

### 现场

| 项 | 结果 |
| --- | --- |
| 到 `nyh-prod` | 直连 `47.239.167.8:41641`，约 40ms，`active` |
| NAT | `MappingVariesByDestIP: true`；公网映射 `112.117.55.212` |
| DERP | 最近昆明自建 `km` 5.6ms；官方 `hkg` **499.5ms** |
| 内存 | 7.7 GiB，available 约 5.3 GiB；swap 已用 890 MiB |
| 磁盘 | 300G 用 25%，剩 225G |
| shared-sit Postgres | **18.6**（与菜苗苗生产 / 开发库大版本一致） |
| 端口 | `8080`/`8081` 已被 iCare 占用；EVP 用 `25173`/`25174`/`28081`/`28082`。菜苗苗需另选高位端口 |
| 绑定惯例 | 业务口绑 `100.109.223.53` + `127.0.0.1`，不绑 `0.0.0.0` |

### 结论（未部署）

适合承载应用 + 独立库/Redis DB/Garage bucket。公网只让 `nyh-prod` 反代 API 端口。不要用 `cypressoai` 的 `shared-sit` runner 部署 `caimiamiao` 仓，继续 GitHub-hosted → SSH。家宽硬 NAT + 与香港没有共同好 DERP，直连断开时小程序入口会变慢或失败。

## 2026-09-09 13:59 CST - 把 cypressoai/evp 加入 mas-go-dev runner 组

- 服务器：GitHub org `cypressoai` runner group `mas-go-dev`（id 3）；对照本机 `mas-go-dev-ci-1`
- 操作人：`Grok`
- 原因：EVP Checks 的 `backend` / `images` 要求 `[self-hosted, Linux, docker, backend-ci]`。唯一匹配 runner 是 `mas-go-dev-ci-1`，但它在 selected 组 `mas-go-dev` 里，名单原先只有 iCare 仓 + `vps-traffic-monitor`，不含 `evp`。job 一直 queued，runner 空闲。
- 影响：`evp` 现在也能调度到该组的三台 runner。部署 runner `mas-go-dev` 没有 `backend-ci`，现有 Checks 不会落到它头上。SIT 仍走 `shared-sit` 组。未改本机 systemd / Docker / label。
- 备份：加仓前名单：`iCare-backend`、`iCare-frontend-mas`、`iCare-Operations-backend`、`iCare-Operations-frontend`、`iCare-public-backend`、`iCare-public-frontend`、`vps-traffic-monitor`。
- 回滚方式：`gh api -X DELETE orgs/cypressoai/actions/runner-groups/3/repositories/1361034755`（`cypressoai/evp` 的 repo id）。
- 做了什么：
  1. `PUT orgs/cypressoai/actions/runner-groups/3/repositories/1361034755`。
  2. 取消卡住的 Checks [run 34316200682](https://github.com/cypressoai/evp/actions/runs/34316200682) 并 rerun（已 queued 的 job 不会因为后来加仓而自行匹配）。
- 验证结果：rerun 后 [Checks 34316200682](https://github.com/cypressoai/evp/actions/runs/34316200682) `success`。`backend` / `images` 均落 `mas-go-dev-ci-1`；frontend 在 mac-mini / lemon；Sonar 在 mas-go-dev-ci-2 与 mac-mini。没有 GitHub-hosted job。

## 2026-09-09 13:45 CST - EVP Checks 从 ubuntu-latest 改到 self-hosted

- 服务器：`mas-go-dev`（质量 runner `mas-go-dev-ci-1`；对照 lemon / mac-mini 质量池）
- 操作人：`Grok`
- 原因：`cypressoai/evp` 的 Checks 还在 GitHub-hosted 上烧免费分钟。Sonar 已在 self-hosted；把 backend 测试、frontend lint/build、镜像构建也迁走。
- 影响：同机 8GB 上的 `mas-go-dev-ci-1` 会跑临时 Postgres 容器和四次 `docker build`。不占用 `shared-sit` / `mas-go-dev` 部署 runner，不绑宿主机 5432（`shared-sit-postgres` 已占用）。
- 选型：
  - frontend：`[self-hosted, frontend-quality-ci]`，可落到 mac-mini / lemon / mas-go-dev-ci。
  - backend 测试 + 镜像：`[self-hosted, Linux, docker, backend-ci]`。当前只有 `mas-go-dev-ci-1` 同时有这些标签（`ci-2` 无 docker）。
  - 不用 GHA `services:` 映射 5432；job 里 `docker run -p 127.0.0.1::5432` 拿随机端口，结束 `docker rm -f`。
  - 四镜像改为一个 job 内串行构建，避免单 runner 上 4 个 docker build 抢内存。
- 备份：只改 evp 仓库 workflow / 文档，未改本机 Docker、runner label、SIT compose。
- 回滚方式：把 `evp/.github/workflows/ci.yml` 的 backend / frontend / images 改回 `ubuntu-latest` 并恢复 `services.postgres`。
- 做了什么：
  1. 只读确认 `actions-runner` 可用 docker、`127.0.0.1:5432` 已被 shared-sit 占用、可用内存约 5.4GiB。
  2. 改 `ci.yml` 去掉全部 `ubuntu-latest`。
  3. 更新 evp `docs/deployment.md` 与本仓 runner 池对照表。
- 验证结果：以 push 后 Checks run 为准（backend / frontend / images 均应落 self-hosted，且无 GitHub-hosted 计费 runner）。

## 2026-09-09 12:24 CST - EVP Deploy SIT workflow 首次跑通

- 服务器：`mas-go-dev`（runner `shared-sit`）
- 操作人：`Grok`
- 原因：为 `cypressoai/evp` 接上 `shared-sit` 组的自动部署。
- 影响：仓库新增 `.github/workflows/deploy-sit.yml` 与 `deploy/sit/{docker-compose.yml,deploy.sh}`。本机 `/opt/evp-sit` 由该 job 同步并 `compose build` / migrate / `up -d`。未动 iCare。
- 备份：无（脚本不删 volume，不用 `--remove-orphans`）。
- 回滚：`docker tag evp/<svc>:sit-<sha> evp/<svc>:sit` 后在 `/opt/evp-sit` 执行 `docker compose up -d --no-build`。
- 验证：
  - Actions [Deploy SIT #34310755339](https://github.com/cypressoai/evp/actions/runs/34310755339) success（29s，镜像层 CACHED）。Runner name/group 均为 `shared-sit`。
  - 日志 `sit deploy ok sha=ff6f6a418b4f93f33eba6aa7b86b41de51c86099`；四条 `/health/ready` ok。
  - 本机 Tailscale `25173`/`25174` health 200。iCare `redis` running、`api` healthy。

## 2026-09-09 12:16 CST - 创建 shared-sit runner 组并注册本机 runner

- 服务器：`mas-go-dev`
- 操作人：`Grok`（用户确认按 `shared-sit` 组创建并注册）
- 原因：EVP SIT 自动部署不能进 iCare 专用组 `mas-go-dev`。
- 影响：GitHub org 新增 runner group `shared-sit`（id 6，selected 仅 `cypressoai/evp`）。本机新增 systemd runner `actions.runner.cypressoai.shared-sit`。未改 iCare 三套 runner、未改 Docker 业务容器。
- 选型：
  - 目录 `/opt/actions-runner/shared-sit/`，用户 `actions-runner`，版本 2.337.0（与现网一致）。
  - 名字 / label：`shared-sit`；保留默认 `self-hosted` `Linux` `X64`，另加 `docker` `al2023`。**不**贴 `mas-go-dev` / `backend-ci` / `frontend-quality-ci`。
  - `/opt/evp-sit` 属主改为 `actions-runner`，便于后续该 runner 写部署目录；共享层 `/opt/shared-sit` 仍属 `ec2-user`。
- 备份：`/tmp/shared-sit-runner-before-20260909-041448/`（systemd / docker ps / 目录属主）。registration token 用完即删。
- 回滚：
  ```bash
  sudo /opt/actions-runner/shared-sit/svc.sh stop
  sudo /opt/actions-runner/shared-sit/svc.sh uninstall
  sudo -u actions-runner /opt/actions-runner/shared-sit/config.sh remove --token <新 remove token>
  ```
  然后在 org 删除 group id 6。iCare runner 不在回滚范围内。
- 变更时序：
  1. `POST /orgs/cypressoai/actions/runner-groups`，`selected_repository_ids=[1361034755]`（`cypressoai/evp`）。
  2. 下载 runner 包、`config.sh --unattended --runnergroup shared-sit`，`svc.sh install actions-runner` + `start`。
  3. 写入 `.env`（`GOCACHE` 独立，`GOMODCACHE` 与同机其它 slot 共享）。
- 验证：
  - 组 6 仓库只有 `cypressoai/evp`；组 3 仍是 7 个 iCare 相关仓。
  - GitHub：`shared-sit` **online**，labels `self-hosted, Linux, X64, docker, al2023, shared-sit`，busy=false。
  - systemd enabled/active；iCare 三套 runner 仍 active。EVP 四容器仍 healthy。
- 后续：在 `cypressoai/evp` 加 deploy workflow，`runs-on.group: shared-sit`。Checks 继续 `ubuntu-latest`。

## 2026-09-09 11:41 CST - 共享 Redis + 部署 EVP SIT 四容器

- 服务器：`mas-go-dev`（Tailscale `100.109.223.53`）
- 操作人：`Grok`（用户要求公共层补 Redis，并部署 EVP 四个容器）
- 原因：后续项目肯定用 Redis；EVP SIT 先借住本机，独立 compose、只走 Tailscale。
- 影响：
  - 新增 `shared-sit-redis`（`6380`，requirepass + AOF）。iCare `redis:6379` 未改。
  - 新增 compose `evp-sit`：provider/admin 的 api+web 四个容器。未动 `/opt/mas-go-dev`。
- 选型：
  - Redis 镜像与 iCare 相同 `redis:7-alpine` digest，**容器名不能叫 `redis`**（已被 iCare 占用）。网络别名 `redis` 仅在 `shared-sit`。宿主端口 `6380`。
  - EVP 当前代码不用 Redis（会话在 Postgres）；租户连接串先写好 DB `/1`，应用未注入。
  - EVP 源码 rsync 到 `/opt/evp-sit/src/`，本机 `docker compose build`（未用 iCare runner）。
  - 端口：医院 `25173` / 管理 `25174`，API `28081` / `28082`，只绑 Tailscale + 回环。`S3_BUCKET` 空。
- 备份：新服务无旧数据。iCare Redis 未重建。
- 回滚：
  ```bash
  docker compose -f /opt/evp-sit/docker-compose.yml --project-directory /opt/evp-sit stop
  docker compose -f /opt/shared-sit/redis/docker-compose.yml --project-directory /opt/shared-sit/redis stop
  ```
  保留 volume，不要 `down -v` / `--remove-orphans`。
- 变更时序：
  1. 起 Redis，AUTH `PONG`，无密码 `NOAUTH`；iCare `PING` 仍通。
  2. 构建并启动两 API → `manage migrate` → 创建 `platform.admin` / `hospital.admin`。
  3. 构建并启动两前端。
- 验证：
  - 四容器 healthy。本机 Tailscale 打开 `/` 与 `/health/ready` 均为 200。
  - 医院/管理登录 200 且种上对应 session cookie；缺 Origin 返回 403。医院前端访问 `/api/admin/v1` 为 404。
  - 空闲内存：四容器合计约 35MiB，Redis 约 4MiB。iCare api healthy。
- 账号密码见本机 `mas-go-dev/secrets.local.md`（gitignore）。入口见 `mas-go-dev/README.md`。

## 2026-09-09 11:14 CST - 部署共享 SIT PostgreSQL 与 Garage

- 服务器：`mas-go-dev`（PVE VM `130`，Tailscale `100.109.223.53`）
- 操作人：`Grok`（用户确认本机作为多项目 SIT 合部署 VM，先上公共 Postgres / Garage）
- 原因：EVP 及其后项目的 SIT 借住本机；每个项目各自起一份数据库/对象存储更浪费，也比再开 VM 更吃 PVE 内存。
- 影响：新增独立 compose `shared-sit-postgres`、`shared-sit-s3` 与 Docker 网络 `shared-sit`。未改 `/opt/mas-go-dev`、未加入 iCare `shared-services`。端口只绑 `127.0.0.1` 与 `100.109.223.53` 的 `5432` / `3900`。
- 选型：
  - 目录 `/opt/shared-sit/`，属主 `ec2-user`，不放进 runner 管理的 `/opt/mas-go-dev`。
  - PostgreSQL **18.6**（`postgres:18-alpine` 钉 digest，与 mac-mini / `dev-cypresso` 共享库大版本一致），`restart: always`，内存上限 1 GiB、CPU 上限 1 核、`shared_buffers=128MB`、`max_connections=80`。
  - Garage **v2.3.0** 单节点 SQLite，区域 `ap-southeast-1`，内存上限 512 MiB。不启用 website / Funnel。
  - 与 mac-mini `shared-dev-*` 分离：那边给笔记本调试，这边给 SIT。
  - 首个租户 EVP：角色/库 `evp`（非超级用户，连接上限 40）、bucket `evp`、key 名 `evp-sit`（只读写该 bucket）。
- 备份：`/opt/shared-sit/backup-before-*/state.txt`（变更前 `docker ps` / compose / 端口 / 内存）。新实例无旧数据。
- 回滚方式：
  ```bash
  docker compose -f /opt/shared-sit/postgres/docker-compose.yml --project-directory /opt/shared-sit/postgres stop
  docker compose -f /opt/shared-sit/s3/docker-compose.yml --project-directory /opt/shared-sit/s3 stop
  ```
  保留 named volume `shared_sit_pg_data` / `shared_sit_s3_data`，不要 `down -v`。
- 变更时序：
  1. 写 compose 到 `/opt/shared-sit/`，建外部网络 `shared-sit`，生成 600 凭据后 `up -d`。
  2. 首轮把 SQL 文件 `docker cp` 进容器，postgres 用户读 600 文件 Permission denied；改为 `psql` stdin 后租户初始化成功。
  3. Garage `--single-node` 自动 layout；`key create evp-sit` + `bucket create evp` + `allow --read --write`。
- 验证：
  - 两容器 healthy。本机 Tailscale `nc` 通 `100.109.223.53:5432` / `:3900`；`192.168.2.22:5432` 不通。
  - `evp` 可在本库建表写入；连接 `postgres` 库被拒绝。
  - 经 Tailscale 对 bucket `evp` 做 PUT/GET/DELETE 探针对象成功后删除。
  - 空闲内存约 postgres 56MiB / Garage 13MiB。
  - 同期 iCare `api`/`worker`/`ecom`/`sup` 被 **本机已在跑的 GitHub Actions / buildkit** 滚动（StartedAt 约 03:13 UTC），不是 shared-sit compose recreate；`azurite` / `redis` / 门户未动。事后 `api`/`ecom`/`sup` healthy。
- 备注：当前 EVP 代码无 `S3_ENDPOINT`，SIT 应用先留空 `S3_BUCKET` 即可启动。档案 `mas-go-dev/README.md`，凭据 `mas-go-dev/secrets.local.md`（gitignore）。

## 2026-09-09 10:57 CST - 只读评估能否把 EVP SIT 放到本机

- 服务器：`mas-go-dev`（PVE VM `130`，Tailscale `100.109.223.53` / 内网 `192.168.2.22`）
- 操作人：`Grok`
- 原因：用户计划把 `/Users/konghai/Code/Project/evp` 的 SIT 部署到 `100.109.223.53`，需先确认这台机是什么、现占用、端口与资源是否允许轻量共存。
- 影响：只读；未改 Docker / compose / runner / 防火墙，未创建目录或容器。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：`ssh mas-go-dev` 查 hostname、内存、磁盘、`docker ps`/`stats`、监听端口、compose 项目、`/opt`；对照 PVE 宿主机 `qm config 130` 与节点内存。
- 验证结果：
  - 本机就是 iCare MAS Go 内网 SIT + org runner，不是空 VM。规格 4 vCPU / 8 GiB / 300G，根盘约 73G/300G（25%）。
  - 运行中 compose：`frontend-mas`、`icare-backend`（5）、`icare-backend-infra`（azurite+redis）、`icare-public-backend`（3）、`public-frontend`（2）、`vps-traffic-monitor`。无 PostgreSQL 端口。
  - 空闲时 available 约 4.4Gi；采样时有 CI buildkit（约 1.65Gi / 42% CPU），load 3.88，swap 已用 1.1Gi。
  - EVP 本地 compose 端口 `25173/25174/28081/28082/54329` 本机未占用。仓库 `compose.yaml` 绑 `127.0.0.1`，不能原样给 Tailscale 客户端用。
  - 结论留给对话：短期可独立 compose 项目挤进去；长期不建议把 EVP SIT 绑在这台 iCare 专用机。PVE 宿主机 31Gi 已用约 29.4Gi 且在用 swap，短期也很难再开独立 VM 或给本机加内存。

## 2026-08-24 23:18 CST - 后端与 public-backend 切到 ihc20260824 新 catalog

- 服务器：`mas-go-dev`
- 操作人：`Grok`（用户确认 SIT 无人测试、可不考虑中断）
- 原因：mssql-ref 已恢复 10.100.0.4 最新库；应用仍指旧 catalog。
- 影响：
  - `.env.docker`：`WEBKIT_DB_NAME=maswebkit_preprod`，`SALESPORTAL_DB_NAME=insularsalesportal_preprod`
  - `.env.ecom`：`PREPAID_DB_NAME=masprepaid_preprod`，`AUTH_DB_NAME=authprovidermasuat_preprod`
  - `.env.sup`：`SALESPORTAL_DB_NAME=insularsalesportal_preprod`，`AUTH_DB_NAME=authprovidermasuat_preprod`
  - public-backend `.env.{app,hr,map}`：`WEBKIT_DB_NAME=maswebkit_preprod`
  - `DB_NAME` 已是 `medicalassistance_preprod`（新 bak），未改。
  - 以当前镜像 `--no-build --force-recreate` 重建 api/worker/ecom-api/sup-api/public-app/hr/map。
- 备份：`/opt/mas-go-dev/backend/.env.{docker,ecom,sup}.bak.20260824-ihc-cut`；public-backend 同戳。
- 回滚：用上述 bak 覆盖 env 后同样 `--force-recreate --no-build`。
- 验证：容器 healthy；日志 `database connected` 到新 catalog（api: 主库 + maswebkit_preprod + insularsalesportal_preprod；ecom: 主库 + authprovidermasuat_preprod；sup: 主库 + insularsalesportal_preprod + authprovidermasuat_preprod；hr: maswebkit_preprod）。
- 相关：`mssql-ref/databases.md`；ecom/sup auth 用户在新库的授权见 `docs/operations/mssql-ref.md` 同时段。

## 2026-08-22 18:40 CST - 只读确认 Operations Portal UAT verify 失败是单测，不是 pnpm PATH

- 服务器：`mas-go-dev`（runner `mas-go-dev-ci-1`）
- 操作人：`Grok`
- 原因：业务仓 session 把 iCare-Operations-frontend 失败归因为自托管 runner `pnpm: command not found`。本机实际领到的是 [Deploy Azure UAT run 32567471377](https://github.com/cypressoai/iCare-Operations-frontend/actions/runs/32567471377) / Job [97018102290](https://github.com/cypressoai/iCare-Operations-frontend/actions/runs/32567471377/job/97018102290)。
- 影响：只读；未改 runner、`PNPM_STORE_PATH`、workflow，未重跑。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：读 Job 日志与 `deploy-azure-uat.yml`。
- 验证结果：
  - `pnpm/action-setup@v4` success，装上 pnpm 11.18.0；`pnpm install --frozen-lockfile` **Done in 4.6s**。不是 PATH / action-setup 失效。
  - 失败在 `Install and verify` 里的 `pnpm test:coverage`：2 files / **11 tests failed**（24 passed）。断言期望 `fetch('/session/v1/login')` 等相对路径，实际打到 `https://icare2-uat-operations-api.ambitioussea-…`。同 step 导出了 `VITE_API_BASE_URL`（给 `pnpm build` 写死 UAT API origin），vitest 一并吃到，测试环境被污染。
  - 更早的 dispatch [32565550318](https://github.com/cypressoai/iCare-Operations-frontend/actions/runs/32565550318) 未分配 runner：OIDC `claim 'environment' cannot be null`（workflow-level `id-token: write`），与 pnpm 无关；已在后续 yaml 里改成只给 deploy job 开 OIDC。
  - `Upload private SWA` 因 quality 红而 skipped，属连带，不是 runner 挂了。
- 修法在业务仓：UAT quality 的 test 不要带 `VITE_API_BASE_URL`，或测试里对 base URL 做归一化。重跑同一 SHA 仍会红。

## 2026-08-17 17:35 CST - 只读确认 Backend Deploy #32010421100 失败为 swagger 注解冲突

- 服务器：`mas-go-dev`（self-hosted runner `mas-go-dev`）；对照 GitHub Actions `Backend Deploy`
- 操作人：`Grok`
- 原因：用户指向 [iCare-backend Actions run 32010421100](https://github.com/cypressoai/iCare-backend/actions/runs/32010421100)，需判断是 runner / 磁盘 / 部署脚本问题，还是代码侧构建失败。
- 影响：只读查 `gh run view` 与 `develop` 上的 handler 注解；未改 runner、Docker、compose、`.env.docker`，未重跑 Job，未重启容器。
- 备份：无（只读）。
- 回滚方式：无变更。当前 SIT 仍停在上一趟成功部署（`fix(CYP-2160)` / run [32003652368](https://github.com/cypressoai/iCare-backend/actions/runs/32003652368)），本次镜像未构建成功，容器未被覆盖。
- 做了什么：
  1. 核对 run 结论：`Set Environment Variables` 成功；`Deploy to mas-go-dev` 与 `Build and Push Docker Image` 均在 Docker 构建阶段失败；`Build and Test` / `Deploy to Server` 被跳过。
  2. 两边失败步骤相同：`Dockerfile:23` 的 `RUN bash ./scripts/generate-swagger.sh`。
  3. 脚本本身先生成 Swagger 2.0 成功，失败发生在 `go run ./cmd/openapi-conv`：`convert to openapi 3: body and form parameters cannot exist together for the same operation`。
  4. 本趟触发提交是 [iCare-backend#1525](https://github.com/cypressoai/iCare-backend/pull/1525)（CYP-2164 help-center 列表过滤，`eb41b77`），但同一错误已在前一趟 [run 32004994057](https://github.com/cypressoai/iCare-backend/actions/runs/32004994057) / [iCare-backend#1523](https://github.com/cypressoai/iCare-backend/pull/1523)（CYP-2162 MAP 头像 multipart）出现。
  5. 核对 `develop` 上 `UploadProfileImage` 的 swag 注解：同一 `POST /internal/public/v1/members/{membercode}/profile-image` 同时写了 `@Accept json,mpfd`、`@Param body body ...` 和 `@Param file formData file ...`。`kin-openapi` 转 OpenAPI 3 时不允许同一 operation 同时带 body 与 form 参数。
- 验证结果：
  - **不是** runner、磁盘、Buildx、GHCR 登录或 mas-go-dev 运行时问题；`Verify mas-go-dev runtime`、checkout、Buildx 均成功。
  - **是** 代码侧 swagger 契约冲突。#1525 只是叠在已坏的 #1523 之上，重跑本趟不会过。
  - 修法在 iCare-backend：把 JSON / multipart 拆成两个 route（或两套独立 `@Router`），或只给其中一种写 swag 参数，不能在同一个 operation 上同时声明 `body` 与 `formData`。
- 备注：Node.js 20 deprecation 只是 annotation，与本次失败无关。

## 2026-08-14 10:48 CST - App 同事确认 MAS LOA Discussion 真机推送通过

- 服务器：`mas-go-dev`（内网 SIT）
- 操作人：`Grok`（记录）；真机验证由开发 App 的同事完成
- 原因：09:47 打开 `iCare-backend` FCM、10:45 确认部署后挂载仍在之后，补齐 handoff 要求的端到端验收。
- 影响：无服务器改动。
- 备份：无（只记录）。
- 回滚方式：无变更。
- 做了什么：同事在内网 MAS 发出 LOA Discussion，用已登录 App 的真机查收。
- 验证结果：同事回复 **「app 上能收到推送」**。整条链路已通：
  MAS LOA 页面 → 内网 `iCare-backend` → FCM → APNs → App。
  公网 `public-backend` 仍只负责登录 / 存 token / 读通知，无需再改。

## 2026-08-14 10:45 CST - 只读确认 #1500 合并后 FCM 挂载在后续部署中仍生效

- 服务器：`mas-go-dev`（内网 SIT）
- 操作人：`Grok`
- 原因：[iCare-backend#1500](https://github.com/cypressoai/iCare-backend/pull/1500) 已合并并自动部署；需确认 compose 覆盖后 `api` / `worker` 仍能读到 FCM 凭证，没有退回 `fcm push disabled` 或因缺文件起不来。
- 影响：只读检查 GitHub Actions 与本机容器 / 挂载 / 日志 / 探活；未改配置、未重启、未发真实推送。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：
  1. 核对 #1500 合并提交 `943acb5a`，Backend Deploy [31762295839](https://github.com/cypressoai/iCare-backend/actions/runs/31762295839) 成功（含 `Deploy to mas-go-dev`）。
  2. 再核对其后的 [CYP-2123](https://github.com/cypressoai/iCare-backend/actions/runs/31763823982) 部署也成功；本机当前跑的是这趟镜像 `icare/backend:mas-go-dev-d53eb812…`（2026-08-14 10:35 CST 起来）。
  3. 检查本机 `backend.compose.yaml`（02:35 被 deploy 覆盖）、`.env` / `.env.docker`、凭证文件与容器挂载、启动日志、探活。
- 验证结果：
  - 部署覆盖后的 compose 仍带 `${BACKEND_FCM_CREDENTIALS_FILE:-/dev/null}:/run/secrets/fcm-sa.json:ro`（`api` 与 `worker`）。
  - 主机 `.env` / `.env.docker` 与 `fcm-service-account.json` 未被 deploy 改动（仍是 01:44 那一版）。
  - 容器内 `FCM_ENABLED=true`，挂载 `fcm-service-account.json -> /run/secrets/fcm-sa.json (ro)`，属主 `10001:999`。
  - `api` / `worker` 均报 `fcm push sender ready project=icare-dev-3c465`；`api` healthy、`RestartCount=0`。
  - `127.0.0.1:8080/healthz`、`5174/healthz`、`5174/api/v1/health` 均为 200。
  - 结论：#1500 的挂载已进入 develop 部署链路，**后续常规部署不会再冲掉 FCM**。真机横幅当时待同事验证；10:48 已确认 App 能收到推送。

## 2026-08-14 09:47 CST - 打开 iCare-backend FCM 真实发送（MAS LOA Discussion）

- 服务器：`mas-go-dev`（内网 SIT，`192.168.2.22`）
- 操作人：`Grok`
- 原因：App 同事要验证 MAS 发出的 LOA Discussion 能否出 iPhone 横幅。这条链路由 `iCare-backend` 发送，与已配好的公网 `public-backend` FCM 是两套独立配置。此前 `api` / `worker` 日志为 `fcm push disabled`，discussion 会落库但不推送。
- 影响：仅重建 `icare-backend-api-1` 与 `icare-backend-worker-1`（约数秒不可用）；未改 ECOM / SUP / public-backend / MAS portal / 数据库。FCM 为出站访问 Google，不暴露新端口。
- 备份：
  - `/opt/mas-go-dev/backend/.env.docker.bak.20260814-fcm`
  - `/opt/mas-go-dev/backend/backend.compose.yaml.bak.20260814-fcm`
- 回滚方式：
  ```bash
  BASE=/opt/mas-go-dev/backend
  sudo cp -a $BASE/.env.docker.bak.20260814-fcm $BASE/.env.docker
  sudo cp -a $BASE/backend.compose.yaml.bak.20260814-fcm $BASE/backend.compose.yaml
  sudo rm -f $BASE/.env $BASE/fcm-service-account.json
  IMG=$(sudo docker inspect icare-backend-api-1 --format '{{.Config.Image}}')
  sudo env BACKEND_IMAGE="$IMG" docker compose --project-directory $BASE \
    -f $BASE/backend.compose.yaml up -d --no-deps --force-recreate --pull never api worker
  ```
  回滚后日志应回到 `fcm push disabled`；MAS 保存 discussion 仍可用，只是不再真发推送。
- 变更时序：
  1. 从同机已验证的 `public-backend` 服务账号复制到 `/opt/mas-go-dev/backend/fcm-service-account.json`（`600`，`uid=10001 gid=999`），Firebase 项目 `icare-dev-3c465`。
  2. 在主机维护的 `.env.docker` 追加 `FCM_ENABLED=true`、`FCM_CREDENTIALS_FILE=/run/secrets/fcm-sa.json`、`FCM_PROJECT_ID=icare-dev-3c465`、`FCM_TIMEOUT=10s`。未写入 ecom/sup env，避免非 mas profile 启动失败。
  3. 新增 compose `.env`：`BACKEND_FCM_CREDENTIALS_FILE=/opt/mas-go-dev/backend/fcm-service-account.json`（只给 volume 插值，不入库）。
  4. `api` / `worker` 增加只读挂载 `${BACKEND_FCM_CREDENTIALS_FILE:-/dev/null}:/run/secrets/fcm-sa.json:ro`。
  5. 显式复用当前镜像 `icare/backend:mas-go-dev-80c1eb54…`，`--no-deps --force-recreate --pull never` 重建 `api` + `worker`，未跑 seed、未 `--remove-orphans`。
  6. 源仓同步：[iCare-backend#1500](https://github.com/cypressoai/iCare-backend/pull/1500)。**该 PR 合并前若有其它 backend 部署，会覆盖本机 compose、丢掉挂载**；而 `.env.docker` 仍是 `FCM_ENABLED=true`，`api` 会因读不到凭证起不来。合并前请先合 #1500，或临时把 `FCM_ENABLED` 改回 `false`。
- 验证：
  - `api` `healthy`、`RestartCount=0`；`worker` `running`、`RestartCount=0`。
  - 两边日志：`fcm push sender ready project=icare-dev-3c465`。
  - 挂载：`/opt/mas-go-dev/backend/fcm-service-account.json -> /run/secrets/fcm-sa.json (ro)`。
  - 本机用服务账号换 FCM access token：`TOKEN_OK expires_in=3599`；对无效 token 调 FCM v1 返回 `400 INVALID_ARGUMENT`（鉴权与出网通过，不是 `401/403`）。
  - `http://127.0.0.1:5174/healthz` 与 `/api/v1/health` 仍为 200。
  - maswebkit 中已有设备 token 记录（历史数据，未读取或下发任何真实 token）。
  - 当时未做真机横幅。后续见 10:48 条目：App 同事确认能收到推送。
- 备注：公网 `dev-cypresso` 的 `public-backend` FCM 保持不动（App 登录 / 存 token / `test-dispatch` 仍走那里）。`mas-icare.cypress.sg` 仍是 SIT 结束说明页，不要为这条链路重开。

## 2026-08-13 01:21 CST - 只读确认 iCare-backend Sonar 失败为 mac-mini 服务不可达

- 服务器：`mas-go-dev`（self-hosted runner `mas-go-dev-ci-2`）；对照 `mac-mini` SonarQube 与 `umacbook-pro-2`
- 操作人：`Codex`
- 原因：排查 [iCare-backend Job 94190148086](https://github.com/cypressoai/iCare-backend/actions/runs/31617573433/job/94190148086) 是 runner 侧还是代码侧失败。
- 影响：仅通过 `gh` 读取 Actions / PR 日志，并 SSH 只读检查 runner 服务、MagicDNS 与 SonarQube HTTP 连通性；未改 runner、Tailscale、Docker、SonarQube、workflow 或业务代码，未重跑 Job。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：
  1. 核对目标 Job 全部步骤及同一时段前后 SonarQube workflow runs。
  2. 在 `mas-go-dev` 检查 `mac-mini` 短名解析、`http://mac-mini:9000/api/system/status` 连通性及两台 runner systemd 服务状态。
  3. 对照 `umacbook-pro-2` 上另一条 Sonar Job 的同型失败，并在 `mac-mini` 检查 Docker API、SonarQube 端口与宿主机运行时间。
- 验证结果：
  - 目标 Job 的 checkout、Go 1.25.7、C toolchain、依赖下载、全量测试与 coverage 合并全部成功；唯一失败为 SonarScanner 查询 `SONAR_HOST_URL` 的 `/api/v2/analysis/version`，报 `Failed to query server version` 并退出 1，因此不是业务代码或测试失败。
  - `mas-go-dev-ci-1/2` systemd 服务均为 `active`；`getent hosts mac-mini` 正确解析到 Tailscale 地址 `100.108.64.126`，排除 2026-08-02 曾发生的 MagicDNS 故障；但访问 `mac-mini:9000` 立即 connection refused。
  - 同一时段稍后的 run `31617651468` 落到 `umacbook-pro-2`，也在测试和 coverage 成功后报完全相同的 Sonar server version 查询失败，排除 `mas-go-dev-ci-2` 单 runner 故障。
  - `mac-mini` 已运行 22 天、无本次时段重启；但 Docker Desktop 主进程不在、`~/.docker/run/docker.sock` 不存在、TCP 9000 无监听，仅 `com.docker.vmnetd` helper 存活。结论：**基础设施 / SonarQube 宿主侧故障，具体为 mac-mini 上 Docker Desktop 未运行，导致 SonarQube 容器不可达；不是代码侧问题，也不是目标 runner 自身故障。**
  - 未启动 Docker Desktop、未拉起 SonarQube、未重跑 CI；这些恢复动作需另行确认。

## 2026-08-12 12:47 CST - 补齐 SUP AUTH_DB 配置并恢复外部 API

- 服务器：`mas-go-dev`（本地 SIT）
- 操作人：`Codex`
- 原因：Actions run `31561010370` 升级 SUP 至新镜像后，`.env.sup` 缺少 `AUTH_DB_*`，容器在启动前报 `AUTH_DB_ENABLED must be true when APP_SERVICE_PROFILE=sup` 并循环重启。
- 影响：仅更新 `.env.sup` 的 8 个 `AUTH_DB_*` 项，重建单个已不可用的 `icare-backend-sup-api-1`；未改 ECOM、MAS API、worker、OAuth 数据、业务数据或 schema。
- 备份：`/opt/mas-go-dev/backend/.env.sup.bak.20260812-1235-sup-authdb`。
- 回滚方式：恢复上述 `.env.sup` 备份后，以当前 SUP 镜像执行 `docker compose -f backend.compose.yaml --profile external-api up -d --no-deps --force-recreate sup-api`；确认两台 SIT 不再使用 SUP 专用身份后，由 SA 删除相应 SQL user/login（见 `mssql-ref` 同时段记录）。
- 变更时序：通过 `sudo` 操作 `actions-runner` 管理的 env，使用该 VM 专属、最小权限的 SUP SQL 身份（仅 `CONNECT` + `SELECT dbo.oauth_clients`）；沿用现有 DB host / port / encrypt 链路，`AUTH_DB_NAME=authprovidermasweb`；显式复用 Actions 部署镜像 `icare/backend-sup:mas-go-dev-9e99fc71…`，以 `--no-deps --force-recreate --pull never` 重建。未清理 orphan `gotenberg`。
- 验证：SUP `/api/v1/health` 第 2 次探测通过且 `auth_database=up`；最终 ECOM 与 SUP 均为 `running`、Docker health `healthy`、`RestartCount=0`。

## 2026-08-12 12:35 CST - 只读确认 iCare-backend CI 红叉为 Draft PR 门禁

- 服务器：`mas-go-dev`（jobs 分别落在 `mas-go-dev-ci-1/2`）
- 操作人：`Codex`
- 原因：排查 [iCare-backend Actions run 31561543745](https://github.com/cypressoai/iCare-backend/actions/runs/31561543745) 的 `Lint` 与 `SonarQube Scan` 同时失败，判断是 runner 侧还是代码侧问题。
- 影响：仅通过 GitHub 页面/API 读取 run、job、PR 与 workflow 状态；未 SSH 登录服务器，未改 runner、workflow、PR 状态或业务代码，未重跑 job。
- 备份：无（只读）。
- 回滚：无变更。
- 验证：
  - attempt 2 的 `Lint` 在 `mas-go-dev-ci-2`、`SonarQube Scan` 在 `mas-go-dev-ci-1`；两台 runner 均使用版本 `2.336.0`，`Set up job` 成功并正常下载所需 Actions，排除 runner 初始化或网络下载故障。
  - 两个 job 都在第一个业务步骤 `Block while draft` 命中 `github.event.pull_request.draft == true`，日志明确输出 `CI is intentionally not run` 后按 workflow 设计执行 `exit 1`；后续 checkout、Go、lint、test 与 Sonar 步骤全部 skipped，业务代码实际上未被检查。
  - PR [#1467](https://github.com/cypressoai/iCare-backend/pull/1467) 当前 `isDraft=true`；attempt 1 与 attempt 2 行为一致。结论：不是 runner 故障，也不是业务代码失败，而是 Draft PR 的预期 required-check 门禁；将 PR 标记为 Ready for review 后，`ready_for_review` 事件会自动触发真实 CI。

## 2026-08-12 12:21 CST - 补齐 ECOM AUTH_DB 配置并恢复外部 API

- 服务器：`mas-go-dev`（本地 SIT）
- 操作人：`Codex`
- 原因：新 ECOM 镜像要求独立的 `AUTH_DB_*` 连接读取 `authprovidermasweb.dbo.oauth_clients`，但既有 `.env.ecom` 未配置，导致容器启动前退出并循环重启。
- 影响：仅更新 `/opt/mas-go-dev/backend/.env.ecom` 的 8 个 `AUTH_DB_*` 项，并强制重建原本已不可用的 `icare-backend-ecom-api-1`；未改 API、worker、SUP、业务数据、数据库表结构或 OAuth 客户端数据。
- 备份：`/opt/mas-go-dev/backend/.env.ecom.bak.20260812-1205-authdb`。
- 回滚方式：恢复上述 `.env.ecom` 备份后，以当前 ECOM 镜像执行 `docker compose -f backend.compose.yaml --profile external-api up -d --no-deps --force-recreate ecom-api`；确认两台 SIT 均不再使用对应独立身份后，由 SA 删除其 `authprovidermasweb` user 与 SQL login（见 `docs/operations/mssql-ref.md` 同时段记录）。
- 变更时序：
  1. 使用独立、最小权限的 ECOM SQL 身份（仅 `CONNECT` + `SELECT dbo.oauth_clients`）替代缺失配置；密码仅写入本机 `.env.ecom`，未输出或提交。
  2. `AUTH_DB_HOST` / `PORT` / `ENCRYPT` 沿用该环境现有数据库链路，`AUTH_DB_NAME=authprovidermasweb`。
  3. 通过 `sudo` 操作 `actions-runner` 管理的部署目录，显式复用当前 ECOM 镜像 `icare/backend-ecom:mas-go-dev-9e99fc71…`，以 `--no-deps --force-recreate --pull never` 重建单个 ECOM 容器；未清理 compose 提示的 orphan `gotenberg`。
- 验证：HTTP `/api/v1/health` 在第 2 次探测通过且 `auth_database=up`；最终容器 `running`、Docker health `healthy`、`RestartCount=0`。

## 2026-08-12 11:52 CST - 只读确认 ECOM 部署失败为缺失 AUTH_DB 配置

- 服务器：`mas-go-dev`（本地 SIT）
- 操作人：`Codex`
- 原因：与远端 SIT Server 同次 ECOM readiness 失败；恢复 `iCare backend ECOM deployment failure diagnosis` 交接后，需确认本地 SIT 是否存在相同启动前置条件缺失。
- 影响：只读检查 Docker 容器状态、最近 200 行日志及 `/opt/mas-go-dev/backend/` 下 `.env.ecom` / `.env.docker` 的 `AUTH_DB_*` 键是否存在或非空；未读取或输出密码、连接值，未改配置、未重启或重建容器。
- 备份：无（只读）。
- 回滚：无变更。
- 验证：
  - `icare-backend-ecom-api-1`（`icare/backend-ecom:mas-go-dev-9e99fc71…`）处于 `Restarting (1)`，检查时 `RestartCount=9`、`ExitCode=1`；`api` healthy、`worker` Up，故影响限于 ECOM 外部 API。
  - 启动日志反复报：`AUTH_DB_ENABLED must be true when APP_SERVICE_PROFILE=ecom`。
  - `.env.ecom` 与 `.env.docker` 均未定义 `AUTH_DB_ENABLED`、`AUTH_DB_HOST`、`AUTH_DB_PORT`、`AUTH_DB_USER`、`AUTH_DB_PASSWORD`、`AUTH_DB_NAME`；与 `dev-cypresso` 一致，确定为两套 SIT 环境均未供应 ECOM 的外部 OAuth 数据库配置。

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`mas-go-dev`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：CLEAN（误报名碰撞）。/opt/actions-runner/*/_work 下 motion-dom setup.mjs；哈希非恶意；preinstall=0。兼 CI+SIT。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

## 2026-08-04 19:48 CST - 修正 public-backend `MAS_INTERNAL_API_HEALTH_PATH` 并恢复容器

- 服务器：`mas-go-dev`
- 操作人：`Grok`
- 原因：PR [#63](https://github.com/cypressoai/iCare-public-backend/pull/63) 合入后 Deploy 镜像构建成功，但 health 探针失败；容器日志：`MAS_INTERNAL_API_HEALTH_PATH: target must stay under /internal/public/v1`。本机 `.env.{app,hr,map}` 仍是 CYP-1782 迁移前的 `/internal/mobile/health`。
- 影响：
  - 更新三份 env 的 `MAS_INTERNAL_API_HEALTH_PATH` → `/internal/public/v1/health`
  - `--force-recreate` 拉起 `public-app` / `public-hr` / `public-map`（镜像 `icare/public-backend:mas-go-dev-c2ddf907…`）
- 备份：
  - `/opt/mas-go-dev/public-backend/.env.app.bak.20260804114821`
  - `/opt/mas-go-dev/public-backend/.env.hr.bak.20260804114821`
  - `/opt/mas-go-dev/public-backend/.env.map.bak.20260804114821`
- 回滚方式：
  ```bash
  ssh mas-go-dev 'BASE=/opt/mas-go-dev/public-backend
  for f in .env.app .env.hr .env.map; do
    sudo cp -a "$BASE/$f.bak.20260804114821" "$BASE/$f"
  done
  sudo env PUBLIC_BACKEND_IMAGE=$(sudo docker inspect --format "{{.Config.Image}}" icare-public-backend-public-app-1) \
    PUBLIC_APP_ENV_FILE=$BASE/.env.app PUBLIC_HR_ENV_FILE=$BASE/.env.hr PUBLIC_MAP_ENV_FILE=$BASE/.env.map \
    docker compose -f $BASE/public-backend.compose.yaml -f $BASE/public-backend.compose.mas-go-dev.yaml \
    up -d --force-recreate public-app public-hr public-map'
  ```
- 变更时序：
  1. 备份三份 env
  2. sed 替换 `HEALTH_PATH` 为 `/internal/public/v1/health`
  3. force-recreate 三容器
- 验证：
  - `8090/8091/8092` 的 `/api/v1/health/live` 均返回 `{"status":"up"}`
  - 容器 Up；app 日志 `service starting` + webkit connected
- 备注：GitHub Deploy run [30905855374](https://github.com/cypressoai/iCare-public-backend/actions/runs/30905855374) 仍记 failure（探针超时已失败）；本机已手工恢复。GHCR Build and Push 已 success（原 CGO/sqlite 问题已由 #63 修掉）。

## 2026-08-04 18:50 CST - 排查 public-backend CI 20m 超时（golangci-lint-action）

- 服务器：`mas-go-dev`（job 落在 `mas-go-dev-ci-1`；结论适用整个 `backend-ci` 池）
- 操作人：`Grok`（只读取证 + 业务仓 workflow PR；本机未改 runner）
- 原因：用户指向 [actions/runs/30898768407/attempts/1](https://github.com/cypressoai/iCare-public-backend/actions/runs/30898768407/attempts/1)，今日多次 CI 异常。
- 影响：无本机变更。诊断与修复落在业务仓 workflow。
- 取证摘要：
  - Annotation：`The job has exceeded the maximum execution time of 20m0s`
  - Runner：`mas-go-dev-ci-1`；步骤日志上 Test/Lint/Build 均 success，但 job 被 timeout cancel
  - `golangci-lint-action` GH cache restore ~16MB 卡在 0.1MB/s 后 timeout（prepare ~113s）；Post 仍 save cache ~63s
  - 真正 `golangci-lint run` 仅 ~4s、0 issues；lint endgroup 后约 15 分钟无日志
  - 同期其它失败：`config verify` 拉 `golangci-lint.run` jsonschema → `context deadline exceeded`（lemon / mas / umac）
  - attempt 2：`test-lint-build` 在 `lemon-imac-1` ~2min 成功；Sonar 在 `mas-go-dev-ci-2` **Quality Gate FAILED**（规则门禁，非 runner）
  - 排查窗口：家宽 Tailscale 对 `mas-go-dev` / mac-mini / lemon / umac **SSH 全超时**，未能读 `_diag`；GitHub API 显示 backend-ci runner 仍多为 online
- 修复：对齐 `iCare-backend`，去掉 action，改为 `go install` + `golangci-lint run`
  - PR：https://github.com/cypressoai/iCare-public-backend/pull/62
- 方案沉淀：`docs/solutions/mas-go-dev/workflow-issues/golangci-lint-action-cache-timeout-selfhosted-2026-08-04.md`
- 回滚：无本机回滚项；workflow 回滚见 PR
- 验证：合入 #62 后观察后续 `test-lint-build` 是否不再出现 cache restore timeout / golangci-lint.run deadline

## 2026-08-03 15:50 CST - CI 池加固：PNPM store + systemd timer + EnvironmentFile

- 服务器：`mas-go-dev`（AL2023，根盘 **300G**）
- 操作人：`Grok`（iCare 自托管 runner 运维加固任务）
- 原因：`mas-go-dev-ci-1/2` 承接 `frontend-quality-ci` + `backend-ci`；需本机 pnpm/go store 与定时清 work，且不破坏部署 runner / buildx。
- 影响：
  - CI 两 slot `.env` 增加 `PNPM_STORE_PATH=/var/cache/gha/pnpm-store`；保留 per-slot GOCACHE + 共享 GOMODCACHE
  - **部署 runner `mas-go-dev` 未加 PNPM**（职责不混）
  - 脚本：`/opt/gha-scripts/{gha-runner-maintenance.sh,prune-gocache.sh}`
  - 系统无 cronie → 用 **systemd timer**：
    - `gha-runner-maintenance.timer` 每日 03:15 UTC
    - `gha-runner-maintenance-weekly.timer` 周日 04:30 UTC
  - systemd drop-in `env.conf`：`EnvironmentFile=/opt/actions-runner/<slot>/.env`（Listener 进程可验证到 GO*/PNPM）
  - 目录：`/var/cache/gha/pnpm-store` 属主 `actions-runner`；日志 `/var/log/gha/maintenance.log`
  - 空闲时清 `_temp`；CI 两 slot 已 restart
- 备份：`/opt/actions-runner/*/.env.bak.*`；既有 `service.d/restart.conf` 未改
- 回滚：
  ```bash
  sudo systemctl disable --now gha-runner-maintenance.timer gha-runner-maintenance-weekly.timer
  sudo rm -f /etc/systemd/system/actions.runner.cypressoai.mas-go-dev-ci-{1,2}.service.d/env.conf
  # 恢复 .env.bak 后 systemctl restart 对应 service
  ```
- 验证：
  - `strings /proc/<Listener-pid>/environ` 含 `PNPM_STORE_PATH` / `GOCACHE` / `GOMODCACHE`
  - `systemctl list-timers 'gha*'` 已排程；根盘约 **28% / Avail 219G**
  - `/var/cache/buildx` **未动**
- 关联：`docs/runbooks/ci-runner-pools.md`

## 2026-08-02 18:26 CST - 开启 Tailscale accept-dns，恢复 mac-mini Sonar 解析

- 服务器：`mas-go-dev`（PVE VM `130`，Tailscale `100.109.223.53`）
- 操作人：`Grok`（用户确认方案 A）
- 原因：`iCare-backend` Sonar job 落到 `mas-go-dev-ci-*` 时报 `Failed to query server version`；根因是 `CorpDNS=false`，`http://mac-mini:9000` 无法解析（见上一条 18:18 排查）。
- 选型：只做 A（`tailscale set --accept-dns=true`），暂不加 `/etc/hosts` 兜底。
- 影响：
  - MagicDNS 恢复；系统 DNS 改为优先 Tailscale（`100.100.100.100`，search `taila93443.ts.net`）。
  - 未改 runner、Docker、Sonar 服务端、GitHub secrets / workflow。
- 备份：变更前 `tailscale debug prefs` → `CorpDNS: false`；IP 直连 `http://100.108.64.126:9000` 仍 UP。
- 回滚方式：
  ```bash
  sudo tailscale set --accept-dns=false
  ```
  回滚后 `mac-mini` 短名会再次解析失败，CI 再落到本机 Sonar 会挂。
- 变更时序：
  1. 预检：`CorpDNS false`；`curl http://mac-mini:9000` → could not resolve；IP 直连 200。
  2. `sudo tailscale set --accept-dns=true`（exit 0）。
  3. 验证解析与 HTTP。
- 验证：
  - `CorpDNS: true`
  - `getent hosts mac-mini` → `100.108.64.126 mac-mini.taila93443.ts.net`
  - `curl http://mac-mini:9000/api/system/status` 连续 3 次 HTTP **200**，`"status":"UP"`（~10–15ms）
  - FQDN `http://mac-mini.taila93443.ts.net:9000/...` 亦 200
- 备注：真实 CI 需等下次 `backend-ci` 调度到 `mas-go-dev-ci-*` 的 Sonar job 再确认 Scanner 端到端；本机连通性已恢复。

## 2026-08-02 18:18 CST - 只读排查：iCare-backend SonarQube Scan 间歇失败（mac-mini DNS）

- 服务器：`mas-go-dev`（runner `mas-go-dev-ci-1/2`）；对照 `mac-mini` SonarQube、`lemon-imac` / `umacbook-pro`
- 操作人：`Grok`
- 原因：用户反馈 GitHub Actions job 常失败，示例  
  https://github.com/cypressoai/iCare-backend/actions/runs/30742636487/job/91482673100
- 影响：只读排查，未改 Tailscale / DNS / runner / Sonar / workflow
- 备份：无
- 回滚：无（无变更）

### 现象

- Job：`SonarQube Scan`（workflow `SonarQube Analysis` / `.github/workflows/sonar.yml`）
- 失败 runner：`mas-go-dev-ci-2`（同 run 重试落到 `lemon-imac-2` 后成功）
- 测试与 coverage 步骤均通过；失败在最后 `SonarSource/sonarqube-scan-action`：
  ```
  ERROR Failed to query server version: Call to URL [***/api/v2/analysis/version] failed: null
  ```
- 同模式近期样例（connectivity，非 Quality Gate）：
  - `2026-08-02` run `30734946112` @ `mas-go-dev-ci-1`
  - `2026-08-01` run `30681716513` @ `mas-go-dev-ci-2`
- 注意：列表里另有一批 failure 是 **Quality Gate 未过**（exit code 3），与本连通性问题不同，例如 lemon 上的 QG fail。

### 根因链

1. 仓库 secret `SONAR_HOST_URL`（2026-05-13 迁移日更新）指向内网 `http://mac-mini:9000`（Sonar 已从 `sonar.cypresso.ai` / dev-cypresso 迁到 mac-mini）。
2. **mac-mini 上 Sonar 健康**：容器 `sonarqube` Up healthy；`curl http://127.0.0.1:9000/api/system/status` → `"status":"UP"`。
3. **lemon / umac 可达**：`curl http://mac-mini:9000/api/system/status` → HTTP 200。
4. **mas-go-dev 不可解析 `mac-mini`**：
   - `tailscale debug prefs` → **`CorpDNS: false`**（未接受 MagicDNS / accept-dns）
   - `resolvectl`：`tailscale0` DNS scope = none；系统 DNS 仅 `192.168.2.1`（search 虽有 `taila93443.ts.net` 但上行解析器不认 tailnet 名）
   - `curl http://mac-mini:9000/...` → `Could not resolve host: mac-mini`
   - `curl http://mac-mini.taila93443.ts.net:9000/...` 同样失败（系统解析器没用 `100.100.100.100`）
5. **数据面本身通**：`tailscale ping mac-mini` OK；`curl http://100.108.64.126:9000/api/system/status` → UP（~26ms）
6. 公网遗留入口 `https://sonar.cypresso.ai`（dev-cypresso nginx → 已停的旧 Sonar）现为 **502 Bad Gateway**，与本次 CI secret 路径无关，但是噪音/误导源。

对照 2026-06-12 记录：当时在 VM 内启用 Tailscale 后 MagicDNS 曾验证通过（`getent hosts mac-mini` → `100.108.64.126`）。当前 **`CorpDNS=false`**，MagicDNS 已失效，job 一旦调度到 `mas-go-dev-ci-*` 就会在 Scanner 查 version 时秒失败；调度到 lemon/umac 则正常。

### 建议修复（待用户确认后再做）

| 方案 | 动作 | 说明 |
| --- | --- | --- |
| A（推荐） | `sudo tailscale set --accept-dns=true` | 恢复 MagicDNS，与 06-12 设计一致；验证 `getent hosts mac-mini` + `curl http://mac-mini:9000/api/system/status` |
| B（兜底） | `/etc/hosts` 增加 `100.108.64.126 mac-mini mac-mini.taila93443.ts.net` | 不依赖 accept-dns；注意 cloud-init `manage_etc_hosts` 可能覆盖，需改 template 或关管理 |
| C（不推荐） | 把 `SONAR_HOST_URL` 改成 Tailscale IP | 全池 secret 一改全动，且失去主机名语义 |

修复后可用任意 backend PR 重跑 `SonarQube Analysis`，确认 job 落在 `mas-go-dev-ci-*` 时 Scanner 不再报 `Failed to query server version`。

### 验证（排查时）

- mac-mini：`docker ps` sonarqube healthy；本地 API UP
- mas-go-dev：`CorpDNS false`；IP 直连 200；主机名解析失败
- 失败 job runner = `mas-go-dev-ci-2`；同 run 成功 job runner = `lemon-imac-2`

## 2026-07-28 16:51 CST - 紧急磁盘清理：buildx 残骸 + Docker build cache + go-build 修剪

- 服务器：`mas-go-dev`
- 操作人：`Grok`
- 原因：用户报 runner 再次把磁盘搞满；紧急排查与回收可再生占用。
- 排查现状（清理前）：
  - 根盘 `/`：`103G/300G`（**35%**，Avail **198G**）——**当时未满**；今日 Worker 日志无 ENOSPC。
  - `/tmp` tmpfs：`1.2G/3.9G`（**30%**），主要为残留 `go-build*` / `go-link*` / `node-compile-cache`。
  - Docker：Build Cache **22.65GB** 全可回收；3 个已退出 2–6 周的 buildx builder volume 合计 **~16.9G**；Images 另有 ~2.5G 可回收。
  - go-build：`ci-1` **7.9G**、`ci-2` **11G**、部署 slot **0**；无 `Runner.Worker`。
  - 三 Listener / 业务容器（api/worker/portal/redis/azurite 等）均正常。
- 影响：
  - 清理后根盘 **48G used / 253G avail（16%）**；`/tmp` **144M（4%）**。
  - 下次 Docker build 会冷启动重建 buildkit cache（预计多几分钟）。
  - go-build 按 runbook **mtime >2 天**修剪，近期编译缓存保留。
- 备份：无（删除均为可再生 cache / 已退出 builder 状态）。
- 回滚：cache 与 buildx 状态会在下次 CI/deploy 自动重建；无需回滚。
- 变更时序：
  1. 确认无 `Runner.Worker`。
  2. `sudo rm -rf /tmp/go-build* /tmp/go-link* /tmp/node-compile-cache`。
  3. `docker rm -f` 三个 exited buildx builder 容器，并 `docker volume rm` 对应 `*_state` 卷（~17G）。
  4. `sudo docker builder prune -af`（回收 **22.79GB**）。
  5. `sudo docker image prune -f`（回收 dangling **242MB**）。
  6. `find …/cache/go-build -type f -mtime +2 -delete`：`ci-1` 7.9G→**4.7G**，`ci-2` 11G→**4.6G**。
- 验证：
  - `df -h / /tmp`：根盘 16% / Avail 253G；`/tmp` 4%。
  - `docker system df`：Build Cache **0**；Volumes 仅 azurite/redis/uploads（~41MB）。
  - 三 runner service `active`；业务容器仍 Up/healthy。
- 备注：历史 ENOSPC 多在根盘真满（7 月初）或 `/tmp` tmpfs 打满（7-17）；本次根盘尚有空间，但 Docker buildx 残骸 + 22G build cache 已是下次打满的主要隐患，已先清。

## 2026-07-23 19:01 CST - A+B：清空 ci-1/ci-2 go-build（CYP-1547）

- 服务器：`mas-go-dev`
- 操作人：`Grok`
- 原因：`mas-go-dev-ci-1/2` go-build **77G+72G**（mtime 均 ≤2 天）；与 lemon/umac 同类 coverage 膨胀。
- 影响：
  - 确认无 `Runner.Worker` 后清空 `/opt/actions-runner/mas-go-dev-ci-{1,2}/cache/go-build`
  - `mas-go-dev` 部署 slot go-build 本已 0；`df` 根盘 **74% → 25%**（Avail **80G → 228G**）
  - 三 Listener 保持运行
- 备份：无
- 回滚：cache 可再生
- 关联：**CYP-1547**；coverage job-local GOCACHE（backend PR）；runbook **2 天**修剪
- 验证：两 ci go-build 0；Listeners 在跑

## 2026-07-20 20:01 CST - U6 清理陈旧 tool：部署 runner go 1.25.0

- 服务器：`mas-go-dev`
- 操作人：`Grok`
- 原因：U6/R7；`mas-go-dev` 部署 runner `_work/_tool/go` 仅残留 **1.25.0**（与 go.mod 1.25.7 不一致）。
- 做了什么：`rm -rf /opt/actions-runner/mas-go-dev/_work/_tool/go/1.25.0`（~240M）。
- 验证：ci-1/ci-2 仅 `1.25.7`；部署 runner go tool 目录空，下次 setup-go 会拉 1.25.7。
- 影响：下次走 `mas-go-dev` label 的 job 可能多一次 Go 工具下载（一次性）。

## 2026-07-20 19:48 CST - CI 缓存基线：清 128G go-build + per-slot GOCACHE

- 服务器：`mas-go-dev`
- 操作人：`Grok`（ce-work U1）
- 原因：共享 `~/.cache/go-build` 膨胀至 ~128GB；ci-1/ci-2 同 HOME 无隔离，存在 CYP-322 同类竞态。
- 影响：
  - 删除 `/home/actions-runner/.cache/go-build`（重建空目录）；磁盘 199G used → **71G used / 230G avail**。
  - `mas-go-dev-ci-1/2` 与 `mas-go-dev` 的 `.env` 注入 per-slot `GOCACHE` + 共享 `GOMODCACHE=/home/actions-runner/go/pkg/mod`。
  - 重启三 runner service；日志显示当时 **SonarQube Scan** 与 **Deploy to mas-go-dev** job 被 cancel（重启窗口）。
- 备份：`/opt/actions-runner/*/.env.bak.20260720-113130`
- 回滚：还原 `.env.bak.*` 后 `sudo ./svc.sh stop && start`。
- 验证：三 Listener 在线；`.env` 含不同 GOCACHE。
- 参考：`docs/plans/2026-07-20-001-ops-ci-runner-cache-baseline-plan.md`

## 2026-07-20 13:45 CST - CI 池：部署 runner 与质量 runner 分离

- 服务器：`mas-go-dev`
- 操作人：`Grok`
- 原因：统一调度；避免 Deploy to mas-go-dev 与 PR 质量活抢同一角色。
- 影响：
  - `mas-go-dev`（id 26）：仅 `mas-go-dev` 部署标签，**无** quality/tests。
  - `mas-go-dev-ci-1/2`（id 28/29）：新增 `frontend-quality-ci`；id 29 补 `backend-ci`。
  - 前端 Typecheck / 汇总 / PR Sonar / Lint 改为 `frontend-quality-ci`，可落到 ci runner，**不再**用部署 runner 的 `mas-go-dev` label。
- 回滚：删 label；workflow 改回旧 `runs-on`。
- 验证：见 `docs/runbooks/ci-runner-pools.md` 快照表。



## 2026-07-18 09:30 CST - 只读排查 Deploy to mas-go-dev migrate applock 失败

- 服务器：`mas-go-dev`（`192.168.2.22` / TS `100.109.223.53`）+ 关联 `mssql-ref`
- 操作人：`Grok`
- 原因：用户要求排查
  [Actions run 29587500204 / job 87909063494](https://github.com/cypressoai/iCare-backend/actions/runs/29587500204/job/87909063494)
  （`Deploy to mas-go-dev` 失败）。
- 影响：**只读**，未重启容器 / runner / SQL Server，未改配置、未 force 迁移。
- 结论：
  - 失败点：`deploy_seed.sh` → `migrate up`，错误为 SQL Server `sp_releaseapplock`（Resource `3979484786`，Session 锁未持有）。
  - **根因**：同一次 run 内 `Deploy to Server` 与 `Deploy to mas-go-dev` 几乎同时对 **同一库**
    `medicalassistance_preprod` 跑 golang-migrate。
    - mas-go-dev：`192.168.2.20`
    - Server：`100.124.140.78`（`mssql-ref` Tailscale，与 LAN 同机）
  - 时间重叠（UTC）：Server migrate `14:27:40.679` 起；mas-go-dev migrate `14:27:42.850` 起，`14:27:42.875` 失败；Server `14:27:44.320` `no change` 后 seed 成功。
  - 库现状：`schema_migrations` → `version=26`，`dirty=0`；失败镜像上手工 `migrate up` → `no change`。
  - 当前容器仍为上一成功 deploy 镜像 `icare/backend:mas-go-dev-1a82aa14…`（CYP-1334 run），healthz 正常；**未**滚到失败 commit `099d4908…` 的本地 tag。
- 备份 / 回滚：无变更。
- 建议（需改应用仓 workflow，未在本仓库执行）：
  - 对共享 preprod 的 migrate 加 concurrency / 串行化两个 deploy job；或拆库；或 migrate 退避重试。
  - 短期可在无其它 seed 时重跑 `Deploy to mas-go-dev`。
- 方案沉淀：`docs/solutions/mas-go-dev/workflow-issues/concurrent-migrate-applock-with-server-deploy-2026-07-18.md`

## 2026-07-17 10:30 CST - job 通过后复查 /tmp 并清空残留

- 服务器：`mas-go-dev`（`192.168.2.22` / TS `100.109.223.53`）
- 操作人：`Grok`
- 原因：用户确认失败 job 已重跑通过，要求再查 `/tmp` 并清空。
- 影响：仅删 `/tmp` 下可再生成残留（`useradmin-sig*`、`goimports`、`hsperfdata_*` 等）；未动 runner socket / systemd-private。
- 现状与验证：
  - 复查时 `/tmp` 已仅 **528K（1%）**，无 buildx/go-build 大目录（上轮清理 + 新 deploy 未再往 `/tmp` 写 cache）。
  - 清空后：`df -h /tmp` → **0 / 3.9G（0%）**。
  - 新 Buildx cache 已在磁盘：`/var/cache/buildx/icare-backend-mas-go-dev` **1.4G**（说明新 `deploy.yml` 路径生效）。
- 回滚：无。

## 2026-07-17 10:10 CST - 清理 /tmp 缓存并预建磁盘 Buildx cache 目录

- 服务器：`mas-go-dev`（`192.168.2.22` / TS `100.109.223.53`）
- 操作人：`Grok`
- 原因：接上条排查；用户确认直接清理以恢复 runner。
- 影响：
  - 删除 `/tmp` 上 Buildx 双份 cache、`go-build*`/`go-link*`、`node-compile-cache`、残留 `cgo-gcc-input-*.c`。
  - **未**重启 runner / 容器 / 服务。
  - 预建 `/var/cache/buildx`（属主 `actions-runner:actions-runner`，775），供后续 workflow 把 Buildx local cache 迁出 tmpfs。
  - 同步在 `dev-cypresso` 预建 `/var/cache/buildx`（属主 `ec2-user`，该机 runner 以 ec2-user 运行）。
  - 应用仓 `iCare/backend/.github/workflows/deploy.yml` 本地已改路径（`/tmp/.buildx-cache-*` → `/var/cache/buildx/icare-backend*`），由用户自行开 PR 合入后生效。
- 备份：无（删除的是可再生缓存）。
- 回滚：无必要；cache 会在下次 deploy 重建。
- 变更时序：
  1. `sudo rm -rf /tmp/go-build* /tmp/go-link* /tmp/.buildx-cache-mas-go-dev /tmp/.buildx-cache-mas-go-dev-new /tmp/.buildx-cache-backend* /tmp/node-compile-cache /tmp/cgo-gcc-input-*.c`
  2. `sudo mkdir -p /var/cache/buildx && chown actions-runner:actions-runner`
- 验证：
  - `df -h /tmp`：528K / 3.9G（**1%**，清理前 100%）。
  - `free -h`：swap 已用从约 **4.3G → 451M**（tmpfs 释放后内存压力明显下降）。
  - 根盘仍约 85G 可用。

## 2026-07-17 10:05 CST - 排查 runner 报磁盘满：根因是 /tmp(tmpfs) 100% 满

- 服务器：`mas-go-dev`（`192.168.2.22` / TS `100.109.223.53`）
- 操作人：`Grok`
- 原因：self-hosted runner 报磁盘满；只读排查当前磁盘与 CI 占用。
- 影响：本次**仅排查、未做清理或改配置**。
- 现状（只读）：
  - 根盘 `/`（`/dev/sda1` xfs 300G）：已用 216G / 可用 85G（**72%**，**未满**）。
  - **`/tmp` 为 tmpfs，仅 3.9G，已用 3.9G / 可用 0（100% 满）**——真正触发 “No space left on device” 的挂载点。
  - `/tmp` 主要占用（属主均为 `actions-runner`）：
    - `/tmp/.buildx-cache-mas-go-dev` **1.4G**
    - `/tmp/.buildx-cache-mas-go-dev-new` **1.4G**（与上一份并存，说明 rotate 未完成或并发写）
    - 多个 `/tmp/go-build*` + `go-link*` 合计约 **1.2G**
    - 合计把 3.9G tmpfs 顶满
  - 根因链路：`deploy.yml` 把 Docker Buildx local cache 写在 `/tmp/.buildx-cache-mas-go-dev{,-new}`（`cache-from`/`cache-to type=local` + rotate）；Go 编译默认也把 `GOCACHE`/临时文件落在 `/tmp`。三台 runner 服务共享同一 `/tmp`，且 tmpfs 占物理内存。
  - Runner 服务状态：`mas-go-dev` / `mas-go-dev-ci-1` / `mas-go-dev-ci-2` 均为 `active running`；近期 job 中 **Lint / SonarQube Scan Failed**（如 2026-07-17 01:59–02:00 UTC 一带）。
  - 内存侧：物理内存 7.7G，swap 已用约 4.3G；tmpfs 满时会进一步挤压可用内存。
  - Docker 侧（根盘，非本次直接原因）：build cache ~14.5G；三个已退出的 buildx builder volume 各约 5–6G；可后续再清理。
- 验证：
  - `df -h / /tmp`：根盘 72% 可用 85G；`/tmp` 100% 可用 0。
  - `sudo du -sh /tmp/.buildx-cache* /tmp/go-build*` 与 workflow 中 cache 路径一致。
- 回滚：无（只读）。
- 备注 / 建议修复（**待用户确认后再做**）：
  1. 紧急：清理 `/tmp` 中 buildx 双份 cache 的旧份、陈旧 `go-build*`/`go-link*`（可立刻腾出约 2–3G，恢复 CI 写临时文件）。
  2. 中期：把 Buildx local cache 从 `/tmp` 迁到根盘路径（如 `/var/cache/buildx/...` 或 `/opt/mas-go-dev/buildx-cache/`），避免 RAM 型 tmpfs 上限。
  3. 可选：为 runner 设 `TMPDIR`/`GOCACHE` 到磁盘目录；`docker builder prune` / 删除退出的 buildx volume 回收根盘空间。

## 2026-07-14 18:05 CST - portal 容器 nginx client_max_body_size 100M

- 服务器：`mas-go-dev`（`192.168.2.22` / TS `100.109.223.53`）
- 操作人：`Grok`
- 原因：本机无宿主机 nginx；`mas-icare-portal` 容器内 nginx 反代 `/api/`，默认 `client_max_body_size 1m`，大文件上传会被 413。与 `dev-cypresso` 对齐提高到 `100M`。
- 影响：
  - 容器 `mas-icare-portal`：`/etc/nginx/nginx.conf`（http 块）与 `/etc/nginx/conf.d/default.conf`（server 块）均写入 `client_max_body_size 100M;`。
  - 仅容器内 `nginx -s reload`，未 recreate 容器、未改 compose / 镜像。
  - 未装宿主机 nginx（`nginx` 命令不存在）。
- 备份：
  - 容器内 `/etc/nginx/nginx.conf.bak.20260714`
  - 容器内 `/etc/nginx/conf.d/default.conf.bak.20260714`
  - 备份随容器生命周期；镜像重建后整份配置被覆盖。
- 变更时序：
  1. 容器内备份两份 conf。
  2. `default.conf` 在 `server_name` 后插入 `client_max_body_size 100M;`；`nginx.conf` 在 `keepalive_timeout` 后插入同指令。
  3. `nginx -t` 通过后 `nginx -s reload`。
- 验证：
  - `docker exec mas-icare-portal nginx -T | grep client_max_body_size` → `100M`（http + server 各一处）。
  - `curl http://127.0.0.1:5174/healthz` → `200 ok`。
- 回滚：
  ```bash
  ssh mas-go-dev 'docker exec -u root mas-icare-portal sh -c "cp /etc/nginx/nginx.conf.bak.20260714 /etc/nginx/nginx.conf; cp /etc/nginx/conf.d/default.conf.bak.20260714 /etc/nginx/conf.d/default.conf; nginx -t && nginx -s reload"'
  ```
- 备注：
  - **非持久**：下次 runner 滚动 `mas-icare-portal` 会回到镜像默认 1m。永久方案需改 frontend-mas 镜像内 nginx 模板（或部署时挂载 conf）。
  - 镜像当时为 `icare/mas-portal:mas-go-dev-68f9b69aa4761cb6a1b634cb2430d38404fd0565`。

## 2026-07-14 11:42 CST - CYP-1302：SIT 后端 api/worker 设 TZ=Asia/Manila

- 服务器：`mas-go-dev`（`192.168.2.22` / TS `100.109.223.53`）
- 操作人：`Grok`（对应 Jira `CYP-1302` 第 2 项，SIT 环境）
- 原因：与 `dev-cypresso` / `mssql-ref` 对齐，SIT 后端 `time.Now()` 使用 PHT 墙钟。
- 影响：
  - `/opt/mas-go-dev/backend/.env.docker` 追加 `TZ=Asia/Manila`（属主仍为 `actions-runner`，600）。
  - 仅 `force-recreate` `icare-backend-api-1` + `icare-backend-worker-1`；未动 seed / gotenberg / infra（azurite/redis）/ portal / runner。
  - 镜像未变：`icare/backend:mas-go-dev-cadac74a9171f69298f23eb0fb61d85823d7eae0`。
  - API 短暂不可用约 30s。
- 备份：
  - `/opt/mas-go-dev/backend/.env.docker.bak.20260714-tz-manila`。
- 变更时序：
  1. 以 `actions-runner` 备份并追加 `TZ=Asia/Manila`（`diff` 仅此新增）。
  2. `BACKEND_IMAGE=<当前 api 镜像> docker compose -f backend.compose.yaml up -d --no-deps --no-build --force-recreate api worker`。
- 验证：
  - api / worker：`TZ=Asia/Manila`，本地 `date` 为 PST（+0800），`date -u` 为 UTC。
  - `icare-backend-api-1` healthy；worker running。
  - 同批已在本机用 `sqlcmd` 验证 `mssql-ref` 的 `GETDATE()` 为 PHT 墙钟（见 `docs/operations/mssql-ref.md` 同日条目）。
- 回滚：
  ```bash
  ssh mas-go-dev 'sudo -u actions-runner bash -c "cp /opt/mas-go-dev/backend/.env.docker.bak.20260714-tz-manila /opt/mas-go-dev/backend/.env.docker && chmod 600 /opt/mas-go-dev/backend/.env.docker && cd /opt/mas-go-dev/backend && BACKEND_IMAGE=icare/backend:mas-go-dev-cadac74a9171f69298f23eb0fb61d85823d7eae0 docker compose -f backend.compose.yaml up -d --no-deps --no-build --force-recreate api worker"'
  ```
- 备注：`.env.docker` 为 VM 本地维护，runner 同步 compose 时一般不覆盖此文件；若 CI 或人工用 example 重写 env，需保留 `TZ=Asia/Manila`。代码口径改动仍在应用仓。

## 2026-07-05 14:35 CST - 为 Azurite 配置 CORS（浏览器预览 blob）并固化脚本

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`）
- 操作人：`Claude`
- 原因：用户在浏览器预览 azurite 上的 blob 文件失败，报 CORS 错误。需要给 azurite blob 服务开启 CORS，允许浏览器跨源直连预览/上传。
- 关键结论（避坑）：
  - **Azurite 没有 `--cors` 命令行选项**。原始方案建议在 `azurite-blob` 启动命令后加 `--cors "*"`，实测导致容器崩溃循环（日志 `The option "cors" is unknown`），且 `--cors` 也不是顶层命令参数。已 context7 查官方文档确认：CORS **只能**通过 `Set Blob Service Properties` REST API 在运行时写入服务属性。
  - CORS 规则持久化在 `azurite-data` volume 里，`up -d --force-recreate` 重建容器不丢；但 `docker compose down -v` 或删 volume 会丢，需重跑设置脚本。
- 影响：
  - azurite blob 服务新增一条 CORS 规则：`AllowedOrigins=*`、全 HTTP 方法、全 headers、`MaxAgeInSeconds=3600`。
  - 期间因错误方案 azurite 容器崩溃循环约 1 分钟，已回滚恢复；api/worker 经 `azurite:10000` 的连接短暂中断后自动重连，无数据丢失。
  - 新增运维脚本 `/opt/mas-go-dev/infra/set-cors.sh`（属主 `actions-runner`，可执行）。
- 变更时序：
  1. 备份 `infra.compose.yaml` → `infra.compose.yaml.bak.20260705`。
  2. （错误尝试）在 command 加 `--cors "*"` 并 recreate → azurite 崩溃循环 → **立即回滚**备份文件并 recreate，服务恢复。
  3. 用一次性 `python:3.12-slim` 容器 + `azure-storage-blob` SDK（经 `shared-services` 网络 DNS 名 `azurite` 访问，SDK 自动 SharedKey 签名）调用 `set_service_properties(cors=...)` 写入 CORS 规则。
  4. 把该步骤固化为 `/opt/mas-go-dev/infra/set-cors.sh`（幂等，内部同样借一次性 python 容器；裸 curl 因缺 SharedKey 签名返回 403，故不用 curl 直发）。
- 验证：
  - OPTIONS 预检（`Origin: http://example.com`）返回 `HTTP/1.1 200 OK` + `Access-Control-Allow-Origin: http://example.com` + `Access-Control-Allow-Methods: GET`。
  - `set-cors.sh` 独立执行输出「已写入 1 条 CORS 规则」+ 预检头校验通过。
  - `infra.compose.yaml` 已还原为改动前内容（command 无 `--cors`），azurite `Up` 正常。
  - 用户浏览器强刷后确认 blob 文件可正常预览，CORS 报错消失（端到端验证通过）。
- 回滚说明：
  - compose 文件已在步骤 2 回滚，与改动前一致，无残留。
  - 如需移除 CORS：用 SDK/脚本调用 `set_service_properties(cors=[])` 置空即可（运行时属性，不涉及 compose）。
  - 若 volume 被删导致规则丢失：重跑 `sudo -u actions-runner bash /opt/mas-go-dev/infra/set-cors.sh`。

## 2026-07-05 00:16 CST - 在线扩展根分区与 XFS 到 300G

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`）
- 操作人：`Codex`
- 原因：PVE 侧已按确认方案将 VM `130` 的 `scsi0` 从 120G 扩到 300G；需要在 guest 内扩展根分区与 XFS 文件系统，让新增容量可用。
- 影响：
  - `/dev/sda1` 从 `120G` 在线扩展到 `300G`。
  - 根文件系统 `/` 从 `120G` 扩到 `300G`，可用空间约 `189G`，使用率从扩容前约 `93%` 降到 `38%`。
  - 未重启 VM，未重启 runner，未重启 Docker 或业务容器。
- 变更：
  1. 扩容前 guest 已识别整盘 `/dev/sda` 为 `300G`，但 `/dev/sda1` 仍为 `120G`。
  2. 执行 SCSI rescan 与 `partprobe`；`fdisk` 显示 GPT backup table 不在磁盘末尾，这是磁盘刚扩容后的预期状态。
  3. 执行 `sudo growpart /dev/sda 1`，`/dev/sda1` 从 `251633631` sectors 扩到 `629120991` sectors。
  4. 执行 `sudo xfs_growfs /`，XFS data blocks 从 `31454203` 扩到 `78640123`。
- 验证：
  - `lsblk`：`sda` `300G`，`sda1` `300G`，`sda127` `1M`，`sda128` `10M`。
  - `df -hT /`：`/dev/sda1` `xfs`，`300G`，已用约 `112G`，可用约 `189G`，使用率 `38%`。
  - 再次 `fdisk -l /dev/sda` 不再出现 GPT PMBR / backup GPT mismatch 警告。
  - 3 个 runner service 均为 `active`：`mas-go-dev`、`mas-go-dev-ci-1`、`mas-go-dev-ci-2`。
  - `docker system df`：Build Cache 又有约 `953.8MB` 可回收，属 CI 后续重新生成缓存，当前空间充足无需处理。
- 回滚说明：XFS 与分区已在线扩展，不能直接无损缩回；如后续需要调整容量，应另行规划迁移或重建磁盘。

## 2026-07-05 00:08 CST - 只读确认 Go testcache 可复用，清 testcache 不适合做磁盘治理

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`）
- 操作人：`Codex`
- 原因：用户进一步确认 iCare backend coverage CI 产生的 Go testcache 下次是否真的用不上；若用不上才考虑每次 CI 结束自动清理测试结果缓存。
- 影响：本次仅读取 VM 上 Go 1.25.7 的帮助文本与源码，不执行测试、不清理缓存、不修改 VM 配置。
- 结论：
  - 当前 coverage 测试结果缓存**不是确定用不上**。Go 1.25.7 文档与源码明确把 `-coverprofile` 列为 cacheable test flag；`-coverpkg` / `-covermode` 影响 test binary / build action ID，若源码、测试输入、环境变量、文件输入和相关 flag 一致，后续运行可以命中 testcache，并恢复测试输出与 coverage profile。
  - 因此不应把“每次 CI 完自动 `go clean -testcache`”作为常规优化；这会牺牲可复用的测试结果缓存。
  - `go clean -testcache` 也不是释放磁盘空间的有效手段：Go 源码 `cmd/go/internal/clean/clean.go` 中它只是写 `testexpire.txt`，让旧测试结果过期，并不会遍历删除大块 cache 文件。真正占 `65G+` 的主要是 Go build cache 编译产物。
- 关键依据：
  - `cmd/go/internal/test/test.go`：package list mode 下 successful package test results 可缓存；cacheable test flags 包含 `-coverprofile`。
  - `cmd/go/internal/test/test.go`：`saveOutput` 会在 `testCoverProfile != ""` 时把 coverage profile 存入 cache key。
  - `cmd/go/internal/clean/clean.go`：`-testcache` “expire all test results”，实现是写 `testexpire.txt`，不是删除整个 build cache。
- 后续判断：
  - 如果目标是保留 CI 速度，正确方向不是每次清 testcache，而是扩容 VM 磁盘，并保留 Go module cache 与大部分 Go build cache。
  - 仍可做阈值兜底：当根分区接近打满时再执行有损性能的缓存清理，避免 runner 再次假活。

## 2026-07-04 23:56 CST - 回收 Docker build cache 并分析 Go build cache 膨胀原因

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`）
- 操作人：`Codex`
- 原因：上一条排查确认 Docker build cache 约 `8.792G` 可回收，用户确认先回收该部分；同时要求继续分析 `/home/actions-runner/.cache/go-build` 为什么涨到约 `65G`，以及后续如何避免无限膨胀。
- 影响：
  - 执行 `docker builder prune -af`，删除 BuildKit 本地构建缓存，不影响当前运行容器、镜像和 volume。
  - 后续 Docker build 首次重建会变慢；被删构建缓存无法原样回滚，但可由后续 build 自动再生成。
  - 未清理 Go build cache，未重启 runner，未修改 systemd / crontab / workflow。
- 变更：
  - 清理前 `docker system df`：`Build Cache 334` 项，`8.792GB`，全部可回收。
  - `docker builder prune -af` 实际回收 `8.843GB`。
  - 清理后 `docker system df`：`Build Cache 1` 项，`659B`，`0B` 可回收。
- 验证：
  - 根分区从 `120G 100%` 降到 `120G 90%`，可用空间约 `13G`。
  - inode 从 `95%` 降到 `4%` 使用。
  - 清出空间后，`mas-go-dev` 与 `mas-go-dev-ci-1` 重新出现 `Runner.Listener`；3 个 runner service 均为 `active (running)`。当时 `mas-go-dev` / `mas-go-dev-ci-1` 已开始承接 Go CI 任务。
- Go build cache 分析：
  - Go binary 来自 runner toolcache：`/opt/actions-runner/mas-go-dev-ci-1/_work/_tool/go/1.25.7/x64/bin/go`，版本 `go1.25.7`。
  - `GOCACHE=/home/actions-runner/.cache/go-build`，`GOMODCACHE=/home/actions-runner/go/pkg/mod`。
  - Go 源码 `cmd/go/internal/cache/cache.go` 里当前策略是：缓存文件每次使用后最多每小时更新一次 `mtime`，每天最多 trim 一次，只删除至少 `5 days + 1 hour` 未使用的 cache entry。
  - 本机根分区虽然是 `noatime`，但该 Go 版本使用的是 `mtime` 标记最近使用，不是文件系统 `atime`；`noatime` 不是主因。
  - `/home/actions-runner/.cache/go-build` 当时约 `65G`、约 `216k` 个文件。按 `mtime` 聚合：`2026-06-28` 约 `1.95G`、`06-29` 约 `14.24G`、`06-30` 约 `8.78G`、`07-01` 约 `9.15G`、`07-02` 约 `12.38G`、`07-03` 约 `1.02G`、`07-04` 约 `16.81G`；超过 7 天的只有 2 个小文件。
  - 当前 runner 正在跑 iCare backend 的覆盖率测试：`go test ./test/... ./internal/... -coverprofile=coverage.out -covermode=atomic -coverpkg=./cmd/...,./internal/...`。这种全量覆盖率插桩会生成大量编译产物；多个 runner 共享同一个 `actions-runner` 用户家目录下的 `GOCACHE`，高频 CI 又会持续刷新这些产物的 `mtime`，所以 Go 自带的“5 天未用再删”很难把缓存压下来。
  - iCare backend workflow 里 `actions/setup-go@v5` 已设置 `cache: false`；问题不是 GitHub Actions 远端 cache，而是 self-hosted runner 本机的 Go build cache。
- 后续建议（需用户确认后再执行）：
  1. 立即止血：等当前 Go CI 任务结束后，以 `actions-runner` 身份执行 Go cache 清理，例如用当前 toolcache 里的 Go binary 跑 `go clean -cache -testcache`，或直接清空 `/home/actions-runner/.cache/go-build`。这会让后续 Go 构建变慢，但缓存可再生成。
  2. 防止复发：在 iCare backend 的重型 CI job 里设置 job-local `GOCACHE`，例如 `GOCACHE=${{ runner.temp }}/go-build`，让覆盖率测试产物随 job temp 生命周期回收，代价是减少跨 job 编译缓存复用。
  3. 服务器兜底：增加一个 systemd timer（或经确认后再用 crontab）定期检查 `/home/actions-runner/.cache/go-build` 和根分区占用，超过阈值时跑 `go clean -cache -testcache`，并可顺手跑 `docker builder prune -af --filter until=168h`。

## 2026-07-04 23:50 CST - 只读排查 GitHub Actions runner 假活，根因为根盘 100%

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`）
- 操作人：`Codex`
- 原因：用户询问 VM 上的 self-hosted GitHub Actions runner 是否已经死掉。
- 影响：本次仅做只读排查，未重启 runner、未清理文件、未改 Docker / systemd / 应用配置。
- 结论：
  - 3 个 runner systemd service 均显示 `active (running)`，但并不代表健康。
  - `mas-go-dev` 与 `mas-go-dev-ci-1` 只剩 `runsvc.sh` + `RunnerService.js`，没有稳定的 `Runner.Listener`；`mas-go-dev-ci-2` 当时仍有一个 `Runner.Listener`，但日志同样出现过反复退出。
  - 直接根因是根分区 `/dev/sda1` 已满：`120G` 用满、只剩 `16K`，inode 使用率 `95%`。runner 写 `_diag/Runner_*.log` 时持续报 `System.IO.IOException: No space left on device`，导致 listener 退出后反复重拉，属于“systemd 假活 / runner 不可靠”。
- 只读排查结果：
  - `/home` 约 `67G`，其中 `/home/actions-runner/.cache` 约 `65G`，全部集中在 Go build cache：`/home/actions-runner/.cache/go-build`。
  - `/var` 约 `34G`，主要是 `/var/lib/docker`：`volumes` 约 `17G`、`overlay2` 约 `16G`、Docker build cache 约 `8.792G` 可回收。
  - `/opt/actions-runner` 约 `8.0G`，其中 3 个 runner 的 `_diag` 合计约 `523M`，不是主因。
  - `/var/log` 约 `319M`，journal 约 `287.8M`，容器 json 日志约 `7M`，不是主因。
- 回滚方式：本次无服务器变更，无需回滚。
- 后续建议（需用户确认后再执行）：
  1. 优先清理 `/home/actions-runner/.cache/go-build`，这是最大且最像可再生缓存的占用。
  2. 视情况执行 Docker build cache 清理（`docker builder prune` / `docker buildx prune`），预计可回收约 `8.8G`。
  3. 清出空间后重查 3 个 runner 是否都恢复 `Runner.Listener`；如未恢复，再确认是否重启 runner service。

## 2026-07-02 11:53 CST - 安装 go-sqlcmd v1.10.0（连 MSSQL 参考库排查用）

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`），Amazon Linux 2023，x86_64
- 操作人：`Claude`
- 原因：偶尔需要从 mas-go-dev 直连内网 MSSQL（如 `mssql-ref` `192.168.2.20`）做只读排查，此前机器上没有任何 SQL 客户端。
- 选型：装微软新版 **go-sqlcmd**（`microsoft/go-sqlcmd` 官方 release 单静态二进制），而非 `mssql-tools18`。理由：单文件、零依赖，不引入 unixODBC/msodbcsql18 仓库、不污染系统，对"偶尔排查用"最省事。代价是**不带 `bcp`**——若日后要批量导入导出再补装 `mssql-tools18`。
- 影响：
  - 新增 `/usr/local/bin/sqlcmd`（v1.10.0，0755，root 属主），无其它系统改动，未加 yum 仓库、未装依赖包。
  - 纯客户端工具安装，不影响任何容器 / runner / 生产服务。
- 备份 / 回滚方式：无需备份（新增文件而非改配置）。回滚即 `sudo rm /usr/local/bin/sqlcmd`。
- 变更（按时序）：
  1. 确认系统 AL2023 / x86_64，机器上无 sqlcmd/bcp、无 mssql 仓库。
  2. 从 GitHub API 取最新 tag `v1.10.0`，下载 `sqlcmd-linux-amd64.tar.bz2` 到 `/tmp` 并解压（得单个 `sqlcmd` 二进制 + `sqlcmd_debug`）。
  3. `sudo install -m 0755 /tmp/.../sqlcmd /usr/local/bin/sqlcmd`。
  4. 清理 `/tmp` 下载与解压临时文件。
- 验证：
  - `sqlcmd --version` → `v1.10.0` ✅。
  - 到 `mssql-ref`（`192.168.2.20:1433`）TCP 端口可达。
  - 用错误密码探测：sqlcmd 完成 TLS+TDS 握手，服务端返回明确的 `Login failed for user 'mas_ref_owner'`——证明工具、加密（`-C` 信任自签证书）、网络链路全通，换正确密码即可查询。
- 用法提示：go-sqlcmd 默认强制加密，连自签证书的 MSSQL **必须带 `-C`**（信任服务器证书），否则证书报错：
  ```bash
  sqlcmd -S 192.168.2.20 -U mas_ref_owner -P '<密码>' -C -d <库名> -Q "SELECT TOP 10 * FROM ..."
  ```

## 2026-07-02 02:45 CST - Redis 端口映射增绑 tailscale IP 并关闭 protected-mode，本机免隧道直连

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`）
- 操作人：`Claude`
- 原因：延续同日 Azurite 的做法（见下条），想在本机（tailnet 内）直连 mas-go-dev 的 Redis 做集成测试排查（查看 asynq 队列、worker 注册、失败统计等），免去每次开 SSH 隧道。原先 `redis` 容器端口只映射到 `127.0.0.1:6379`，VM 外部无法直连。
- 安全权衡（**经用户确认**）：此 Redis **无密码**（`requirepass` 为空）。用户判断 tailnet 内只有少数开发同事、可信，接受不加密码。**因此这是有意为之的暴露**：tailnet 内任何成员无需认证即可读写/清空（`FLUSHALL`）该 Redis 及其中的 asynq 队列数据。风险边界：仅限 tailnet（未绑 `0.0.0.0`），公网与 PVE 内网 `192.168.2.x` 均连不到；且是开发测试环境、非生产。若日后 tailnet 成员范围扩大或数据敏感度提高，应补 `requirepass`。
- 关键点 —— 必须关 protected-mode：Redis 7 在「绑定非回环地址 + 无密码」时，protected-mode 默认会**拒绝**非本地连接。故仅改端口映射不够，须在 `command` 显式加 `--protected-mode no`，否则 tailnet 直连会被拒。这是与 Azurite 那次的差异（Azurite 无此机制）。
- 影响：
  - `/opt/mas-go-dev/infra/infra.compose.yaml` 的 `redis` 服务：
    - `command` 由 `["redis-server","--appendonly","yes"]` 改为追加 `"--protected-mode","no"`。
    - `ports` 段在原 `127.0.0.1:6379:6379` 基础上**新增** `100.109.223.53:6379:6379`（保留回环）。
  - 以 `actions-runner` 身份 `docker compose up -d` 重建 **redis 一个容器**；`azurite` 保持 Running 未动。
  - 数据卷 `redis-data` 保留（AOF 持久化），队列数据未丢。
  - 不碰 api / worker（它们经 Docker DNS 名 `redis:6379` 走 `shared-services` 内网访问），不触发 runner / 部署流程。
- 备份：
  - `/opt/mas-go-dev/infra/infra.compose.yaml.bak.20260702-redis`（以 `actions-runner` 身份 `cp -a`，含上一条 azurite 改动，2384 字节）。
- 回滚方式：
  ```bash
  ssh mas-go-dev
  sudo cp /opt/mas-go-dev/infra/infra.compose.yaml.bak.20260702-redis /opt/mas-go-dev/infra/infra.compose.yaml
  sudo -u actions-runner docker compose -f /opt/mas-go-dev/infra/infra.compose.yaml up -d
  ```
- 变更（按时序）：
  1. `sudo cp -a infra.compose.yaml infra.compose.yaml.bak.20260702-redis`。
  2. 用 Python 精确替换整个 `redis` 服务段（按内容匹配，非按行号）：`command` 追加 `--protected-mode no`，`ports` 增绑 tailscale IP，各加一行注释。
  3. `sudo diff` → 仅 command 1 行改写 + ports 新增 1 行 + 注释 2 行。
  4. `sudo -u actions-runner docker compose config --quiet` 校验语法 OK。
  5. `sudo -u actions-runner docker compose up -d` → `redis Recreated/Started`，`azurite Running`（未动）。
- 验证：
  - `docker ps` → redis 端口 `100.109.223.53:6379->6379, 127.0.0.1:6379->6379`。
  - `ss -tlnp` → 宿主同时监听 `100.109.223.53:6379` 与 `127.0.0.1:6379`。
  - **从本机（无 SSH 隧道）** `redis-cli -h 100.109.223.53 -p 6379 PING` → `PONG` ✅；`INFO server` → Redis 7.4.9；`DBSIZE` → 20 keys；`--scan asynq*` 可见 asynq 队列数据（worker 注册、各队列 processed/failed 统计）。全程只读，未改数据。
- 遗留 / 待办：
  - 本机源文件 `~/Code_local/Project/iCare/backend/infra.compose.yaml`（`backend/` 是独立 git 子仓库）已同步 azurite + redis 两处改动，**未提交**；由用户自行开 PR（base 到活跃分支 `develop`）固化。

## 2026-07-02 02:30 CST - Azurite 端口映射增绑 tailscale IP，本机免隧道直连 Blob

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`）
- 操作人：`Claude`
- 原因：想在本机（tailnet 内）直连 `mas-go-dev` 的 Azurite Blob 模拟器做集成测试排查，方便用 Azure Storage Explorer / 脚本读写测试容器。原先 `azurite` 容器端口只映射到 `127.0.0.1:10000`，VM 外部（含本机）无法直连，每次都得先手动开 `ssh -L 10000:127.0.0.1:10000 mas-go-dev` 隧道，容易忘、忘了就连不上。容器内部本已 `--blobHost 0.0.0.0`，限制只在宿主端口绑定那一行，故只需在端口映射上增绑 tailscale IP 即可。
- 影响：
  - `/opt/mas-go-dev/infra/infra.compose.yaml` 的 `azurite` 服务 `ports` 段，在原 `127.0.0.1:10000:10000` 基础上**新增一行** `100.109.223.53:10000:10000`（保留回环绑定不动）。
  - 以 `actions-runner` 身份 `docker compose -f infra.compose.yaml up -d` 重建 **azurite 一个容器**；`redis` 保持 Running 未动。
  - 数据卷 `azurite-data` 保留，测试容器/blob 数据未丢。
  - **未绑 `0.0.0.0`**：只在 tailnet（`100.109.223.53`）+ 回环监听，PVE 内网 `192.168.2.x` 与公网均连不到。
  - 不碰 api / worker（它们经 Docker DNS 名 `azurite:10000` 走 `shared-services` 内网访问，与宿主端口映射无关），不触发 runner / 部署流程。
- 安全说明：Azurite 用的是**公开固定测试密钥**（`devstoreaccount1` / `Eby8vdM0...`，微软官方文档公开），tailnet 内任何成员即可读写 `mas`/`temp` 等**集成测试实际数据**，写删需谨慎。仅因限定在 tailnet 内网、且是开发测试环境，风险可接受。
- 备份：
  - `/opt/mas-go-dev/infra/infra.compose.yaml.bak.20260702`（以 `actions-runner` 身份 `cp -a` 保留权限/归属，与原文件同为 2313 字节）。
- 回滚方式：
  ```bash
  ssh mas-go-dev
  sudo cp /opt/mas-go-dev/infra/infra.compose.yaml.bak.20260702 /opt/mas-go-dev/infra/infra.compose.yaml
  sudo -u actions-runner docker compose -f /opt/mas-go-dev/infra/infra.compose.yaml up -d
  ```
- 变更（按时序）：
  1. `sudo cp -a infra.compose.yaml infra.compose.yaml.bak.20260702`。
  2. 用 Python 精确替换 `azurite` 的 `ports` 段（按整段内容匹配，非按行号），新增 `- "100.109.223.53:10000:10000"` 并更新上方注释。
  3. `sudo diff` 备份与新文件 → 仅注释 1 行改写 + 新增端口 1 行。
  4. `sudo -u actions-runner docker compose -f infra.compose.yaml config --quiet` 校验语法 OK。
  5. `sudo -u actions-runner docker compose -f infra.compose.yaml up -d` → `azurite Recreated/Started`，`redis Running`（未动）。
- 验证：
  - `docker ps` → azurite 端口为 `100.109.223.53:10000->10000, 127.0.0.1:10000->10000`。
  - `ss -tlnp` → 宿主同时监听 `100.109.223.53:10000` 与 `127.0.0.1:10000`。
  - **从本机（无任何 SSH 隧道）** 用共享密钥签名请求 `http://100.109.223.53:10000/devstoreaccount1?comp=list` → HTTP 200，列出全部 10 个容器（`group-account-contract-ledger`、`mas`、`temp`、`test-404`、`test-copy-move`、`test-ctype`、`test-presign`、`test-roundtrip`、`test-slash`、`test-traversal`）✅。
  - 本机连接串（tailnet 内直接可用）：`DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM0...;BlobEndpoint=http://100.109.223.53:10000/devstoreaccount1;`。
- 遗留 / 待办：
  - 本次只改了 **VM 上**的 `infra.compose.yaml`。源文件受 git 管理，在 **`iCare/backend/` 这个独立子仓库**里（`~/Code_local/Project/iCare/backend/infra.compose.yaml`；注意它不属于外层 `iCare` 仓库——外层 `.gitignore` 忽略了 `backend/`，故在外层仓库看不到）。已在该子仓库同步改动、未提交，由用户自行开 PR（base 到 `develop`）固化。

## 2026-07-01 13:07 CST - 修复 worker 漏配 reports 队列（潜伏问题，尚未堆积）

- 服务器：`mas-go-dev`（`192.168.2.22`）
- 操作人：`Claude`
- 原因：同日在 `dev-cypresso` 定位到 worker `.env` 里 `WORKER_QUEUES=default:1` 覆盖了代码默认值、导致 Report Center 报表任务卡死（见 `docs/operations/dev-cypresso.md` 2026-07-01 12:25），排查 `mas-go-dev` 是否同病。结果 `mas-go-dev` **同样中招**：worker 只监听 `default`、不监听 `reports`。代码默认队列是 `internal/config/config.go:210` `{"default":1,"reports":1}`，只要不设 `WORKER_QUEUES` 就该监听两个。区别是 `mas-go-dev` 当前 `reports`/`default` 队列都是 0 堆积——不是没问题，而是**还没人在这台上触发过 Report Center 报表任务**，属潜伏雷；一旦有人用报表功能，任务会入 `reports` 队列但无人消费、永久卡 pending。趁修 dev-cypresso 一并根除。
  - 附带确认：`mas-go-dev` 的 Azurite **不缺 container**——`mas`（及历史 `group-account-contract-ledger`、若干 `test-*`）均已存在、已有 25 个 blob，上传存文件链路正常，无 dev-cypresso 那个 500 问题。故本次只需修 worker 队列一项。
- 影响：
  - `/opt/mas-go-dev/backend/.env.docker` 删除 `WORKER_QUEUES=default:1` 一行（文件归 `actions-runner`、保持 `600` 权限）。
  - 重建 `icare-backend-worker-1` 容器（`.env` 改动须 recreate 才重读 env_file）。
  - 只重建 worker 一个容器；不动 api / seed / gotenberg / azurite / redis / mas-icare-portal，**不碰 self-hosted GitHub Actions runner、不触发部署流程**。
- 备份：
  - `/opt/mas-go-dev/backend/.env.docker.bak.20260701-worker-queues`（以 `actions-runner` 身份 `cp -p` 保留权限/归属）。
- 回滚方式：
  ```bash
  sudo -u actions-runner cp /opt/mas-go-dev/backend/.env.docker.bak.20260701-worker-queues /opt/mas-go-dev/backend/.env.docker
  sudo -u actions-runner env BACKEND_IMAGE=icare/backend:mas-go-dev-eaeecd6055a799cc662344f419836e99b8878644 \
    sh -c 'cd /opt/mas-go-dev/backend && docker compose -f backend.compose.yaml up -d --no-deps --no-build worker'
  ```
- 变更（按时序）：
  1. `sudo -u actions-runner cp -p .env.docker .env.docker.bak.20260701-worker-queues`。
  2. `sudo -u actions-runner sed -i '/^WORKER_QUEUES=default:1$/d' .env.docker`（按整行内容精确删除，非按行号）。
  3. `diff` 备份与新文件 → 仅少 `WORKER_QUEUES=default:1` 一行。
  4. 重建 worker：`sudo -u actions-runner env BACKEND_IMAGE=icare/backend:mas-go-dev-eaeecd6055a799cc662344f419836e99b8878644 sh -c 'cd /opt/mas-go-dev/backend && docker compose -f backend.compose.yaml up -d --no-deps --no-build worker'`。
  - 与 dev-cypresso 的操作差异：配置目录 `/opt/mas-go-dev/backend/`（归 actions-runner，读写都需 `sudo -u actions-runner`）；用 `docker compose` **插件**（v2.24.5，非独立 `docker-compose`）；镜像是本地 tag `icare/backend:mas-go-dev-eaeecd60...`（非 dev-cypresso 的 ghcr tag）。`cd` 必须在 `sudo -u actions-runner sh -c` 上下文里做，否则外层 ec2-user 无权限进目录。
- 验证：
  - worker 新日志：`starting worker ... queues="map[default:1 reports:1]" concurrency=1` → `asynq: Starting processing`——已监听 reports ✅。
  - `docker exec icare-backend-worker-1 env | grep WORKER_QUEUES` → 空（已回退代码默认）。
  - 容器 `Up`，健康。
  - 注：`asynq:queues` 集合此刻仍只有 `default`——正常。该集合由**入队方**投递首个任务时才写入，`mas-go-dev` 从未有人投过 `reports` 任务故集合无 `reports`；worker 是否消费取决于其服务器注册（`asynq:servers`），已由启动日志的 `map[default:1 reports:1]` 证实。将来一旦有报表任务入队即会被消费。

## 2026-06-22 19:05 CST - 给 VM 增加 swap 并为 3 个 runner 加 OOM 后自动恢复

- 服务器：`mas-go-dev`（`192.168.2.22`）
- 操作人：`Codex`
- 原因：`actions.runner.cypressoai.mas-go-dev-ci-1.service` 在 `2026-06-22 16:42 CST` 跑 `SonarQube Scan` 时被 OOM killer 杀掉，systemd 停在 `failed (Result: oom-kill)`，导致该 runner 离线。根因是 8G VM 无 swap，且当时同机并发 Docker build / BuildKit / Java / Sonar 等进程，内存峰值无缓冲。为降低后续瞬时内存峰值直接杀 runner 的概率，并避免 runner 被 OOM 后长期停在 failed，给 VM 加 swap 并给 runner service 加失败自动恢复策略。
- 影响：
  - 新增 `/swapfile`，大小 `8G`，权限 `600`，并写入 `/etc/fstab` 持久化开机启用。
  - 为 3 个 runner service 增加 systemd drop-in：`Restart=on-failure`、`RestartSec=180`。覆盖范围：
    - `actions.runner.cypressoai.mas-go-dev.service`
    - `actions.runner.cypressoai.mas-go-dev-ci-1.service`
    - `actions.runner.cypressoai.mas-go-dev-ci-2.service`
  - 执行 `systemctl daemon-reload`，并确保 `mas-go-dev-ci-1` 处于 active。
  - 未重启 VM、Docker、应用容器、数据库、Tailscale 或其它业务服务。
- 备份：
  - `/etc/fstab.bak.20260622-110536`
  - `/root/runner-oom-fix-redo-20260622-110536/runner-units-before.txt`
  - `/root/runner-oom-fix-redo-20260622-110536/runner-status-before.txt`
  - `/root/runner-oom-fix-redo-20260622-110536/free-before.txt`
  - `/root/runner-oom-fix-redo-20260622-110536/swapon-before.txt`
- 回滚方式：
  1. 停用并移除 swap：
     ```bash
     sudo swapoff /swapfile
     sudo cp /etc/fstab.bak.20260622-110536 /etc/fstab
     sudo rm -f /swapfile
     ```
  2. 移除 runner restart drop-in 并重载 systemd：
     ```bash
     sudo rm -f /etc/systemd/system/actions.runner.cypressoai.mas-go-dev.service.d/restart.conf
     sudo rm -f /etc/systemd/system/actions.runner.cypressoai.mas-go-dev-ci-1.service.d/restart.conf
     sudo rm -f /etc/systemd/system/actions.runner.cypressoai.mas-go-dev-ci-2.service.d/restart.conf
     sudo systemctl daemon-reload
     ```
- 验证：
  - `free -h` 显示 `Swap: 8.0Gi`，`swapon --show` 显示 `/swapfile file 8G`。
  - `/etc/fstab` 包含 `/swapfile none swap sw 0 0`。
  - 3 个 runner service 均为 `active (running)`，`systemctl show` 显示 `Restart=on-failure`、`RestartUSec=3min`；`systemctl cat` 显示 drop-in 中的 `Restart=on-failure`、`RestartSec=180`。
  - `mas-go-dev-ci-1` 当前 active。此前恢复后已重新连接 GitHub 并继续承接 `SonarQube Scan`，最近日志中可见多条 scan 完成记录。

## 2026-06-19 10:42 CST - 后端 DB_NAME 切到 medicalassistance_preprod（配合 mssql-ref 库改名）

- 服务器：`mas-go-dev`（`192.168.2.22`）
- 操作人：`Claude`
- 原因：`mssql-ref` 上库 `medicalassistance` 改名为 `medicalassistance_preprod`（详见 `docs/operations/mssql-ref.md` 2026-06-19）。后端 `.env.docker` 的 `DB_NAME=medicalassistance` 需同步改名，否则连不上库。
- 影响：
  - 修改 `/opt/mas-go-dev/backend/.env.docker`：`DB_NAME` 由 `medicalassistance` 改为 `medicalassistance_preprod`（仅这一行）。`WEBKIT_DB_NAME=maswebkit` 未动；host/账号/密码不变。
  - 强制重建 `icare-backend-api-1` + `icare-backend-worker-1`（含一次性 `seed` 依赖），使新 env 生效。未碰 gotenberg / runner。
  - 改名过程中库一度不可用，停容器期间 API 短暂不可用（开发测试环境，影响可接受）。
- 回滚：用备份 `/opt/mas-go-dev/backend/.env.docker.bak.20260619` 覆盖后同样重建容器。
- 变更：
  1. 以 `actions-runner` 身份 `cp` 备份后 `sed -i 's/^DB_NAME=medicalassistance$/DB_NAME=medicalassistance_preprod/'` 精确改单行。
  2. 先 `stop api worker` 释放对旧库的连接（配合 mssql-ref 改名），改名后重建：
     ```bash
     cd /opt/mas-go-dev/backend
     export BACKEND_IMAGE=icare/backend:mas-go-dev-8346d1a908fe958b6c892e52a31de6dd42649bea
     docker compose -f backend.compose.yaml up --no-build --force-recreate -d api worker
     ```
     注意：`start`（而非 `up --force-recreate`）不会重读改过的 `.env.docker`，必须 recreate；且需带镜像 tag，否则默认 `${BACKEND_IMAGE:-icare/backend:local}` 会去拉不存在的 `:local`（同 6-14 那条经验）。`seed` 在旧库名仍存在时会因连不上失败 exit 1、阻断 api/worker；改名后重跑即通过。
- 验证：
  - api/worker 启动日志 `database connected ... database=medicalassistance_preprod` + `maswebkit`，无 login failed。
  - `icare-backend-api-1` 转 `healthy`，worker 正常。

## 2026-06-14 21:25 CST - 后端 DB 账号切到 mas_ref_owner，修复因 mssql-ref 停用旧账号导致的 500

- 服务器：`mas-go-dev`（`192.168.2.22`）
- 操作人：`Claude`
- 原因：本次在 `mssql-ref` 上把 SQL 账号 `mas_ref_reader` 停用（DISABLE），换成 `mas_ref_owner`。检查发现后端 `icare-backend-api` / `worker` 的 `.env.docker` 用 `mas_ref_reader` 连库（`medicalassistance` 与 `maswebkit` 两套连接，host `192.168.2.20`），账号被禁用后 API 持续报 500：`Login failed for user 'mas_ref_reader'. The account is disabled.`。这就是账号迁移时待确认的「遗留使用方」。
- 影响：
  - 修改 `/opt/mas-go-dev/backend/.env.docker`：`DB_USER` 与 `WEBKIT_DB_USER` 由 `mas_ref_reader` 改为 `mas_ref_owner`（密码不变，两账号同密码，`DB_PASSWORD`/`WEBKIT_DB_PASSWORD` 未动；两个 `*_DSN` 为空，无需改）。
  - 重建 `icare-backend-api-1` + `icare-backend-worker-1` 两个容器使新 env 生效。未动 gotenberg / azurite / redis / seed，未碰 runner。
- 回滚：用备份 `/opt/mas-go-dev/backend/.env.docker.bak.20260614-claude-switch-owner` 覆盖后同样方式重建容器；或在 mssql-ref 上 `ALTER LOGIN [mas_ref_reader] ENABLE` 临时恢复旧账号。
- 变更：
  1. 确认连库配置在 `.env.docker`（compose 经 `env_file: ${DOCKER_ENV_FILE:-.env.docker}` 注入），密码为明文、文件 600、属主 `actions-runner`。
  2. 以 `actions-runner` 身份 `cp` 备份后 `sed` 精确替换两处 `DB_USER`。
  3. 重建容器（需带 runner 部署时的镜像 tag，否则 compose 默认 `${BACKEND_IMAGE:-icare/backend:local}` 会去拉不存在的 `:local`）：
     ```bash
     cd /opt/mas-go-dev/backend
     export BACKEND_IMAGE=icare/backend:mas-go-dev-598f00214c4b1b828d5849b5c93409c5aee83d7a
     docker compose -f backend.compose.yaml up -d --force-recreate --no-build --no-deps --pull never api worker
     ```
- 验证：
  - api/worker 启动日志均 `database connected`（medicalassistance + maswebkit），无 login failed。
  - 近 1 分钟 `login failed` 次数为 0（修复前持续刷）。
  - 之前 500 的 `/api/v1/admin/permissions` 现返回 401（缺 token 的正常响应，DB 连接已通）。
  - `icare-backend-api-1` 转 `healthy`，worker 正常。
- 后续（重要，未完成）：
  - **更正（已核查 iCare backend 仓库）**：先前担心「CI 会覆盖回旧账号」不成立。`deploy.yml` 不生成/覆盖 `.env.docker`，只通过 `DOCKER_ENV_FILE: /opt/mas-go-dev/backend/.env.docker` 引用 VM 上已存在的文件；仓库内只有占位模板（`.env.docker.example` 为 `replace-with-db-user`，`.env.konghai`/`.env.example` 是本地用的 `sa`/`icare`），GitHub secrets 里也没有这个 DB 账号。`mas_ref_reader`/`mas_ref_owner` 的真实值**只存在于 VM 上手工维护的 `.env.docker`**。所以本次修改即持久生效，**仓库侧无需改动**。
  - 唯一残留风险：VM 上几个 `.env.docker.bak.*` 里含旧账号，若有人手工用旧备份覆盖会退回 `mas_ref_reader`（人工风险，非自动化）。
  - 无其它使用方确认前，`mssql-ref` 上的 `mas_ref_reader` 暂保持禁用而非删除。
- 经验复盘（手动重建后端后前端短暂 502，根因不是 nginx 缓存）：
  - 现象：手动 `docker compose up -d --force-recreate api worker` 重建后端后，立刻访问前端 `http://192.168.2.22:5174/login` 出现 502，前端 nginx 日志 `connect() failed (111: Connection refused) ... upstream http://api:8080`。几十秒后自愈。
  - 一开始误判为「api 容器 IP 变了、前端 nginx DNS 缓存还指向旧 IP」。用户质疑：CI 部署同样会重建容器，但他从来无感、不需要等几十秒——若真是 DNS 缓存窗口，日常应偶尔撞到。
  - 实测验证（触发一次 CI 后端部署，与手动重建前的基线对比）：
    - api 容器 ID 与 IP **都变了**（`172.18.0.6` → `172.18.0.5`，且与 worker 互换），证明 CI 部署也是 rm + 重建、IP 一样会变 —— “CI 部署 IP 不变” 的猜想被证伪。
    - 但部署后前端容器内 `getent hosts api` **立即解析到新 IP**，无任何缓存滞后 —— nginx DNS 缓存假说也被证伪。
  - 真正根因：前端 nginx 用 DNS 名 `http://api:8080` 反代（非硬编码 IP，`resolver 127.0.0.11`），解析本身没问题。差别在**有没有等后端 ready**：
    - CI 部署脚本（`deploy.yml`）用 `stop` + `rm -f` + `up -d`，且**带 30 次 `curl healthz` 重试（最多 ~60s），等 api 真正 ready 才算部署完成**；用户都是在部署完成后访问，自然无感。
    - 手动 `--force-recreate` 命令一返回我就让用户访问，api 容器虽 `Started` 但 Go 程序还在初始化（连两个 SQL Server 库的那几秒）、尚未监听 8080 → nginx 连过去 `Connection refused` → 502；初始化完成即自愈。
  - 教训 / 操作建议：手动重建后端容器后，应仿照 CI 先等健康检查通过再交付/通知访问，例如 `for i in {1..30}; do curl -fsS http://127.0.0.1:8080/healthz && break; sleep 2; done`。这与容器 IP、nginx 缓存均无关。

## 2026-06-12 15:57 CST - 在 VM 内启用 Tailscale，恢复访问 mac-mini SonarQube

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：用户安装并登录 Tailscale；`Codex` 做只读验证并记录。
- 原因：`mas-go-dev` 此前依赖 PVE subnet router 与本地静态解析访问 `mac-mini` SonarQube。VM 重启 / 网络重载后，VM 主动访问 tailnet 的路由与 MagicDNS 能力不可用，`http://mac-mini:9000/` 无法解析或连接。用户决定在 VM 内直接安装并登录 Tailscale，减少对 PVE 反向路由和手工 DNS/hosts 方案的依赖。
- 影响：
  - VM 自身成为 tailnet 节点，Tailscale IPv4 为 `100.109.223.53`。
  - `tailscaled` 已启用开机自启并处于运行状态。
  - `mac-mini` MagicDNS 恢复可用，`mac-mini` / `mac-mini.taila93443.ts.net` 均解析到 `100.108.64.126`。
  - 未改 Docker、runner、应用部署目录、PVE subnet router 或防火墙规则。
- 回滚方式：
  - 临时停用：`sudo systemctl disable --now tailscaled`。
  - 如需从 tailnet 退出：`sudo tailscale logout`。
  - 如需完全卸载：按 Amazon Linux 2023 包管理方式移除 `tailscale`，再清理本机不再需要的 tailscale 状态文件。
- 做了什么：
  - 用户已在 `mas-go-dev` 内完成 Tailscale 安装和登录。
  - 只读验证 `command -v tailscale`、`systemctl is-active tailscaled`、`systemctl is-enabled tailscaled`、`tailscale ip -4`、`tailscale status`。
  - 验证 MagicDNS 解析与 SonarQube HTTP 访问。
- 验证结果：
  - `tailscaled`：`active` / `enabled`。
  - `tailscale ip -4`：`100.109.223.53`。
  - `getent hosts mac-mini`：`100.108.64.126 mac-mini.taila93443.ts.net`。
  - `curl -I http://mac-mini:9000/` 返回 `HTTP/1.1 200`。
  - `curl -I http://mac-mini.taila93443.ts.net:9000/` 返回 `HTTP/1.1 200`。
- 注意事项：
  - `tailscale status` 提示 `Some peers are advertising routes but --accept-routes is false`。当前场景只需要访问 tailnet peer（`mac-mini`）和 MagicDNS，不依赖接受其它节点 advertised routes，因此不影响本次修复。
  - 用户已在 Tailscale Admin Console 中给 tailnet 内所有设备设置 `Disable key expiry`，降低 `mas-go-dev`、`pve` 等长期节点因 key 过期导致访问中断的风险。
  - 后续仍需留意 tag / ACL 策略变更，避免 CI VM 对 `mac-mini:9000` 的访问被权限规则误伤。

## 2026-06-12 14:42 CST - 确认 AL2023 无法从官方仓库安装 qemu-guest-agent

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Codex`
- 原因：PVE 侧 VM 配置已有 `agent: enabled=1`，但 guest 内未安装 `qemu-guest-agent`，导致 `qm agent 130 ping` 返回 `QEMU guest agent is not running`。用户确认尝试安装。
- 影响：未安装任何包，未启用任何新服务，未重启 VM，未改 Docker、runner、应用部署目录或业务配置。仅在 `/home/ec2-user/qemu-guest-agent-install-20260612-064212/` 保留安装尝试日志。
- 回滚：无功能性变更需要回滚；如需清理安装尝试日志，可删除 `/home/ec2-user/qemu-guest-agent-install-20260612-064212/`。
- 变更：
  - 安装前状态保存到 `/home/ec2-user/qemu-guest-agent-install-20260612-064212/precheck.txt`。
  - 执行 `sudo dnf install -y qemu-guest-agent`，返回 `No match for argument: qemu-guest-agent` / `Unable to find a match`。
  - 执行 `dnf provides '*/qemu-ga' '*/qemu-guest-agent'`，当前启用的 `amazonlinux` 与 `kernel-livepatch` 仓库无匹配结果。
  - 查阅 AWS 官方 AL2023 KVM 文档，确认 AL2023 当前不打包也不支持 KVM guest agent；因此未从第三方来源安装。
- 验证：
  - `rpm -q qemu-guest-agent` 仍显示 package not installed。
  - PVE 侧 `qm agent 130 ping` 仍返回 `QEMU guest agent is not running`，符合 AL2023 官方限制与当前仓库状态。
  - Docker 与 `actions.runner.cypressoai.mas-go-dev.service` 均为 `active`。
  - `icare-backend-api-1` 仍为 `healthy`，`http://127.0.0.1:5174/healthz` 返回 `ok`。
- 后续：
  - 不建议为 AL2023 引入非官方 QEMU RPM 来追求 PVE guest agent 能力；如确实强依赖该能力，应另行评估迁移到 Ubuntu/Debian 等官方仓库提供 qemu guest agent 的 guest OS。

## 2026-06-11 15:50 CST - 新增 `mas-go-dev-ci-2` 分流 frontend SonarQube job

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Codex`
- 原因：`mac-mini` 上的 frontend PR CI 排队严重。前端 `sonar.yml` 已把 `SonarQube Scan` 单 job 改为共享标签 `frontend-sonar-ci`，`mas-go-dev-ci-1` 已验证能承接该 job；为进一步分流多个 PR 同时触发的 SonarQube job，在同一 VM 上新增第二个 CI runner。
- 影响：
  - 新增一个 GitHub Actions runner service：`actions.runner.cypressoai.mas-go-dev-ci-2.service`，enabled，随 VM 自启。
  - 新 runner 标签为 `self-hosted, Linux, X64, al2023, mas-go-dev-ci, frontend-sonar-ci`。
  - **刻意不加 `backend-ci` / `docker` 标签**：当前只让它承接 frontend SonarQube；不参与 backend Go test / Sonar，也不抢部署 runner `mas-go-dev` 的 job。
  - 可能同时在 `mas-go-dev-ci-1` / `mas-go-dev-ci-2` 上并发跑两个 frontend SonarQube job。该 PR Sonar 不跑 coverage，单 job 通常约 1-2 分钟；当前 VM 4 核、可用内存约 4.1GiB，风险可控。
- 回滚方式：`cd /opt/actions-runner/mas-go-dev-ci-2 && sudo ./svc.sh stop && sudo ./svc.sh uninstall`，然后 `sudo -u actions-runner ./config.sh remove --token <removal-token>`（token 用 `gh api -X POST orgs/cypressoai/actions/runners/remove-token` 获取），最后删除 `/opt/actions-runner/mas-go-dev-ci-2`。
- 做了什么：
  - 预检确认 `mas-go-dev-ci-1` 在线空闲，且不存在 `/opt/actions-runner/mas-go-dev-ci-2`、同名 systemd service 或 GitHub runner 记录。
  - 创建 `/opt/actions-runner/mas-go-dev-ci-2`（owner `actions-runner`），下载并解压 actions/runner `v2.335.1` linux-x64。
  - 以 `actions-runner` 用户执行 `config.sh`，注册到组织 `cypressoai`，runner group `mas-go-dev`，名称 `mas-go-dev-ci-2`，自定义标签 `mas-go-dev-ci,al2023,frontend-sonar-ci`。
  - `sudo ./svc.sh install actions-runner && sudo ./svc.sh start` 安装并启动 systemd 服务。
- 验证结果：
  - `systemctl is-active actions.runner.cypressoai.mas-go-dev-ci-2.service` 返回 `active`，`systemctl is-enabled` 返回 `enabled`。
  - journal 显示 `Connected to GitHub`、runner version `2.335.1`、`Listening for Jobs`。
  - GitHub API 显示 `mas-go-dev-ci-2` `status: online, busy: false`，标签正确；`mas-go-dev-ci-1` 与部署 runner `mas-go-dev` 均保持在线空闲。

## 2026-06-10 19:50 CST - 给 mas-go-dev-ci-1 补装 dirmngr，修复 develop 版 Sonar 签名校验失败

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：PR #581（develop）的 `SonarQube Scan` step 在 mas-go-dev-ci-1 上失败：`gpg: keyserver receive failed: No dirmngr` → `Failed to import SonarSource public key from all keyservers`。根因是 develop 版 sonar.yml 的 `SonarSource/sonarqube-scan-action` **pin 到 SQSCANGHA-135 修复 commit，会校验 Scanner CLI 的 GPG 签名**，需从 keyserver 拉 SonarSource 公钥；而本 VM 装的是 `gnupg2-minimal`，只有 `gpg` 没有 `dirmngr`（gpg 的网络/keyserver 组件），导致拉公钥失败。main 版用 `@v6` 不做此校验，所以之前在本机实测 main workflow（#574/#580）从未暴露此问题。
- 影响：替换一个系统包（minimal→完整 gnupg2），`gpg` 同版本 2.3.7、路径不变，新增 dirmngr/gpg-agent 等完整组件。不影响容器与部署 runner。
- 回滚方式：`sudo dnf install -y --allowerasing gnupg2-minimal`（换回 minimal 包）。
- 做了什么：
  - 预检确认本 VM 到 `keyserver.ubuntu.com:443` / `keys.openpgp.org:443` 出网可达（均 200），方案可行
  - `sudo dnf install -y --allowerasing gnupg2`：AL2023 上 `gnupg2-minimal` 与完整 `gnupg2` 互斥（都提供 `/usr/bin/gpg`），dnf 默认拒绝替换，需 `--allowerasing` 用完整包替掉 minimal 包；无独立 dirmngr 包，这是装 dirmngr 的唯一途径
  - 实测同款命令拉 SonarSource 公钥（`gpg --recv-keys 679F...EC1A`）返回 `imported: 1`、exit 0
- 验证结果：补装 dirmngr 后重跑 PR #581 失败 job（run `27271362622`），`SonarQube Scan` step 成功（落在 mas-go-dev-ci-1，即修复的那台）。
- 经验：mac-mini 之前也踩过同源的 Sonar GPG 坑（`docs/solutions/mac-mini/.../sonarqube-scanner-cli-cache-never-hits-4part-version-2026-06-09.md`，那次是 PATH 缺 gpg + 路径过深）。本次是新 runner 缺 dirmngr。**任何要承接 backend Sonar 扫描的 self-hosted runner，都需具备完整 gpg + dirmngr + 能出网拉 keyserver 公钥**。已另写 `docs/solutions/mas-go-dev/`。

## 2026-06-10 19:35 CST - 把 backend CI 共享池改动同步到 `develop` 分支（修正只合 main 的疏漏）

- 仓库：`iCare-backend`（runner / VM 无变更）
- 操作人：`Claude`
- 原因：前面 PR #574、#580 都只合并到 `main`，但 iCare-backend **日常开发在 `develop`**。GitHub Actions 以「触发 run 的分支上的 workflow 版本」为准，所以 develop 上 backend 的测试/Sonar job 仍是最原始的 `[mac-mini-sonar, macos, arm64]` 独占调度，#574/#580 的改动对 develop **完全没生效**。这是「改 CI 没认准活跃分支」的疏漏。
- 影响：仅 develop 分支 workflow 文件改动，走 PR。runner 标签是 org 级（与分支无关），#580 已加好 `backend-ci`，本次无需再动。
- 关键判断：**没有用 merge main 的方式同步**。`develop` 与 `main` 已分叉（main ahead 4 / behind 335），develop 含 main 没有的内容——`ready_for_review` 触发、Sonar action pin 到 SQSCANGHA-135 修复 commit、gotenberg sidecar 部署步骤。merge main 会搅乱这些。改为基于最新 develop **只 cherry-pick 两处 `runs-on` + GOCACHE 注释**，逐行 diff 核对 develop 独有内容均原样保留。
- 做了什么：提交 PR [iCare-backend#581](https://github.com/cypressoai/iCare-backend/pull/581)（base=`develop`）：`sonar.yml` `SonarQube Scan`、`deploy.yml` `Build and Test` 两个 job `runs-on` 改为 `[self-hosted, backend-ci]`。
- 回滚方式：revert PR #581。
- 教训：**给某仓库改 CI / workflow 前，先确认它的活跃开发分支是哪个**（用 `gh api repos/<repo>/compare/<base>...<head>` 看 ahead/behind 判断主线）。iCare 系列仓库默认分支可能是 `main`，但实际开发在 `develop`，PR base 要对准 develop，否则改动对团队日常 CI 不生效。
- 验证结果：PR #581 首跑 `SonarQube Scan` step **失败**（落在 mas-go-dev-ci-1，测试全过、挂在 Sonar 上报），根因是该 VM 缺 `dirmngr`——详见下方 19:50 记录。补装 dirmngr 后重跑（run `27271362622`）`SonarQube Scan` step 成功。

## 2026-06-10 19:10 CST - backend CI 由硬绑定 mas-go-dev-ci-1 改为 `backend-ci` 共享 runner 池

- 服务器：`mas-go-dev`（PVE VM `130`）+ `mac-mini`（org runner 标签变更）
- 操作人：`Claude`
- 原因：PR #574 把 backend 的 Go 测试 + Sonar 扫描**硬绑定**到 `mas-go-dev-ci-1`（x86 Linux），但用户真实预期是「**优先用 mac-mini（arm64 更快），mac-mini 资源紧张时才溢出到 mas-go-dev-ci-1**」。硬绑定与预期相反——mac-mini 空闲时 backend CI 也永远走更慢的 x86。GitHub Actions 原生不支持优先级/溢出调度（`runs-on` 标签是硬匹配不排序），用「共享 runner 池」做最简近似。
- 影响：org 层面给 5 个 runner 加自定义标签（动态生效、无需重启 runner）；backend 两个 job 的 `runs-on` 改标签（走 PR）。前端 job 与各部署 job 不受影响。
- 回滚方式：
  - 标签：`gh api -X DELETE orgs/cypressoai/actions/runners/<id>/labels/backend-ci`（5 个 runner id：mac-mini-sonar-1..4 = 22/23/24/25，mas-go-dev-ci-1 = 28）
  - workflow：revert PR [iCare-backend#580](https://github.com/cypressoai/iCare-backend/pull/580)
- 做了什么：
  - 通过 org API 给 `mac-mini-sonar-1..4` 与 `mas-go-dev-ci-1` 各加自定义标签 `backend-ci`（5 个 runner 组成共享池）
  - 提交 PR #580：`sonar.yml` 的 `SonarQube Scan`、`deploy.yml` 的 `Build and Test` 两个 job `runs-on` 由 `[self-hosted, mas-go-dev-ci]` 改为 `[self-hosted, backend-ci]`
  - 更正 GOCACHE 注释，覆盖两类机器的缓存隔离方式
- 关键设计点：
  - **没有复用 `mac-mini-sonar` 标签**，而是新建中性标签 `backend-ci`。因为 `mac-mini-sonar` 现在语义 =「mac-mini arm64 macOS slot」，前端 job 用它搭配 `macos`/`arm64`；给 x86 机器贴该标签会让前端 macOS-only job 有误调度到 Linux 的风险。
  - **GOCACHE 并发安全已确认**：mac-mini 4 个并发 slot 在各自 `.env` 注入 per-slot `GOCACHE`/`GOMODCACHE`（`mac-mini-sonar-N/cache/...`），并发跑 backend job 不撞 cache（CYP-322 race 已在 runner 物理层解决）；mas-go-dev-ci-1 单实例走默认路径，已落盘持久化（go-build 2.0G、go-mod 878M）。
  - `mas-go-dev-ci` 标签保留在 mas-go-dev-ci-1 上但已无 job 引用，无害残留。
- 行为说明（诚实记录）：共享池是「谁空闲谁接」，**不是严格「闲时永远优先 arm」**——所有 runner 空闲时 GitHub 挑哪台不保证顺序，偶尔单个 job 落到 x86 慢一点。严格优先级需写显式溢出判断（复杂度高），本方案是性价比最高的近似，完整覆盖核心诉求「mac-mini 忙时溢出」。
- 验证结果：PR #580 触发的 `SonarQube Scan`（run `27270834531`）以标签 `[self-hosted, backend-ci]` 调度成功，1 分 53 秒跑完（热缓存，对比 PR #574 冷缓存 5 分 12 秒）。本次落点恰好是 `mas-go-dev-ci-1`（x86），正好实证「不保证闲时优先 arm」这一行为——功能正确，仅说明严格优先级共享池给不了。后续 merge #580 后 backend 测试/Sonar 即在 5 runner 池中按空闲调度。

## 2026-06-10 18:25 CST - 为 `mas-go-dev-ci-1` 承接 backend Go 测试 + Sonar 扫描做 VM 准备并提交 workflow PR

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：用户决定让 `mas-go-dev-ci-1` 只承接 `iCare-backend` 的 Go 测试与 SonarQube 扫描（即 `sonar.yml` 的 `sonarqube` job 和 `deploy.yml` 的 `test` job，原来都调度到 `mac-mini-sonar` 标签）。预检发现 VM 缺 gcc（CGO 需要）、`actions-runner` 无 sudo（workflow 的 `sudo dnf install gcc` 兜底走不通）、且解析不了 `mac-mini`（`SONAR_HOST_URL` 指向 `http://mac-mini:9000`，原靠 tailnet MagicDNS，本 VM 未装 Tailscale）。
- 影响：VM 上新增系统包与一条 hosts 记录，均为加法操作，不影响既有容器与部署 runner。workflow 改动走 PR，不直接动 main。
- 回滚方式：
  - gcc：`sudo dnf remove gcc glibc-devel`（一般无需回滚，留着无害）
  - hosts：`sudo cp /etc/hosts.bak.20260610 /etc/hosts`
  - workflow：revert PR [iCare-backend#574](https://github.com/cypressoai/iCare-backend/pull/574)
- 做了什么：
  - `sudo dnf install -y gcc glibc-devel`（gcc 11.5.0），workflow 的 `Ensure C Build Toolchain` 步骤会因 gcc 已存在直接短路通过
  - 备份 `/etc/hosts` 为 `/etc/hosts.bak.20260610` 后追加 `192.168.2.170 mac-mini`（mac-mini 与 PVE 同在 192.168.2.0/24 局域网，无需走 Tailscale）
  - 提交 PR iCare-backend#574：两个 job 的 `runs-on` 从 `[mac-mini-sonar, macos, arm64]` 改为 `[self-hosted, mas-go-dev-ci]`，并更新 GOCACHE 注释（单实例 runner 用默认缓存路径，无需 mac-mini 的 per-slot 隔离）
- 验证结果：`getent hosts mac-mini` 返回 `192.168.2.170`；从 VM `curl http://mac-mini:9000/api/system/status` 返回 `"status":"UP"`；PR 触发的 `SonarQube Analysis` run 已调度执行（PR 事件用分支上的新版 workflow，正好实测新 runner）。
- 注意事项：mac-mini 的 `192.168.2.170` 由用户手动静态配置、永不变化（2026-06-10 用户确认），`/etc/hosts` 映射无需担心 DHCP 漂移。

## 2026-06-10 18:06 CST - 新增第二个 GitHub Actions runner `mas-go-dev-ci-1`

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：mac-mini 上 4 个 `mac-mini-sonar-*` runner 承接 MAS CI 任务时 CPU 拥挤、队列积压（见 `docs/operations/mac-mini.md` 2026-06-10 17:05 审计）。评估 PVE 资源后决定在 `mas-go-dev` VM 内新增一个 Linux runner 为 MAS 项目分流 CI 任务。PVE 宿主 CPU 长期空闲（三台 VM 周均 CPU 1.2% / 0.6% / 2.6%）但宿主内存仅余 ~3.7GiB，故不另开 VM/LXC，复用本 VM（内存周均占用 45%，操作时 available 4.5GiB）。
- 影响：纯新增操作，未改动既有 `mas-go-dev` runner、部署目录、容器。新 runner 标签为 `self-hosted, Linux, X64, docker, al2023, mas-go-dev-ci`，**刻意不带 `mas-go-dev` 标签**，避免抢走部署 job 造成并发部署冲突；现有 workflow 不会调度到它，需要分流的 job 显式改 `runs-on: [self-hosted, mas-go-dev-ci]` 才会使用。
- 回滚方式：`cd /opt/actions-runner/mas-go-dev-ci-1 && sudo ./svc.sh stop && sudo ./svc.sh uninstall`，然后 `sudo -u actions-runner ./config.sh remove --token <removal-token>`（token 用 `gh api -X POST orgs/cypressoai/actions/runners/remove-token` 获取），最后删除目录。
- 做了什么：
  - 创建 `/opt/actions-runner/mas-go-dev-ci-1`（owner `actions-runner`），下载并解压 actions/runner `v2.335.1` linux-x64
  - 以 `actions-runner` 用户执行 `config.sh`，注册到组织 `cypressoai`，runner group `mas-go-dev`（visibility: selected，限 MAS 仓库），名称 `mas-go-dev-ci-1`，自定义标签 `mas-go-dev-ci,docker,al2023`
  - `sudo ./svc.sh install actions-runner && sudo ./svc.sh start` 安装并启动 systemd 服务 `actions.runner.cypressoai.mas-go-dev-ci-1.service`（enabled，随 VM 自启）
- 验证结果：systemd 服务 `active (running)`；GitHub API 显示 `mas-go-dev-ci-1` `status: online, busy: false`，标签正确，已在 runner group `mas-go-dev` 中（与既有 `mas-go-dev` runner 并列）。
- 附带发现：PVE 节点级 RRD 历史文件损坏（`rrd_fetch_r failed: mmaping file '/var/lib/rrdcached/db/pve-node-9.0/pve'`，PVE 9 已知问题），本次未处理；各 VM 级 RRD 正常。

## 2026-05-29 CST - 确认 azurite 运行状态 + 沉淀 iCare 项目使用方式

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：用户询问 azurite 是否启动、在 iCare 项目里应该怎么用。做一次只读核查，并把"怎么用"的接法沉淀下来（上线记录 `2026-05-28 12:47` 只写了部署过程，没写消费方如何接入）。
- 影响：纯只读查询（`docker ps` / `docker inspect` / 读 `.env.docker`），未改动任何容器、配置、网络。
- 当前状态（只读核查结果）：
  - `azurite`：`Up`，只启用 **blob** 服务，启动命令 `azurite-blob --blobHost 0.0.0.0 --blobPort 10000 --skipApiVersionCheck`；queue(10001)/table(10002) 未对外暴露。
  - `redis`：`Up`。
  - 两者端口均只 bind `127.0.0.1`（azurite `10000`、redis `6379`），**VM 外部无法直连**。
  - `azurite` 接在 `shared-services` 网络，DNS 名 / 别名为 `azurite`，容器内 IP `172.18.0.4`，`restart: always`（VM 重启自动拉起）。
  - 同网络消费方容器在跑：`icare-backend-api-1`(healthy)、`icare-backend-worker-1`、`mas-icare-portal`。
- iCare 项目使用方式（沉淀，供后续部署/排查参考）：
  - 服务器上 `icare-backend-api-1` / `icare-backend-worker-1` 已接好，连接配置在 `/opt/mas-go-dev/backend/.env.docker`：
    ```
    AZURE_STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=<azurite默认key>;BlobEndpoint=http://azurite:10000/devstoreaccount1;
    ```
  - `AccountName=devstoreaccount1` + 默认 AccountKey 是 Azurite 内置固定账户（官方公开默认值），非真实凭据。
  - **`BlobEndpoint` 的 host 必须写 `azurite`**（`shared-services` 网络 DNS 名），不能写 `localhost`/`127.0.0.1`——对运行在别的容器里的 api/worker 来说 `localhost` 指向它自己。
  - 消费方容器**必须也加入 `shared-services` 网络**才能解析到 `azurite`（`networks: [shared-services]` + `external: true`），这正是 backend compose 的接法。
  - 在 mas-go-dev VM 上跑新服务：直接复用上述连接串 + 加入 `shared-services` 网络即可。
  - 本机本地开发：**连不到 VM 上的 azurite**（端口只绑 127.0.0.1），标准做法是本地另起一个 azurite 容器（`docker run -p 10000:10000 mcr.microsoft.com/azure-storage/azurite azurite-blob --blobHost 0.0.0.0`），连接串里 `BlobEndpoint` 改为 `http://127.0.0.1:10000/devstoreaccount1`，AccountName/Key 沿用同一套默认值，代码无需改动。
- 回滚：无（只读操作，无变更）。

## 2026-05-28 14:55 CST - 部署 build cache 自动清理 timer + 全清历史 cache

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：本仓库 backend Dockerfile + workflow 修复（合并到 develop 后已跑过多个 PR）已验证 build cache 不再无限累积，但磁盘里仍残留 66.91GB 历史 cache 层（其中大量是被新 build 复用的老 591MB Go 编译层）。决定全清一次彻底回收空间，并安装 systemd timer 兜底，防止未来再出现孤儿层堆积。
- 影响：
  - 安装 `docker-builder-prune.service` + `.timer`（root），每天 UTC 20:00（CST 凌晨 4 点）自动清理 168 小时（7 天）未使用的 buildkit cache 层。RandomizedDelaySec=300 避免与其他 timer 同时启动。
  - `sudo docker builder prune -a -f` 全清 buildkit cache，下次 PR build 需要全量重新下载 Go modules + 编译，预计耗时从 3-5 分钟拉长到 8-15 分钟（一次性），多消耗 500MB-1GB 网络流量。
  - 未触碰镜像、容器、卷；正在运行的 `icare-backend-api-1`(healthy)、`icare-backend-worker-1`、`azurite`、`redis`、`mas-icare-portal` 全部未受影响。
- 回滚：
  - timer：`sudo systemctl disable --now docker-builder-prune.timer && sudo rm /etc/systemd/system/docker-builder-prune.{service,timer} && sudo systemctl daemon-reload && sudo rm /var/log/docker-prune.log`
  - cache：不可逆，但下次 build 会按需重建。
- 变更：
  - 新建 `/etc/systemd/system/docker-builder-prune.service`：`Type=oneshot`，执行 `/usr/bin/docker builder prune --filter until=168h --force`，stdout/stderr 追加到 `/var/log/docker-prune.log`。
  - 新建 `/etc/systemd/system/docker-builder-prune.timer`：`OnCalendar=*-*-* 20:00:00 UTC`，`Persistent=true`（断电期间错过的会补跑），`RandomizedDelaySec=300`。
  - `sudo touch /var/log/docker-prune.log && sudo chmod 644`。
  - `sudo systemctl daemon-reload && sudo systemctl enable --now docker-builder-prune.timer`。
  - `sudo docker builder prune -a -f`，回收 66.92GB。
- 验证：
  - `systemctl list-timers docker-builder-prune.timer` 显示 `NEXT=2026-05-28 20:03:48 UTC`（含随机延迟）。
  - 清理前：`Build Cache 993 条 / 66.91GB`，根分区 `74G/120G (62%)`。
  - 清理后：`Build Cache 0 条 / 0B`，根分区 `5.5G/120G (5%)`，可用 `115GB`。
  - `docker ps`：5 个容器全部 `Up`，`icare-backend-api-1` 保持 `healthy`。
- 后续：
  - 观察下次 PR 部署：build 时长（预期 8-15 分钟）、build 完成后 `docker system df` 的 Build Cache 应该回到 1-2GB 级别。
  - 每天 UTC 20:00 后查看 `/var/log/docker-prune.log` 几次，确认 timer 按预期执行。
  - 长期理想态：Build Cache 稳定在 1-2GB（一份完整复用 cache），timer 偶尔清掉过期残留。如果一周后看到 Build Cache 又涨到几十 GB，说明 cache 复用机制再次失效，需要重新排查。

## 2026-05-28 12:47 CST - 上线 iCare 集成测试基础设施容器（azurite + redis）

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：iCare backend 接入 Redis + Asynq 队列（CYP-699）后需要 worker 容器，worker 依赖 Redis 和 Azure Blob（开发态用 Azurite 模拟）。此前这两个依赖只在本地 `compose.dev.yaml` 中提供；mas-go-dev 集成测试环境缺失，导致 worker 无法部署。
- 影响：
  - 在 mas-go-dev 上新增独立 compose project `icare-backend-infra`，运行两个常驻容器 `azurite` + `redis`，接入既有 `shared-services` 网络（172.18.0.0/16）。
  - 同一网络上原有的 `icare-backend-api-1`、`mas-icare-portal` 容器**未重启、未受影响**；只是网络成员从 2 个增加到 4 个。
  - 服务器 `.env.docker` 追加 13 个 worker / queue / azurite 相关环境变量；现有 KEY 不变。
  - 容器端口仅绑 `127.0.0.1`（azurite 10000、redis 6379），不对外暴露。
- 回滚：
  - 容器：`sudo -u actions-runner docker compose -f /opt/mas-go-dev/infra/infra.compose.yaml down -v`（同时清掉持久化卷；如果只是停容器去掉 `-v`）。
  - `.env.docker`：用备份 `/opt/mas-go-dev/backend/.env.docker.bak.20260528-claude-infra-rollout`（818 字节）覆盖回去即可，保持 600 权限。
- 变更：
  - 新建目录 `/opt/mas-go-dev/infra/`，owner `actions-runner:actions-runner`，mode `750`（与 `backend/`、`frontend-mas/` 对齐）。
  - `scp` 仓库内 `iCare/backend/infra.compose.yaml` → `/opt/mas-go-dev/infra/infra.compose.yaml`（mode `644`）。SHA256 比对一致：`38b2e450bc13669f6276983080b15fc15314637ba71f0608b20b27e79347454d`。
  - `sudo -u actions-runner docker compose -f infra.compose.yaml up -d` 启动：
    - `azurite` (image `mcr.microsoft.com/azure-storage/azurite:latest`)，绑 `127.0.0.1:10000`，挂载卷 `icare-backend-infra_azurite-data`，`restart: always`。
    - `redis` (image `redis:7-alpine`)，绑 `127.0.0.1:6379`，挂载卷 `icare-backend-infra_redis-data`，`restart: always`。
  - `/opt/mas-go-dev/backend/.env.docker` 追加 `QUEUE_PROVIDER=redis_asynq` 等 13 个 KEY（先备份为 `.env.docker.bak.20260528-claude-infra-rollout`，文件从 816B → 1558B），保持 `600` 权限。
- 验证：
  - `docker ps` 显示两个容器 `Up`、`restart=always`。
  - `docker network inspect shared-services` 包含 4 个成员：`mas-icare-portal=172.18.0.2`、`icare-backend-api-1=172.18.0.3`、`azurite=172.18.0.4`、`redis=172.18.0.5`。
  - 从 `icare-backend-api-1` 容器内：
    - `getent hosts redis azurite` → 各自解析到 IP，DNS 名一致。
    - TCP：`</dev/tcp/redis/6379` 成功；`curl http://azurite:10000/` 返回 400（裸 GET 被拒，等价"端点活跃"），`curl 'http://azurite:10000/devstoreaccount1?comp=list'` 返回 403（未鉴权请求被正确拒绝，等价"服务真在跑"）。
  - `docker exec redis redis-cli ping` → `PONG`。
  - `docker compose -f /opt/mas-go-dev/backend/backend.compose.yaml config` 解析成功，三个 service `api / seed / worker` 的 environment 中均含新增的 `AZURE_STORAGE_CONNECTION_STRING` 等。
- 后续：
  - **未触发 PR 流水线**。仓库内待提交：`backend/infra.compose.yaml`（新增）、`backend/.env.docker.example`（分组标注三类环境）、`backend/.github/workflows/deploy.yml`（`Deploy local backend container` step 改为 `stop/rm/up api worker` + `--no-deps` + worker RestartCount 存活校验）。
  - PR 合并后由 runner 自动滚 api + worker 新版本，期间 azurite / redis 不会被动到（不同 compose project，部署链路只动 `icare-backend` 的 service）。
  - `infra.compose.yaml` **不进** runner 自动化；仓库内文件变更后，需手动 scp + `docker compose up -d` 同步到 `/opt/mas-go-dev/infra/`。该约定写入 `AGENTS.md`。

## 2026-05-28 12:41 CST - 清理 docker build cache 救磁盘并修复缓存累积根因

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：另一个 session 排查时发现根分区 `/dev/sda1` 占用 98%（`117G/120G`，可用仅 `3.5G`），`/var/lib/docker` 占 113GB，其中 109.4GB 全是 buildkit 构建缓存。镜像本体只有 309MB，问题完全在 build cache。继续累积下去 runner 会因为磁盘满而 build/deploy 失败。
- 影响：
  - 执行 `docker builder prune --filter until=48h`，删除 947 条 48 小时以上未使用的 buildkit cache 层，释放约 35GB。
  - 未触碰镜像、容器、卷；未重启 docker、runner、容器；未改防火墙、SSH、数据库。
  - 同时在 `iCare/backend` 仓库改了 `Dockerfile` 和 `.github/workflows/deploy.yml`（未提交，由用户走 PR 流程），从根因上让后续 build 不再每次累积 ~591MB 新缓存层。
- 回滚：
  - 已清理的 buildkit cache 不可逆，但都是 48 小时以上未访问的孤儿层，下次 build 会按需重新拉取/编译（首次可能慢一些 + 多消耗一点出网流量，但不会破坏数据）。
  - backend 仓库改动可通过 revert PR 回退到 `docker build` 裸跑方式。
- 变更：
  - mas-go-dev 上：`sudo docker builder prune --filter "until=48h" -f`
    - 清理前：`Build Cache 2105 条 / 109.4GB`，根分区 `117G/120G (98%)`
    - 清理后：`Build Cache 1158 条 / 75.39GB`，根分区 `82G/120G (69%)`
  - `iCare/backend/Dockerfile`：4 个 `go build` 合并到一个 `RUN`，加 `--mount=type=cache,target=/root/.cache/go-build,sharing=locked` 和 `--mount=type=cache,target=/go/pkg/mod,sharing=locked`。BuildKit cache mount 的内容不进 image 层，同一 target 路径只保留一份，不会随每次 build 累积。
  - `iCare/backend/.github/workflows/deploy.yml` 中 `deploy-mas-go-dev` job：把裸 `docker build` 换成 `docker/setup-buildx-action@v3` + `docker/build-push-action@v5`，配合 `/tmp/.buildx-cache-mas-go-dev` 本地 cache + 旋转策略，与 `build-and-push` job (`dev-cypresso-ci` runner) 同一套模式。
- 验证：
  - `df -h /` 显示 `82G/120G (69%)`，可用 39GB。
  - `docker system df` 显示镜像、容器、卷均未受影响：`Images 3/2 309.3MB`、`Containers 3/2`、`Volumes 0`。
  - 正在运行的 `icare-backend-api-1` 仍为 `healthy`，`mas-icare-portal` 仍 `Up`。
- 后续：
  - backend PR 合到 `develop` 触发一次 mas-go-dev 部署后，观察 `sudo docker system df` 的 Build Cache 总量。预期稳定在 1-2GB 级别（一份完整 buildkit cache），而不是每个 PR 多 591MB。
  - 跑 2-3 个 PR 验证 cache 真正稳定后，再考虑在 mas-go-dev 加 cron 作为兜底（`0 4 * * * docker builder prune --filter "until=168h" -f`，每天清 7 天未用的）。现在不加 cron，因为如果根因没修好，cron 只会把"撑爆磁盘"变成"周期性丢缓存 + 重新拉网络流量"，和原本"少用网络"的目标冲突。
  - 当前剩余 75GB build cache 都是 48h 内的层；修复合并后会被新的复用结构逐步替换，不需要额外动作。

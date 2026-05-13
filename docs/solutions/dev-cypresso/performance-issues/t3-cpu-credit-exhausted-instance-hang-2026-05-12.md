---
title: t3.xlarge CPU credit 耗尽导致实例僵死、AWS status check 失败
date: 2026-05-12
category: docs/solutions/dev-cypresso/performance-issues
server: dev-cypresso
module: dev-cypresso / EC2 实例容量规划
problem_type: performance_issue
component: infrastructure
severity: high
symptoms:
  - SSH 长时间无法连接（connect timeout），AWS 控制台显示 Instance status check failed
  - 实例状态仍为 running，但 system reachability check 失败近 2 小时
  - 故障窗口内 CloudWatch CPUUtilization 跌至 5–15%，远低于 t3.xlarge 40% 基线（CPU steal）
  - 故障前 5 小时（02:30–07:30 UTC）CPUUtilization 持续在 50–97% 反复峰值
  - 系统僵死前 dockerd / tailscaled / GitHub Actions runner 大面积超时，journald 日志落盘滞后 6 分钟
  - 没有任何 OOM killer / kernel panic / hung_task 记录
  - 重启后 https://mas-icare.cypress.sg/ 504 不可达，nginx 启动期因 DNS 解析失败 systemd `Active=failed`
  - 重启后 icare-backend / telegram-bot 容器陷入 restart loop，DNS 解析公网域名和 tailscale magicDNS 域名均超时
root_cause: resource_exhaustion
resolution_type: configuration_change
tags: [aws, ec2, t3, cpu-credit, burstable, instance-hang, status-check-failed, dev-cypresso, capacity-planning, dns, tailscale, docker, nginx]
---

# t3.xlarge CPU credit 耗尽导致实例僵死、AWS status check 失败

## Problem

dev-cypresso（EC2 实例 `i-0608f008a58c42db0`，类型 `t3.xlarge`，4 vCPU / 16 GiB，us-east-1d）于 2026-05-12 **12:08 UTC** 起整机失去响应：SSH 连接超时、Tailscale 中断、所有容器服务不可用。AWS 控制台显示 **Instance status check failed**，实例状态仍为 running。该状态持续约 **1 小时 55 分钟**，直到 14:03 在控制台手动 Reboot 后恢复。

但 **Reboot 不是终点**：重启后又出现一连串"长尾"问题——`nginx` 因启动期 DNS 不可用退出后未恢复，导致面向公网的 `https://mas-icare.cypress.sg/` 全天不可达；`icare-backend-api-1` 因 `.env` 配置错误用 tailscale magicDNS 连同机数据库，在 tailscale 未完全接入时 restart loop；`telegram-bot-bot-1` 因 tailscale 接管的宿主 DNS 无法解析公网域名而 restart loop。本文档同时记录故障根因和后续系统加固。

故障期间内核日志几乎不可用——journald 在挂死前已停止写盘，AWS "Get system log" 仅能取到重启后新 boot 的早期 dmesg；唯一连续可信的证据是 CloudWatch 的 CPUUtilization 时间序列。

## Symptoms

### 主故障（12:08–14:03 UTC）

- SSH `connect timeout`；AWS 控制台 `Instance status check failed`
- 实例 running，但 system reachability 在 12:08–14:03 期间持续失败
- 重启后 `uptime` 显示 `up 3 min`，`last reboot` 印证只有一次新启动，wtmp 中没有 shutdown 记录（属于硬重启，非正常关机）
- 上一次 boot（2026-02-26 起跑 75 天）最后日志停在 `2026-05-12 12:08:32`，之后到 14:03 完全静默
- 12:08 前的 2.5 小时内大量出现：
  - `dockerd ... resolver failed to query DNS server: 100.100.100.100:53 ... i/o timeout`
  - `tailscaled ... subscriber for health.Change is slow (9m → 41m elapsed)`（数字一路涨到 41 分钟）
  - `dockerd ... timed out starting health check for container ...`
  - `runsvc.sh: Runner connect error: The HTTP request timed out after 00:01:40`
  - dockerd 日志条目自带时间戳比 journald 写入时间**滞后 6 分钟**（如 09:58:51 写入的条目内含 09:52:47 的事件）
- CloudWatch CPUUtilization（UTC）：
  - 02:30–07:30 多次冲到 95%+，长时间在 50–97% 区间反复
  - 07:53 达 97.7%（最后一次能压住 CPU 的尖峰）
  - 09:00 后断崖式跌至 5–15%，与 t3.xlarge 40% 基线对比是反常的低值（CPU steal）
  - 12:08–14:00 仍维持在 5–15%，14:03 出现一根重启尖峰
- 没有任何 OOM、kernel panic、softlockup、hung_task 内核记录

### 重启后的长尾问题（14:03 之后）

- `https://mas-icare.cypress.sg/` 全天不可达（团队报障的入口）
- `nginx.service` 状态 `Active=failed (Result: exit-code) since Tue 2026-05-12 14:04:05 UTC`
- nginx 日志：`[emerg] host not found in upstream "api-icare.cypress.sg" in /etc/nginx/conf.d/mas-icare.cypress.sg.conf:5`
- `icare-backend-api-1`：`Restarting (1)`，日志反复 `lookup ip-172-31-42-99.taila93443.ts.net on 127.0.0.11:53: server misbehaving`
- `telegram-bot-bot-1`：`Restarting (1)`，日志反复 `Cannot connect to host api.telegram.org:443: Temporary failure in name resolution`
- 宿主机直接执行 `dig @100.100.100.100 +short api.telegram.org` 返回空答复（tailscale magicDNS 对公网域名解析失效）
- 同时 `dig @172.31.0.2 +short api.telegram.org` 立刻返回 IP（AWS VPC DNS 正常）
- 当时机器还跑着 **3 个** GitHub Actions runner、**0 swap**、**zram 主动放弃创建**（`zram0: system has too much memory (15791MB), limit is 800MB, ignoring`）

## Investigation

### 主故障：CPU credit 耗尽假说

t3 系列是**可突发实例**：每 vCPU 每小时累积 24 个 credit（即 40% 持续利用率为基线），credit 耗尽后 CPU 被 hypervisor 限速到基线以下，并在 CloudWatch 中表现为 CPUUtilization 反常低 + 高 CPU steal。

时间线对照 CPU 图：

| 时段 (UTC) | CPU% | 解读 |
|---|---|---|
| 02:30–07:30 | 50–97% 反复峰值 | 远超基线，credit 持续被消耗 |
| 07:53 | 97.7%（最后一根高峰） | credit 进入耗尽前的尾声 |
| 09:00 起 | **断崖下跌至 5–15%** | credit 耗尽 → throttle 到 baseline 之下；进程开始大面积超时 |
| 12:08 | 仍 5–15% | 整机已僵死，几乎所有任务阻塞在等 I/O |
| 14:03 | 重启尖峰 | 手动 reboot |

09:00 后 CPU% 低于 40% 基线，这只能用 throttle + CPU steal 解释——实例**未启用 unlimited 模式**，credit 真正耗光后 hypervisor 直接掐 CPU 时间片。

排除内核崩溃：

```bash
sudo journalctl -b -1 -k | grep -iE 'oom|killed|panic|stall|softlockup|hung_task|trace'
# 仅命中 zram_generator 的常规 INFO（与本次无关），无任何 OOM / panic / hung 证据
```

→ 不是内核 panic、不是 OOM，是**应用层全面饥饿但内核仍活着**的状态。

### 实例负载与容量错配

该实例同时常驻 13+ 个服务，远超 t3.xlarge 合理承载：SonarQube + Elasticsearch、ClickHouse、MSSQL、MongoDB + mongot、Postgres、Redis、RabbitMQ、多个业务后端、3 个 GitHub Actions self-hosted runner。任何 SonarQube 扫描、CI 任务、ClickHouse 查询叠加，都会把日均 CPU 拉过 40% 基线。本次很可能是凌晨某次扫描/构建触发，并在 5+ 小时内把累计 credit 全部燃尽。

### 长尾问题 1：nginx 启动期 DNS 依赖

`mas-icare.cypress.sg.conf` 在 `location /api/` 用了 `proxy_pass https://api-icare.cypress.sg/api/`——**域名形式的 upstream**。nginx 启动时强制解析所有 upstream 域名，解析失败立刻 emerg 退出（`exit-code`，无 Restart）。

14:03 整机重启后：
1. `tailscaled` 启动早于完成 control plane 接入，期间 `100.100.100.100` 不响应
2. nginx 在 14:04:05 启动 → 解析 `api-icare.cypress.sg` 走 `/etc/resolv.conf` 里唯一的 tailscale DNS → 超时失败
3. nginx 退出，`Active=failed`，没有重试机制
4. 此后即使 tailscale 接入完成，nginx 也不会自动重启 → 全天 `mas-icare.cypress.sg` 不可达

### 长尾问题 2：icare-backend 用 tailscale magicDNS 连同机数据库

`/home/ec2-user/stacks/icare/.env` 配置：

```env
DB_HOST=ip-172-31-42-99.taila93443.ts.net  # 同机的 tailscale 域名
DB_PORT=14330                              # 通过 host 端口映射
```

要连的 SQL Server (`shared-sqlserver`) 就在**同一台机器**上，但绕道：

```
icare-backend 容器
  → docker 内嵌 DNS 127.0.0.11
  → 转发到宿主 /etc/resolv.conf 的 100.100.100.100（tailscale）
  → 返回本机 tailscale IP 100.115.69.120
  → 走 tailscale0 接口 wireguard 加解密
  → 才回到宿主机 14330 端口
```

任何一步 tailscale 抖动都会断链。

### 长尾问题 3：tailscale 接管 `/etc/resolv.conf` 导致公网解析失败

```bash
cat /etc/resolv.conf
# # resolv.conf(5) file generated by tailscale
# nameserver 100.100.100.100
# nameserver fd7a:115c:a1e0::53
```

tailscale 默认 `--accept-dns=true` 时会用 `100.100.100.100` 完全覆盖系统 DNS，没有 fallback。CPU throttle 期间 tailscaled 自顾不暇，公网域名解析的上游转发链路同步失效，**整个宿主机所有公网 DNS 查询返回空答复**（`MSG SIZE rcvd: 38`，技术上"成功"但 0 个 answer）。这直接波及：
- 宿主机进程（nginx 启动失败）
- 容器内嵌 resolver 转发的查询（telegram-bot 连不上 `api.telegram.org`）

## Root Cause

主故障根因：**t3.xlarge 在长期高于 40% 基线的负载下耗尽 CPU credits，未启用 Unlimited 模式，被 hypervisor 限速到基线以下；叠加 0 swap 的内存回收路径无缓冲，最终整机进入"内核活着但用户态全部阻塞"的僵死状态，AWS instance status check 心跳超时。**

简言之：长期超载 + 实例类型选错（突发型用作长期高负载）+ 没开 Unlimited + 没有 swap。

长尾问题根因：**tailscale 默认接管宿主机 DNS 形成单点依赖，且没有 fallback**。任何宿主进程（nginx）、任何容器（telegram-bot 公网查询、icare-backend 同机查询）的解析都被绑定到 tailscaled 的可用性上。tailscale 慢启动或 CPU 不足时整条 DNS 链路全断；nginx 这种"启动期解析失败就直接退出"的进程会出现长期不可恢复的状态。

## Resolution

### 立即恢复

在 AWS 控制台对实例触发 **Reboot**，14:03 UTC 系统恢复（但留下了下面的长尾问题）。

### 系统加固（2026-05-12 当天完成）

按性价比从高到低，全部已落地：

#### 1. 4G swap 启用（弥补 0 swap 缺口）

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swap.conf
sudo sysctl -p /etc/sysctl.d/99-swap.conf
```

#### 2. 缩减 GitHub Actions Runner 从 3 个到 1 个

之前 3 个 runner（agentId 17/18/19，runner-2 早已 disabled）并发跑 CI 是 CPU 突刺的主要来源。保留 `internal`（agentId=17，最老的主 runner），停用并 disable `internal-3`：

```bash
sudo systemctl stop  actions.runner.cypressoai.ip-172-31-42-99.ec2.internal-3.service
sudo systemctl disable actions.runner.cypressoai.ip-172-31-42-99.ec2.internal-3.service
```

> GitHub org settings 里的离线 runner 注册条目无需清理；调度器只看 online 的 runner，不会卡 job。

#### 3. icare-backend 改走 docker 内网（DNS 解耦 tailscale）

把 `/home/ec2-user/stacks/icare/.env` 的 `DB_HOST` 从 `ip-172-31-42-99.taila93443.ts.net:14330` 改为 docker network 内的服务名 `shared-sqlserver:1433`；`backend.compose.yaml` 给 api 和 seed 加入 `shared-services` 外部网络（infra 用的同一个网络）。

```yaml
# backend.compose.yaml 片段
services:
  api:
    # ...
    networks:
      - default
      - shared
  seed:
    # ...
    networks:
      - default
      - shared

networks:
  shared:
    name: shared-services
    external: true
```

`.env`:

```diff
- DB_HOST=ip-172-31-42-99.taila93443.ts.net
- DB_PORT=14330
+ DB_HOST=shared-sqlserver
+ DB_PORT=1433
```

> compose 文件里有 `env_file: ${DOCKER_ENV_FILE:-.env.docker}`，但目录里实际只有 `.env`——补一个软链 `.env.docker -> .env`，否则 docker-compose 会报 `env file not found` 拒绝启动。

应用变更：

```bash
cd /home/ec2-user/stacks/icare
CURRENT_IMG=$(sudo docker inspect icare-backend-api-1 --format '{{.Config.Image}}')
BACKEND_IMAGE=$CURRENT_IMG sudo -E -u ec2-user env BACKEND_IMAGE=$CURRENT_IMG \
  docker-compose -f backend.compose.yaml up -d --force-recreate --no-build api
```

效果：容器双网络，`getent hosts shared-sqlserver` → `172.19.0.x`（docker 内部 DNS），**完全不经过 tailscale**。

> ⚠️ `.env` 中包含 SQL Server 明文密码，按 AGENTS.md 约定不落文档。仓库 `.gitignore` 应排除该 `.env`（确认动作未做）。

#### 4. 给 infra 容器加 mem_limit（防失控吃光整机）

只限"可能失控"的 infra（postgres / redis / mongodb / rabbitmq / sqlserver / clickhouse / sonarqube），**核心业务容器（cypresso-api / icare-backend-api-1 / mas-icare-portal）刻意不加限制**——mem_limit 是硬天花板防失控，不是预算分配，业务侧需要给足资源。

设计原则：合计硬上限可大于物理内存（"允许借用"），单容器失控时 OOM 单杀，整机不挂。

```yaml
# /home/ec2-user/stacks/infra/docker-compose.yml 各服务追加
postgres:   { mem_limit: 2g }
redis:      { mem_limit: 512m }   # 同时给 command 加 --maxmemory 480mb --maxmemory-policy allkeys-lru
mongodb:    { mem_limit: 3g }
rabbitmq:   { mem_limit: 1g }
sqlserver:  { mem_limit: 4g }
clickhouse: { mem_limit: 3g }
sonarqube:  { mem_limit: 4g }
```

合计 17.5 G 硬上限 / 物理 15 G + 4 G swap，靠"借用未使用资源"维持。重建用 `docker-compose up -d`，整体耗时约 20 秒。

#### 5. Docker daemon 三级 DNS fallback（容器侧治本）

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<'JSON'
{
  "dns": ["172.31.0.2", "8.8.8.8", "100.100.100.100"]
}
JSON
sudo systemctl restart docker
```

容器内嵌 resolver `127.0.0.11` 转发时按顺序尝试：AWS VPC DNS（必通）→ Google → tailscale。docker daemon 重启全量容器约 30 秒。

#### 6. Tailscale 不再接管宿主机 DNS（宿主侧治本）

```bash
sudo tailscale up --accept-dns=false
```

宿主机 DNS 回到系统默认（DHCP 拿到的 AWS VPC DNS）。**代价**：宿主机无法直接解析 `*.taila93443.ts.net`；容器内通过 daemon.json 的 fallback 仍可（最后一档 100.100.100.100）。tailscale 网络本身（节点间 100.x.x.x IP 通信）不受影响。

#### 7. 拉起 nginx

```bash
sudo nginx -t                       # syntax is ok
sudo systemctl start nginx          # 启动
sudo systemctl is-active nginx      # active
```

最终验证：`curl https://mas-icare.cypress.sg/` → HTTP 200。

### 待执行（已和团队对齐）

- **升级实例到 m6i.xlarge**（同代非突发，4 vCPU / 16 GiB，无 credit 限制）—— 由另一位同事执行。流程：在 AWS 控制台 Stop → ModifyInstanceAttribute → Start，约 3–8 分钟停机；EBS、私有 IP、Elastic IP 不变；t3 与 m6i 都是 x86_64/Nitro，AMI 直接兼容
- **同步 iCare 团队** `backend.compose.yaml` 和 `.env` 的修改（CI/CD 推镜像不涉及这两个文件，不会冲突；备份留作 `*.bak.20260512`）
- **CloudWatch 告警**：`CPUCreditBalance < 50`、`StatusCheckFailed_Instance > 0`、`CPUSurplusCreditsCharged > 0`——等同事开 AWS CLI 后配置
- **cypresso-api 持续 52% CPU 无负载**——已交由该项目同事自查
- **nginx 加自愈**（可选）：在 `/etc/systemd/system/nginx.service.d/override.conf` 加 `Restart=on-failure` + `RestartSec=30s`，避免下次启动期偶发失败后无人恢复
- ~~**SonarQube 迁出到 mac-mini**~~ → **2026-05-13 已完成**，详见 `docs/solutions/mac-mini/sonarqube-migrated-from-dev-cypresso-2026-05-13.md`。客户端切换 + 停 dev-cypresso 上 sonarqube 容器待业主明早执行

## Verification

```bash
# 1. swap 已启用
ssh dev-cypresso "free -h && swapon --show"

# 2. 仅 1 个 runner active
ssh dev-cypresso "systemctl list-units --no-legend 'actions.runner*' | grep active"

# 3. infra 容器全部 healthy 且有 mem_limit
ssh dev-cypresso "docker ps --filter 'name=shared-' --format 'table {{.Names}}\t{{.Status}}' && \
  docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}'"

# 4. icare-backend 走 docker 内网且 healthy
ssh dev-cypresso "docker exec icare-backend-api-1 getent hosts shared-sqlserver && \
  docker inspect icare-backend-api-1 --format '{{.State.Health.Status}}'"

# 5. 容器内可解析公网域名（不再依赖 tailscale）
ssh dev-cypresso "docker exec telegram-bot-bot-1 getent hosts api.telegram.org"

# 6. nginx active 且公网入口 200
ssh dev-cypresso "systemctl is-active nginx"
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' https://mas-icare.cypress.sg/
```

升级到 m6i.xlarge 后还需补充：

```bash
# 7. 实例类型切换成功
aws ec2 describe-instances --instance-ids i-0608f008a58c42db0 \
  --query 'Reservations[0].Instances[0].InstanceType'

# 8. status check 24h 连续通过
aws ec2 describe-instance-status --instance-ids i-0608f008a58c42db0

# 9. 不再有 CPU credit 概念（m6i 不是 burstable）
# CloudWatch CPUCreditBalance 指标对 m6i 不再存在；只看 CPUUtilization 长期 <70% 即可
```

## Lessons

- **突发型实例不适合作为长期重载平台**。t3/t4g 系列的 credit 模型对"日均 CPU < 40%、偶尔尖峰"场景最优；像 dev-cypresso 这种 24h 跑 DB + ES + CI runner 的混合负载，本质需求是 m 系列通用型。
- **CPU credit 耗尽的征兆是"CPUUtilization 反常低 + 系统响应变慢"**，不是"CPU 100%"。监控时要看 `CPUCreditBalance` 和 `CPUSurplusCreditsCharged`，单看利用率会误判为"系统很闲"。
- **僵死比崩溃更难排查**：journald 写不进盘、AWS system log 只能拿当前 boot。证据要从 CloudWatch + 挂死前 1–3 小时的 journald 慢速增长信号（如 tailscale `subscriber slow` 的耗时数字）里拼。
- **0 swap 是高内存机器的常见地雷**：zram_generator 对 > 800MB 的机器主动放弃创建，AMI 默认也不带 swapfile。需要手动加。
- **Tailscale 默认 `--accept-dns=true` 是个隐藏单点**：它会用 `100.100.100.100` 完全替换 `/etc/resolv.conf`，没有 fallback。一旦 tailscaled 慢启动或自身受 CPU 影响，宿主机所有公网 DNS 查询返回空答复（不是连接被拒，是答案为空，更难诊断）。生产/共享开发机要么 `--accept-dns=false`，要么用 systemd-resolved 配 fallback。
- **业务不应该用 tailscale magicDNS 连同机服务**。即使能跑通，相当于把"两个本机进程间通信"绕道到了"远程网络可达性 + DNS 可达性 + WireGuard 加解密"上，把简单依赖变成了三个外部依赖。同机服务用 docker 内部网络 + service name 是正确做法。
- **nginx upstream 用域名 + 默认 systemd 配置 = 启动期单点**。`proxy_pass https://example.com/...` 这种写法会让 nginx 启动时硬性解析；解析失败直接 `exit-code` 且不重试。要么 upstream 用 IP / 同机 docker 服务名、要么在 `nginx.service` 加 `Restart=on-failure` 自愈、要么用 `resolver` 指令做运行时解析。
- **mem_limit 用于"防失控"，不是"分配预算"**。容器只用它实际需要的，limit 是硬天花板。所以核心业务可以不限（让其充分使用），只限可能膨胀的 infra（DB、JVM、缓存类），合计硬上限大于物理 RAM 是合理的，靠"借用未使用资源"。

## References

- AWS docs: [Burstable performance instances - CPU credits and baseline utilization](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/burstable-performance-instances-unlimited-mode.html)
- Tailscale docs: [DNS settings and `--accept-dns`](https://tailscale.com/kb/1054/dns)
- Docker docs: [Configure the Docker daemon DNS](https://docs.docker.com/engine/network/#dns-services)
- 本次 console output 留档：`logs/i-0608f008a58c42db0.log`（仅当前 boot 早期 dmesg，无故障期内核日志）
- 关联：本机服务备份文件命名 `*.bak.20260512`（infra docker-compose.yml、icare backend.compose.yaml、icare .env）

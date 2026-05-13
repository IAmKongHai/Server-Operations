---
title: SonarQube 从 dev-cypresso 迁移到 mac-mini（含 PG 升级到独立 17、CSS 修补保留）
date: 2026-05-13
category: docs/solutions/mac-mini/workflow-issues
server: mac-mini
module: mac-mini / SonarQube (sonar.cypresso.ai 内部入口)
problem_type: workflow_issue
component: infrastructure
severity: medium
symptoms:
  - SonarQube 在 dev-cypresso 持续占 ~10% CPU + 2.1G RAM，是 2026-05-12 实例僵死的间接放大器
  - SonarQube 26.x 跑在 PostgreSQL 18 上（unsupported configuration），未来一定踩雷
  - 业主在 dev-cypresso 上手工修复了 SonarQube 26.3.0 缺失的 CSS grid utility 类 Bug，但修复文件不在 git，存在两个位置（sonarqube-web bind mount + nginx alias），维护混乱
root_cause: capacity_mismatch
resolution_type: workflow_improvement
tags: [sonarqube, postgres, migration, mac-mini, dev-cypresso, tailscale, capacity]
---

# SonarQube 从 dev-cypresso 迁移到 mac-mini

## TL;DR（业主明早第一眼看的部分）

✅ **mac-mini 上的 SonarQube 已经跑起来，数据完整**。可以直接通过：
- **新地址**：`http://mac-mini:9000`（tailscale 短域名，团队所有 tailscale 节点延迟 < 10ms）
- 旧地址 `https://sonar.cypresso.ai` **仍然可用**（dev-cypresso 上没动），所以**没有应急压力**

需要业主明早做的事，按优先级：
1. **用浏览器登录 `http://mac-mini:9000` 验证一遍 UI**（具体清单见下方 §3）
2. **如果验证 OK**：切换团队的 `sonar.host.url` 配置到新地址（具体清单见下方 §4）
3. **客户端切换稳定 24h 后**：停 dev-cypresso 上的 sonarqube 容器（命令见下方 §5）
4. **一周后**：清理 dev-cypresso 上的旧 volumes 和 compose 条目（不急）

回滚方案在 §6。

---

## 1. 迁移背景

### 起因
2026-05-12 dev-cypresso（t3.xlarge）整机僵死故障的故障归因之一是"长期 CPU 高位"，SonarQube 是占 ~10% 持续 CPU 的最大单一进程。配合升级 m6i.xlarge 之外的"减压"动作，把 SonarQube 整体搬走是性价比最高的优化之一。

详见 `docs/solutions/dev-cypresso/performance-issues/t3-cpu-credit-exhausted-instance-hang-2026-05-12.md`。

### 顺手解决的另一个隐患
dev-cypresso 上 SonarQube 26.x 连接的是 `shared-postgres`（**PostgreSQL 18.3**）。SonarQube 26.x 官方仅支持 PG **13–17**，PG18 不在支持矩阵里——目前能跑只是没踩到差异点。这次迁移正好把 PG 改成独立的 **PostgreSQL 17**，回到支持矩阵内。

### 迁移计划文档
完整的计划、决策、风险分析见 `docs/plans/2026-05-13-001-refactor-sonarqube-migrate-to-mac-mini-plan.md`。

---

## 2. 新环境的物理形态

### 位置与文件
mac-mini 上 `~/stacks/sonarqube/`：

```
~/stacks/sonarqube/
├── docker-compose.yml          # 两个 service: sonar-postgres + sonarqube
├── .env                        # DB 凭证（chmod 600，与 dev-cypresso 一致）
├── .env.example                # 模板
├── sonarqube-web/              # 业主修复的 CSS / web.xml / 622 个文件
└── migration/                  # 一次性数据，迁移完成 7 天后可清理
    ├── sonarqube.sql           # PG18 pg_dump 输出（已删 PG18 特有的 \restrict 指令）
    ├── sonarqube.sql.orig      # 原始 dump（带 \restrict）
    └── plugins.tar.gz          # community-branch-plugin-26.3.0
```

### 容器与端口
- `sonar-postgres` — `postgres:17-alpine`，只在 docker network `sonar-net` 内暴露 5432，宿主机不暴露
- `sonarqube` — `sonarqube:26.3.0.120487-community`，暴露 `0.0.0.0:9000` 给 tailnet

### 网络
团队访问路径：
```
团队成员设备 (tailscale) → mac-mini:9000 (tailscale 短域名) → sonarqube 容器
```
不需要公网、不需要 nginx、不需要 HTTPS（tailscale 链路本身加密）。

### 资源使用（启动后 1 分钟实测）
- mac-mini 总资源：32G RAM、10 核 M4
- sonarqube 占用：未限制（你的明确要求）
- sonar-postgres 占用：未限制

---

## 3. 浏览器验证清单（业主明早做）

打开 `http://mac-mini:9000`，按顺序验证：

| # | 验证项 | 期望 | 异常处理 |
|---|---|---|---|
| 1 | 登录页加载 | UI 样式正常（这是验证 CSS Bug 修复保留的关键） | 见 §7 |
| 2 | 用 admin 或团队账号登录 | 登录成功 | 密码 hash 已随 DB 迁移，账号密码不变 |
| 3 | 项目列表 | 看到 13 个项目（含 Telegram-bot、cypresso-api、cypresso-doc、cypresso-infra、cypresso-ui、iCare-backend 多分支） | 用 §8 的 SQL 直接对比 |
| 4 | 任意一个项目点进去 | 历史 Issue、Measures、Quality Gate 全可见 | |
| 5 | Quality Profiles 页面 | 看到 4 个自定义 Profile：Cypresso CSS Way / Go Way / Python Way / typescript Way | |
| 6 | Administration → Marketplace（admin 账号） | 看到 "Community Branch Plugin / 26.3.0" 已安装 | |
| 7 | Administration → System | 看到 26.3.0.120487 版本，DB 信息显示 PG17 | |
| 8 | 浏览器 DevTools Network 面板 | 无 404 / 500 的静态资源（已用 curl 验证 favicon / apple-touch-icon / main-DQgggLOs.css / main-BHI4wvfe.js 全部 200） | |

### 已通过 API + DB 完成的预验证（你不需要重做）
- ✅ `/api/system/status` → `{"status":"UP","version":"26.3.0.120487"}`
- ✅ users 表 5 行（admin + bob28125 + hon0039764 + k-cypresso75908 + mcypresso53169）与 dev-cypresso 完全一致
- ✅ projects 13 行、rules 13174 行、issues 25510 行、components 18756 行——四个数都和 dev-cypresso 对账一致
- ✅ Community Branch Plugin 在 sonarqube 启动日志显式 Deploy 成功
- ✅ 关键静态资源 sha256（WEB-INF/web.xml、main-DQgggLOs.css、favicon.ico）三端（dev-cypresso 源、笔记本中转、mac-mini 终点）完全一致
- ✅ DB 大小 263MB（vs dev-cypresso 上 302MB，差异是社区版没有的 organization 表 + 索引压缩）

---

## 4. 客户端切换（✅ 2026-05-13 早晨已完成）

### 4.1 切换原理（为什么改 GitHub Secret 就够了）

走 CI 自动扫描的链路：

```
1. 你 push / 开 PR
   ↓
2. GitHub 看到 .github/workflows/sonar.yml 被触发
   ↓
3. GitHub 把 job 排队到 labels 匹配的 runner 池
   （job 头部：runs-on: [mac-mini-sonar, macos, arm64]）
   ↓
4. mac-mini 上空闲的 runner 通过【长轮询】主动问 GitHub："有活吗？"
   （这是 runner → GitHub 的出站连接，GitHub 永远不会主动连 runner）
   ↓
5. runner 拿到 job，从 GitHub 拉代码、跑测试、跑 SonarScanner
   ↓
6. SonarScanner 把分析报告【从 runner 直接 POST 到】 SONAR_HOST_URL
   （runner 和 sonarqube 都在 mac-mini 上，走 tailscale magicDNS）
   ↓
7. job 结束，runner 上报 job 状态到 GitHub
```

**关键事实**：
- GitHub **永远不需要**访问 mac-mini —— runner 是主动外联的
- Secret `SONAR_HOST_URL` 只是个**字符串变量**，存在 GitHub 上，但**实际拨号的是 runner**
- 整条链路只需要：runner → GitHub（出站）+ runner → SonarQube（同机 localhost / tailscale）
- **mac-mini 上的 4 个 `mac-mini-sonar-*` runner 不需要改任何配置**——runner 是 worker，不缓存 sonar 配置；job 里的 `SONAR_HOST_URL` 来自 GitHub Secret，每次 job 启动时注入

### 4.2 实际改动（已完成）

#### 改了 secret 的 7 个仓库

用 `gh secret set SONAR_HOST_URL --repo cypressoai/<repo>` 批量改：

| Repo | 改后值 |
|---|---|
| cypressoai/iCare | `http://mac-mini:9000` |
| cypressoai/iCare-frontend-mas | `http://mac-mini:9000` |
| cypressoai/iCare-backend | `http://mac-mini:9000` |
| cypressoai/iCare-mobile-app | `http://mac-mini:9000` |
| cypressoai/iCare-frontend-map | `http://mac-mini:9000` |
| cypressoai/iCare-frontend-hr-portal | `http://mac-mini:9000` |
| cypressoai/cypresso-infra | `http://mac-mini:9000` |

`SONAR_TOKEN` **没动**——所有 user token 都在 DB 里随迁移完整带过来了，token 字符串不变。

#### 没有 SONAR secret 的 4 个仓库

`cypressoai_*` 项目在 SonarQube 上有项目记录但 GitHub repo 上**没有 SONAR_HOST_URL / SONAR_TOKEN secret，也没有 sonar.yml workflow**：

- cypressoai/cypresso-api
- cypressoai/cypresso-doc
- cypressoai/cypresso-ui
- cypressoai/Telegram-bot

可能是历史遗留（以前接过 sonar 后来 yml 被删，但 SQ 里项目数据保留），或者本地手动跑过 `sonar-scanner`。**当前没有 CI 在用旧 host 扫描这些项目**，所以迁移不受影响。

如果未来要恢复对它们的 CI 扫描，按这 7 个仓库的样子加 `sonar.yml` + 仓库 secret 即可。

### 4.3 端到端验证（2026-05-13 01:38–01:40 UTC）

手动触发 `iCare-backend` 的 `SonarQube Analysis` workflow_dispatch（develop 分支）：

```bash
gh workflow run "SonarQube Analysis" --repo cypressoai/iCare-backend --ref develop
```

监控结果：

```
01:38:51 [1] in_progress
...
01:40:37 [10] completed | success      ← 约 2 分钟
```

DB 层验证扫描确实进入了 mac-mini 上的 SonarQube：

```sql
SELECT c.kee, to_timestamp(s.analysis_date/1000) AT TIME ZONE 'UTC' AS analysis_utc
FROM snapshots s
JOIN components c ON s.root_component_uuid = c.uuid
WHERE s.created_at > extract(epoch from now() - interval '15 minutes') * 1000
ORDER BY s.created_at DESC;

-- 返回：
-- cypressoai_iCare-backend_ef8f228f-...   2026-05-13 01:40:26
```

完整链路一次走通：GitHub workflow_dispatch → mac-mini runner 拉 job → 跑 `go test` + `sonar-scan-action` → 报告 POST 到 `http://mac-mini:9000` → PG17 落盘 → 新分析记录可见。

### 4.4 关于 host 值的选择

候选：

| 候选 | 优点 | 缺点 |
|---|---|---|
| `http://mac-mini:9000` ✅ 选用 | 团队成员（mac-mini 之外的设备）也能用同一个 URL；可读 | runner 在 mac-mini 上时多一步 mDNS 解析 |
| `http://localhost:9000` | 最快，runner ↔ sonarqube 同机时零网络 | 如果未来 runner 换机器，URL 需要改 |
| `http://100.108.64.126:9000` | 不依赖 mDNS | 不可读，mac-mini 重新加入 tailnet 时 IP 可能变 |

按业主 2026-05-13 决定，统一用 `http://mac-mini:9000`。

### 4.5 IDE / 本地工具切换（自查）

走 CI 的扫描已经全部切到新地址。**本地 IDE 集成的扫描**（SonarLint、IntelliJ 插件、VS Code 插件）需要团队成员自查：

- IDE 中"SonarQube Server" 连接配置的 URL 改成 `http://mac-mini:9000`
- 复用同样的 SONAR_TOKEN（DB 里的 token 全保留）
- IDE 必须能访问 tailscale 网络（绝大多数团队成员已经在用）

---

## 5. 停 dev-cypresso 上的 SonarQube（✅ 2026-05-13 早晨已执行）

**已完成**：业主在 mac-mini 上完成 UI 验证后立刻执行，详见末尾的实际记录。

**注意**：这台机上是老版 `docker-compose` (v1)，没有 v2 `docker compose` 子命令。一定要用 v1 命令：

```bash
# 仅停止，不删除 — 保留 volumes 作为回滚兜底
ssh dev-cypresso "cd /home/ec2-user/stacks/infra && sudo -u ec2-user docker-compose stop sonarqube"

# 验证
ssh dev-cypresso "sudo docker ps -a --filter name=sonarqube --format 'table {{.Names}}\t{{.Status}}'"
# 应看到 sonarqube  Exited (...)

# 释放的资源（监控 24h 后看 CloudWatch）：
# - mem_limit=4G 配额 + 实际占用 2.1G RAM 回到系统
# - 持续 ~10% CPU 下降
```

**保留 7 天后**才考虑清理 volumes：
```bash
# 7 天后（确认 mac-mini 上运行稳定，业务团队也用得习惯）：
ssh dev-cypresso "sudo docker compose -f /home/ec2-user/stacks/infra/docker-compose.yml rm -f sonarqube"
ssh dev-cypresso "sudo docker volume rm sonarqube_data sonarqube_extensions sonarqube_logs sonarqube_temp"

# 同时清掉 shared-postgres 上的 sonarqube 库（302MB 死数据）：
ssh dev-cypresso "sudo docker exec shared-postgres psql -U postgres -c 'DROP DATABASE sonarqube'"

# infra docker-compose.yml 里删掉 sonarqube service 条目（单独的 git 提交）
```

**清理后**还要从 nginx 删 sonar 反代配置（可选）：
```bash
ssh dev-cypresso "sudo rm /etc/nginx/conf.d/sonar.cypresso.ai.conf"
ssh dev-cypresso "sudo nginx -t && sudo systemctl reload nginx"
```

---

## 6. 回滚方案

### 场景 A：mac-mini 上 SonarQube 出致命问题，需要切回 dev-cypresso

只要做一件事：把 `sonar.host.url` 切回 `https://sonar.cypresso.ai`。dev-cypresso 上的 sonarqube 容器没动过，立刻可用。

回滚窗口期内 mac-mini 上累积的扫描数据会丢失（业务上可接受，重新扫描即可）。

### 场景 B：mac-mini 上 PG17 数据出问题，需要重导入

dev-cypresso 上的 `shared-postgres` 里 sonarqube 库**未动过**（仅 pg_dump 只读操作）。可直接：
```bash
# 重新导出
ssh dev-cypresso "sudo docker exec shared-postgres pg_dump -U sonarqube -d sonarqube --no-owner --no-privileges --quote-all-identifiers --format=plain > /tmp/sonarqube.sql"
```
然后从 `~/stacks/sonarqube/migration/sonarqube.sql.orig` 之类的现场资料重做导入。

### 场景 C：迁移期间发现 CSS / 插件不对，需要重置 mac-mini 上 SonarQube

```bash
ssh mac-mini "cd ~/stacks/sonarqube && docker compose down && docker volume rm sonarqube_data sonarqube_extensions sonarqube_logs sonarqube_temp sonar_pg_data"
# 重做 Unit 4 - Unit 5（重新导入 SQL + 解压 plugins + 启 sonarqube）
```

---

## 7. CSS 修复保留情况

### 业主在 dev-cypresso 上修复的 Bug
SonarQube 26.3.0 社区版有个 CSS grid utility 类缺失的 Bug，业主**在两个位置都放了修补**：

1. **bind mount**：`/home/ec2-user/stacks/infra/sonarqube-web/css/main-9woGo04Q.css`（容器内 `/opt/sonarqube/web/css/main-9woGo04Q.css` 被 bind mount 覆盖）
2. **nginx alias**：`/usr/share/nginx/sonar-fix/main-9woGo04Q.css` 通过 `location /css/main-9woGo04Q.css { alias ...; }` 替换 SonarQube 返回的文件

两份文件 sha256 完全一致：`e65a1efaa55cdd80b93659de4ccad4e7b993e1ad31eac993ce7fc6b3064cd31c`，所以**只要一份生效就行**。

### 在 mac-mini 上的保留方式
- bind mount 整目录 rsync 过来了（622 个文件，包括 CSS、WEB-INF/web.xml、字体、图标），sha256 抽样验证一致
- **不需要** nginx 那层（mac-mini 上没 nginx 反代）
- 修补 CSS 内容：
  ```css
  /* Fix SonarQube v26.3.0 missing CSS grid utility classes */
  .sw-col-span-10 { grid-column: span 10 / span 10 !important; }
  .sw-col-start-2 { grid-column-start: 2 !important; }
  ```
- **业主版的实质形态**：不是几行 patch，而是把 SonarQube 前端整体重新 build 了一遍。`index.html` 指向新的 `js/main-BHI4wvfe.js` + `css/main-9woGo04Q.css`（含 fix），vendor 原版的 main JS / CSS 仍在文件系统但 index.html 不再引用它们

### 2026-05-13 已沉淀到 git

`~/stacks/sonarqube/sonarqube-web/` 现在是 GitHub 仓库 [`cypressoai/sonarqube-web-patches`](https://github.com/cypressoai/sonarqube-web-patches)（private）的 working copy。

| 分支 | 内容 | 文件数 | 用途 |
|---|---|---|---|
| `main` ⭐（默认） | 业主 fork（生产实际跑的版本，含 CSS fix） | 622 + README + patches + .gitattributes | mac-mini 上 bind mount 的副本 |
| `vendor-26.3.0` | SonarQube 26.3.0.120487-community 官方镜像里的 web 原版 | 370 | 对照基线 / 紧急回退 |

### 未来再修 CSS 时怎么做

```bash
# 在 mac-mini 上（已配好 git remote 和 upstream）
cd ~/stacks/sonarqube/sonarqube-web
# 改 css/*.css 或其它文件
git status
git add <files>
git commit -m 'fix: <描述>'
git push

# 让 sonarqube 重新加载
cd ~/stacks/sonarqube
docker compose restart sonarqube
```

### 升级 SonarQube 到新版本时

1. 从新版镜像提取 vendor：
   ```bash
   mkdir vendor-26.X && cd vendor-26.X
   docker run --rm --entrypoint sh sonarqube:26.X.X-community \
     -c 'cd /opt/sonarqube/web && tar -cf - .' | tar -xf -
   chmod -R u+rwX .
   ```
2. 在仓库里建 `vendor-26.X.X` 分支提交这份原版
3. `git diff vendor-26.3.0 vendor-26.X.X -- web/css/main-*.css | grep sw-col-span-10`——看新版是否已修
4. 如果已修 → main 重置到新 vendor 之上重新打 fork
5. 如果未修 → 把 fix 移植到新版 main.css 重新提交

---

## 8. 数据对账 SQL（业主想自查时用）

任意时候可以从两边各查一次对照：

```bash
# mac-mini 端
ssh mac-mini "docker exec sonar-postgres psql -U sonarqube -d sonarqube -c \"
SELECT 'users' as table_, count(*) FROM users
UNION ALL SELECT 'projects', count(*) FROM components WHERE qualifier='TRK'
UNION ALL SELECT 'rules', count(*) FROM rules
UNION ALL SELECT 'issues', count(*) FROM issues
UNION ALL SELECT 'components', count(*) FROM components
ORDER BY table_;
\""

# dev-cypresso 端（同样 SQL）
ssh dev-cypresso "sudo docker exec shared-postgres psql -U sonarqube -d sonarqube -c \"
SELECT 'users' as table_, count(*) FROM users
UNION ALL SELECT 'projects', count(*) FROM components WHERE qualifier='TRK'
UNION ALL SELECT 'rules', count(*) FROM rules
UNION ALL SELECT 'issues', count(*) FROM issues
UNION ALL SELECT 'components', count(*) FROM components
ORDER BY table_;
\""
```

### 2026-05-13 凌晨迁移完成时的对账结果（基线）
| 表 | dev-cypresso (PG18) | mac-mini (PG17) |
|---|---|---|
| users | 5 | 5 |
| projects | 13 | 13 |
| rules | 13174 | 13174 |
| issues | 25510 | 25510 |
| components | 18756 | 18756 |

---

## 9. 日常运维

### 启停
```bash
ssh mac-mini "cd ~/stacks/sonarqube && docker compose start"
ssh mac-mini "cd ~/stacks/sonarqube && docker compose stop"
ssh mac-mini "cd ~/stacks/sonarqube && docker compose restart sonarqube"
```

### 日志
```bash
ssh mac-mini "docker logs --tail 100 sonarqube"
ssh mac-mini "docker exec sonarqube tail -f /opt/sonarqube/logs/web.log"
ssh mac-mini "docker exec sonarqube tail -f /opt/sonarqube/logs/ce.log"
```

### 备份（✅ 2026-05-13 已配好每日 cron）

- **脚本**：`~/stacks/sonarqube/backup.sh`
- **目录**：`~/backups/sonarqube/sonarqube-YYYYMMDD.dump`
- **格式**：PostgreSQL custom + zlib 9（~102 MB / 份）
- **调度**：crontab `30 3 * * *`，每天 03:30 本地时间
- **日志**：`~/Library/Logs/sonarqube-backup.log`
- **保留**：滚动 7 份，超出自动按 mtime 倒序删除
- **恢复演练**：已用临时 PG 17 容器跑通，restore 用时 3.7 秒，对账数字一致

手动恢复方式：

```bash
# 找一份要恢复的 dump
ls ~/backups/sonarqube/

# 恢复到 sonar-postgres（注意：这会清空当前 DB！）
docker compose stop sonarqube
docker exec -i sonar-postgres pg_restore -U sonarqube -d sonarqube \
  --clean --if-exists --no-owner --no-privileges \
  < ~/backups/sonarqube/sonarqube-YYYYMMDD.dump
docker compose start sonarqube
```

### 升级 SonarQube

详见专用 runbook：`docs/runbooks/sonarqube-upgrade.md`。

简短版：升级涉及 **5 个组件 + 4 个版本约束**（SQ / PG / community-branch-plugin / web fork / scanner client），不是改一行 image tag 那么简单。每次升级前完整读 runbook §0 的约束章节。

特别注意：**community-branch-plugin 必须严格匹配 SonarQube 主版本，且通常滞后 SonarQube 1–4 周发布**。盲目升 SQ 而 plugin 没跟上，会让分支 / PR 扫描功能瞬间失效。

---

## 10. 系统加固清单（前置依赖）

迁移前对 mac-mini 做了两个修复，详见 §11 文件清单：

1. **`~/.zshenv` 追加 `path_helper` 调用**：让 `ssh mac-mini "cmd"` 这种非交互非登录 shell 能拿到 `/usr/local/bin`，否则连 `docker` 命令都找不到
2. **`~/.zshrc` 顶部加 `[[ ! -o interactive ]] && return` 守卫**：让非交互 shell 跳过 oh-my-zsh + p10k + gitstatus 加载，消除 `setopt monitor` 失败的红色 ERROR

这两个改动让"通过 SSH 远程管理 mac-mini"变得无障碍，是后续 SonarQube 迁移自动化执行的前提。

### gitstatus 报错根因记录（与 git 版本无关）
- 报错字面：`(anon):setopt:7: can't change option: monitor` + `gitstatus failed to initialize`
- 实际原因：p10k → gitstatus 启动需要 `setopt monitor`（job control），但 zsh **在非交互非 job-control shell 默认禁止**该选项
- 解决：让非交互 shell 跳过加载 p10k（参见上面第 2 条）
- git 版本 `2.50.1 (Apple Git-155)` 没有问题，**不需要升级 git**

---

## 11. 改动文件清单（本次迁移修改的文件 / 创建的资源）

### mac-mini 上
| 路径 | 类型 | 用途 | 备份 |
|---|---|---|---|
| `~/.zshenv` | 修改 | 加 path_helper 调用 | `~/.zshenv.bak.20260513` |
| `~/.zshrc` | 修改 | 加非交互 shell early return | `~/.zshrc.bak.20260513` |
| `~/stacks/sonarqube/` | 新建 | SonarQube 整个 stack 目录 | — |
| `~/stacks/sonarqube/docker-compose.yml` | 新建 | compose 定义 | — |
| `~/stacks/sonarqube/.env` | 新建 | DB 凭证（chmod 600） | — |
| `~/stacks/sonarqube/sonarqube-web/` | rsync 自 dev-cypresso | 622 个 web 静态资源 | — |
| `~/stacks/sonarqube/migration/` | 新建 | 迁移临时数据（7 天后可清） | — |
| docker volumes | 新建 | `sonar_pg_data`、`sonarqube_data`、`sonarqube_extensions`、`sonarqube_logs`、`sonarqube_temp` | — |
| docker network | 新建 | `sonar-net` | — |

### dev-cypresso 上
**本次没有修改任何 dev-cypresso 上的文件**。所有内容都只读访问。

待业主明早执行的 dev-cypresso 端动作（见 §5）：
- `docker compose stop sonarqube`（保留 volumes）
- 7 天后清理 volumes + nginx 配置 + shared-postgres 里的 sonarqube 库

### 本仓库（Server）
| 路径 | 类型 |
|---|---|
| `docs/plans/2026-05-13-001-refactor-sonarqube-migrate-to-mac-mini-plan.md` | 新建 — 完整迁移计划 |
| `docs/solutions/mac-mini/sonarqube-migrated-from-dev-cypresso-2026-05-13.md` | 新建 — 本文 |

---

## 12. 已知遗留 / TODO

- [x] **业主**：浏览器登录 `http://mac-mini:9000` 完成 §3 验证清单（2026-05-13 早晨完成，三个地址 `http://mac-mini:9000/projects`、`http://mac-mini.taila93443.ts.net:9000`、`http://100.108.64.126:9000` 全部可登陆、内页无异常）
- [x] **业主**：执行 §5 停 dev-cypresso 上 sonarqube（2026-05-13 早晨完成，详见下方实际记录）
- [x] **业主**：按 §4 切换 CI 的 `sonar.host.url`（2026-05-13 已完成，7 个仓库的 `SONAR_HOST_URL` secret 全部改成 `http://mac-mini:9000`，端到端验证用 iCare-backend 跑了一次扫描成功落到新 SonarQube）
- [ ] **业主 / 团队成员**：本地 IDE（SonarLint / IntelliJ / VS Code 插件）的 SonarQube Server URL 自查切到 `http://mac-mini:9000`
- [ ] **业主**：可选 — 关闭 dev-cypresso 上的 sonar.cypresso.ai nginx 反代（避免 502 噪音；不做也无害）
- [ ] **业主**：24 小时后看 CloudWatch CPUUtilization 是否下降（验证 SonarQube 占用真的释放）
- [ ] **业主**：一周后清理 dev-cypresso 上的 volumes、nginx 配置、shared-postgres 上的 sonarqube 库
- [x] ~~**建议**：把 `~/stacks/sonarqube/sonarqube-web/` 中相对 SonarQube 原版的 diff 沉淀到本仓库 / git 仓库~~ → **2026-05-13 已完成**，沉淀到 https://github.com/cypressoai/sonarqube-web-patches（private repo，main + vendor-26.3.0 双分支）
- [x] ~~**建议**：加每日 pg_dump 备份 cron~~ → **2026-05-13 已完成**，详见 §9 备份章节
- [ ] **建议**：cypresso-api / cypresso-doc / cypresso-ui / Telegram-bot 这 4 个项目在 SonarQube 上有项目记录但 GitHub repo 上没接 CI sonar workflow——业主决定是补上 sonar.yml 还是从 SQ 中删掉过时项目

### 2026-05-13 早晨实际停服记录

| 指标 | 停止前 | 停止后 |
|---|---|---|
| sonarqube 容器 | `Up 9 hours` | `Exited (130) Less than a second ago` |
| 内存 used | 4.9 GiB | **3.1 GiB**（释放 1.8 GiB） |
| 内存 available | 9.4 GiB | **11 GiB** |
| Volumes（sonarqube_data / extensions / logs / temp） | 在 | **全部保留**，可回滚 |
| 其它 12 个容器 | Up | 全部 Up（零影响） |

Exit code 130 是 SonarQube 收到 SIGINT 后的正常退出码。

---

## 13. 关键命令快查

```bash
# 状态检查（一行知道好不好）
curl -sS http://mac-mini:9000/api/system/status

# 容器状态
ssh mac-mini "cd ~/stacks/sonarqube && docker compose ps"

# 日志（实时）
ssh mac-mini "cd ~/stacks/sonarqube && docker compose logs -f --tail 50"

# 重启
ssh mac-mini "cd ~/stacks/sonarqube && docker compose restart"

# 进 PG
ssh mac-mini "docker exec -it sonar-postgres psql -U sonarqube -d sonarqube"

# 进 sonarqube 容器
ssh mac-mini "docker exec -it sonarqube bash"
```

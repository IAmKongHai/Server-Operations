---
title: SonarQube 升级 runbook（mac-mini 上的 cypressoai SQ 实例）
last_updated: 2026-09-09
applies_to: mac-mini ~/stacks/sonarqube/，sonarqube:26.5.0.122743-community + community-branch-plugin 26.5.0
---

# SonarQube 升级 runbook

> **入口文档**。每次升级 SonarQube 前完整读一遍，按顺序操作。本 runbook 假设你已经熟悉 `docs/solutions/mac-mini/sonarqube-migrated-from-dev-cypresso-2026-05-13.md` 描述的当前架构。

## 0. 升级前必须搞清楚的 4 个约束

升级 SonarQube 不是改一行 image tag 那么简单。涉及 **5 个组件 + 4 个版本约束**：

```
┌──────────────────────────┐
│ 1. SonarQube 镜像版本     │ ← 受 PG 版本支持矩阵约束
└──────────────────────────┘
              ↓
┌──────────────────────────┐
│ 2. PostgreSQL 版本        │ ← 必须在新 SQ 版本支持范围内
└──────────────────────────┘
              ↓
┌──────────────────────────┐
│ 3. community-branch-plugin │ ← 必须严格匹配 SQ 主版本（X.Y）
└──────────────────────────┘
              ↓
┌──────────────────────────┐
│ 4. sonarqube-web fork    │ ← 新版本可能修复了 CSS Bug
└──────────────────────────┘
              ↓
┌──────────────────────────┐
│ 5. scanner 客户端        │ ← 一般兼容性好，偶有 breaking
└──────────────────────────┘
```

### 约束 ①：community-branch-plugin **必须先于**或同时支持目标 SQ 版本

[mc1arke/sonarqube-community-branch-plugin](https://github.com/mc1arke/sonarqube-community-branch-plugin) 通常滞后官方 SQ 发布 1–4 周。**没有匹配 plugin 的 SQ 版本绝对不要升**，否则分支 / PR 扫描功能会瞬间失效（你的 iCare-backend、frontend-mas 等都用了分支扫描）。

**检查方法**：

```bash
# 看官方最新版
curl -s 'https://hub.docker.com/v2/repositories/library/sonarqube/tags?page_size=10&name=community' \
  | jq -r '.results[].name' | head -5

# 看 plugin 最新 release
curl -s 'https://api.github.com/repos/mc1arke/sonarqube-community-branch-plugin/releases?per_page=5' \
  | jq -r '.[] | "\(.tag_name)  \(.published_at)  pre=\(.prerelease)"'
```

**目标版本选择规则**：找两者主版本号（major.minor）匹配的最高组合。2026-09-09 起当前在跑、也是 plugin 能跟上的最高对：

| SQ 版本 | plugin 26.3.0 | plugin 26.5.0 |
|---|---|---|
| 26.3.0 | 旧（已迁走） | ❌ |
| 26.5.0 | ❌ | ✅（**当前在跑**） |
| 26.6–26.9 | ❌ | ❌（plugin 无对应 release） |

### 约束 ②：PostgreSQL 版本必须在 SQ 支持矩阵内

SQ 26.x 当前支持 **PostgreSQL 13–17**。mac-mini 跑的是 PG 17，**26.x 区间内升 SQ 不需要动 PG**。

但**未来某天 SQ 27.x / 28.x 可能要求 PG 18+** 或不再支持 PG 13/14。看官方文档：

```
https://docs.sonarsource.com/sonarqube-server/latest/setup-and-upgrade/install-the-server/prerequisites/
```

如果跨大版本（26 → 27）必须先做 PG dump/restore（参考 2026-05-13 从 dev-cypresso 迁移时的 PG18→PG17 过程，runbook 在 `docs/solutions/mac-mini/sonarqube-migrated-from-dev-cypresso-2026-05-13.md` §6 场景 B）。

### 约束 ③：跨大版本升级必须经过中间版本（LTS chain）

SQ 不允许从 24.x 直接跳到 26.x。如果你长时间不升级，必须按 LTS 链路：
- 25.1 LTA → 26.1（下一个 LTA）→ 26.5 → ...
- 每个中间停留版本都要等 ES 索引重建 + DB schema 升级完成才能继续

当前在 26.5，可直接升任意更高的 26.x（仍须匹配 plugin）。如果未来跑到 27.x，需要经过官方标明的 LTA 链路。

### 约束 ④：sonarqube-web fork 与新版本兼容性

业主在 `cypressoai/sonarqube-web-patches` 仓库维护了 SonarQube 26.3.0 的前端 fork（修复 CSS grid utility classes 缺失）。**新 SQ 版本的 web 资源结构可能完全不同**：

- 新 hash 文件名（不可避免，Vite build 每次都换）
- 新 main JS / CSS 入口
- 可能官方已经修了那个 CSS bug → fork 不再需要

升级流程的 §3 详细讲怎么决定"还要不要 fork"。

---

### 约束 ⑤：如果升级**同时换 host**（不只升版本），OAuth 回调链必须同步

升级一般不换 host，但如果你借升级窗口顺便换 host（迁机房 / 改域名 / 加 https），必须同步两端的 host 字符串：

- SonarQube `sonar.core.serverBaseURL`（Administration → General → Server base URL）
- GitHub App / OAuth App 的 Authorization callback URL 白名单
- 反代层（如果有）的 Host header

参考：[`docs/solutions/mac-mini/integration-issues/sonarqube-github-oauth-callback-after-migration-2026-05-13.md`](../solutions/mac-mini/integration-issues/sonarqube-github-oauth-callback-after-migration-2026-05-13.md)

---

## 1. 升级前检查清单（5 分钟）

在开始升级前完成这些只读检查：

```bash
# 1.1 当前版本
curl -sS http://mac-mini:9000/api/server/version
ssh mac-mini "docker exec sonar-postgres postgres --version"

# 1.2 备份：先停 sonarqube（postgres 保持运行），再 pg_dump -Fc（不要 plain SQL，不要分配 TTY）
# dump 放到 backup.sh 的 `sonarqube-*.dump` prune glob 之外，例如子目录
ssh mac-mini "docker-compose -f ~/stacks/sonarqube/docker-compose.yml stop -t 180 sonarqube && \
  mkdir -m 700 -p ~/backups/sonarqube/upgrade-kit && \
  docker exec sonar-postgres pg_dump -U sonarqube -d sonarqube \
    --no-owner --no-privileges --format=custom --compress=9 \
  > ~/backups/sonarqube/upgrade-kit/sonarqube.custom.dump && \
  chmod 600 ~/backups/sonarqube/upgrade-kit/sonarqube.custom.dump && \
  docker exec -i sonar-postgres pg_restore -l < ~/backups/sonarqube/upgrade-kit/sonarqube.custom.dump | head"

# 1.3 当前 sonarqube-web 仓库状态（必须 clean，否则本地修改会丢）
ssh mac-mini "cd ~/stacks/sonarqube/sonarqube-web && \
  git status --short && git log --oneline -3"

# 1.4 现有项目数（升级后用来对账）
ssh mac-mini "docker exec sonar-postgres psql -U sonarqube -d sonarqube -c \"
  SELECT 'users' AS t, count(*) FROM users
  UNION ALL SELECT 'projects', count(*) FROM components WHERE qualifier='TRK'
  UNION ALL SELECT 'rules', count(*) FROM rules
  UNION ALL SELECT 'issues', count(*) FROM issues
  ORDER BY t;\""

# 1.5 通知团队：扫描会在升级窗口期内（10–30 分钟）失败
```

---

## 2. 升级执行（典型耗时 15–30 分钟）

### 2.1 选定目标版本组合

按约束 ① 决策表选目标 SQ 版本 + plugin 版本。当前在跑是 `26.5.0.122743` + plugin `26.5.0`。下一跳必须等匹配 plugin。mac-mini 上 Compose CLI 是 `docker-compose`，不是 `docker compose`。

### 2.2 下载新 plugin jar **和** `sonarqube-webapp.zip`

```bash
ssh mac-mini "
TARGET_PLUGIN_VERSION=26.5.0
KIT=~/backups/sonarqube/upgrade-kit
mkdir -m 700 -p \"\$KIT\"
curl -fL -o \"\$KIT/sonarqube-community-branch-plugin-\${TARGET_PLUGIN_VERSION}.jar\" \
  https://github.com/mc1arke/sonarqube-community-branch-plugin/releases/download/\${TARGET_PLUGIN_VERSION}/sonarqube-community-branch-plugin-\${TARGET_PLUGIN_VERSION}.jar
curl -fL -o \"\$KIT/sonarqube-webapp.zip\" \
  https://github.com/mc1arke/sonarqube-community-branch-plugin/releases/download/\${TARGET_PLUGIN_VERSION}/sonarqube-webapp.zip
ls -lh \"\$KIT\"
"
```

### 2.3 用 plugin 的 `sonarqube-webapp.zip` **替换** web 树（keep `.git`）

不要 `git checkout vendor-*`，也不要把 zip 解在 旧 hashed 文件上面。web 目录常是 `dr-xr-x---`，先 `chmod u+w`。

```bash
ssh mac-mini "
WEB=~/stacks/sonarqube/sonarqube-web
KIT=~/backups/sonarqube/upgrade-kit
git -C \"\$WEB\" status --short --untracked-files=all   # 必须干净
git -C \"\$WEB\" rev-parse HEAD                         # 记进 kit，供回滚
find \"\$WEB\" -path \"\$WEB/.git\" -prune -o -type d -exec chmod u+w {} +
find \"\$WEB\" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
unzip -q \"\$KIT/sonarqube-webapp.zip\" -d \"\$WEB\"
# 确认 index.html 不再引用旧 hashed main-*.js
"
```

登录页 grid 若坏了，最多在**新** `css/main-*.css` 末尾追加两条 grid utility；不要还原 26.3 hashed 资源。完整 fork 决策树仍见 §3。

### 2.4 改 compose 配置

```bash
ssh mac-mini "
cd ~/stacks/sonarqube
cp docker-compose.yml docker-compose.yml.bak.\$(date +%Y%m%d)

# 只改 image tag 和已有 SONAR_WEB_JAVAOPTS / SONAR_CE_JAVAOPTS 里的 jar 文件名
sed -i '' 's|sonarqube:26.3.0.120487-community|sonarqube:26.5.0.122743-community|' docker-compose.yml
sed -i '' 's|sonarqube-community-branch-plugin-26.3.0.jar|sonarqube-community-branch-plugin-26.5.0.jar|g' docker-compose.yml
# 26.5 镜像没有 wget，healthcheck 用 curl，要求 status=UP
# 升级窗口内若要过 /setup，需临时接受 DB_MIGRATION_*，UP 后再改回 UP-only

# 验证
grep -E 'image:|community-branch-plugin' docker-compose.yml
"
```

### 2.5 把新 plugin jar 放进 extensions volume

```bash
ssh mac-mini "
# kit 目录 700 时 alpine 挂不上，用 docker cp
docker cp ~/backups/sonarqube/upgrade-kit/sonarqube-community-branch-plugin-26.5.0.jar \
  sonarqube:/opt/sonarqube/extensions/plugins/sonarqube-community-branch-plugin-26.5.0.jar
docker run --rm -v sonarqube_extensions:/dest alpine sh -c '
  chown 1000:0 /dest/plugins/sonarqube-community-branch-plugin-26.5.0.jar
  rm -f /dest/plugins/sonarqube-community-branch-plugin-26.3.0.jar
  ls -la /dest/plugins/
'
# 不要先 rm glob；不要把 jar 放到 sonarqube-web bind-mount
"
```

### 2.6 拉新镜像 + 只重启 sonarqube

```bash
ssh mac-mini "
cd ~/stacks/sonarqube
docker-compose pull sonarqube
docker-compose up -d --no-deps sonarqube
# 禁止 docker-compose down / down -v / volume prune
"
```

### 2.7 等 DB schema 升级 + ES 重建

新版 SQ 启动时会自动跑 DB migration（如果有 schema 变化）和 ES 重建。**首次启动可能很慢（5–30 分钟）**。监控：

```bash
# API 状态
curl -sS http://mac-mini:9000/api/system/status
# 期望从 DB_MIGRATION_NEEDED → DB_MIGRATION_RUNNING → UP

# 如果状态是 DB_MIGRATION_NEEDED，触发迁移
curl -sS -X POST http://mac-mini:9000/api/system/migrate_db
```

---

## 3. sonarqube-web fork 升级决策树

```
新 SQ 版本启动后用 vendor（不挂 bind mount）测试一次
  │
  ├─ 是否还有原来的 CSS Bug（登录页布局错位）？
  │
  ├─ 否（官方修了）→ ✅ 不再需要 fork
  │   ├─ 1. cypressoai/sonarqube-web-patches 仓库归档（或保留作历史）
  │   ├─ 2. mac-mini compose 删除 sonarqube-web bind mount
  │   └─ 3. 删 ~/stacks/sonarqube/sonarqube-web 目录
  │
  └─ 是（官方没修）→ ❌ 仍需 fork，按 §3.1 移植
```

### 3.1 提取新 vendor 并比对

```bash
ssh mac-mini "
TARGET_SQ_TAG=26.4.0.121862-community
mkdir -p ~/tmp-sonar-vendor-new && cd ~/tmp-sonar-vendor-new
docker run --rm --entrypoint sh sonarqube:\${TARGET_SQ_TAG} \
  -c 'cd /opt/sonarqube/web && tar -cf - .' | tar -xf -
chmod -R u+rwX .
find . -type f | wc -l
"
```

### 3.2 在 sonarqube-web-patches 仓库建新 vendor 分支

```bash
ssh mac-mini "
TARGET_SQ_VERSION=26.4.0  # 仅用 major.minor.patch（不带 build id 和 -community）
cd ~/stacks/sonarqube/sonarqube-web

# 先确保 working tree 干净
git status

# 用 vendor-26.3.0 作为模板建新 vendor 分支
git checkout vendor-26.3.0
git checkout --orphan vendor-\${TARGET_SQ_VERSION}
git rm -rf --quiet .

# 拷新版 vendor 文件进来
cp -R ~/tmp-sonar-vendor-new/. .
chmod -R u+rwX .

# 写 vendor README（参考 vendor-26.3.0 分支 README 改 image tag）
# ...

git add -A
git -c commit.gpgsign=false commit -m \"chore: import SonarQube \${TARGET_SQ_VERSION} web/ as vendor baseline\"
git push -u origin vendor-\${TARGET_SQ_VERSION}
"
```

### 3.3 检查官方是否修了 CSS Bug

```bash
ssh mac-mini "
cd ~/stacks/sonarqube/sonarqube-web
git fetch --all --quiet

# 看新 vendor 的 main CSS 是否包含 fix 的两个 class
git show vendor-26.4.0:css/main-*.css 2>/dev/null | grep -E 'sw-col-span-10|sw-col-start-2' && echo '✅ 官方已修' || echo '❌ 仍需 fork'

# 或者跨分支 diff
git diff vendor-26.3.0..vendor-26.4.0 -- css/ | head -50
"
```

### 3.4 移植 fork 到新版（如果仍需 fork）

业主原始 fork 是整套 rebuild，**不能直接 cherry-pick**——新版 hash 文件名完全不同。两种策略：

**策略 A（推荐，简单）**：只把缺失的 CSS rules 注入到新版的 main CSS。
```bash
# 找到新版 main CSS 文件名
NEW_MAIN_CSS=$(ls css/main-*.css | head -1)

# 把 fix 追加到末尾
cat >> "$NEW_MAIN_CSS" <<'CSSEOF'

/* fork: SonarQube 26.X.X CSS grid utility classes fix
 * 参考 patches/01-css-grid-utility-classes.css */
.sw-col-span-10 { grid-column: span 10 / span 10 !important; }
.sw-col-start-2 { grid-column-start: 2 !important; }
CSSEOF

# 提交
git checkout main
# 切到 main，先重置到新 vendor
git reset --hard vendor-26.4.0
# 再应用上面的 CSS 修改
# 提交
```

**策略 B（复杂，仅 CSS fix 不够时）**：完整重新 build SonarQube 前端。这超出 runbook 范围，需要 fork SonarQube 前端源码、修 Tailwind 配置、跑 vite build。

---

## 4. 升级后验证（必做）

```bash
# 4.1 版本验证
curl -sS http://mac-mini:9000/api/server/version
# 期望：新版本号

# 4.2 plugin 加载验证
ssh mac-mini "docker logs sonarqube 2>&1 | grep -i 'Community Branch'"
# 期望：Deploy Community Branch Plugin / 26.5.0 / null

# 4.3 数据完整性（对照升级前 §1.4 的数字）
ssh mac-mini "docker exec sonar-postgres psql -U sonarqube -d sonarqube -c \"
  SELECT 'users' AS t, count(*) FROM users
  UNION ALL SELECT 'projects', count(*) FROM components WHERE qualifier='TRK'
  UNION ALL SELECT 'rules', count(*) FROM rules
  UNION ALL SELECT 'issues', count(*) FROM issues
  ORDER BY t;\""
# 期望：users/projects/issues 不变；rules 数量可能增加（新版自带新规则，正常）

# 4.4 UI 验证（开浏览器）
# - 登录页样式（验证 CSS Bug 状态）
# - 任一项目历史 Issue 完整
# - Quality Profile 4 个仍在（Cypresso CSS/Go/Python/typescript Way）
# - Administration → Marketplace 看 Community Branch Plugin 已安装且版本正确

# 4.5 验证 GitHub required check 名「SonarQube Scan」变绿（不是整次 mixed run）
# 例：iCare-backend 上 job / check 名必须是 SonarQube Scan
# Quality-gate 超时或 ES 重建导致的红：重跑该 job，不要当回滚条件
# Issues facets=authors 的 HTTP 400、banner「version no longer active」是已知噪声
```

---

## 5. 回滚

如果升级后任何步骤失败，回滚到升级前状态。**不要** `docker-compose down` / `down -v` / `volume prune`。postgres 全程保持运行。

`/setup` 之前（schema 未迁）：只从 kit 恢复 compose、jar、javaagent 文件名、web `git reset --hard`，再 `docker-compose up -d --no-deps sonarqube`。不要 DROP DATABASE，不要擦 `es8`。

`/setup` 之后（schema 已迁）必须 drop/create + restore + 擦 ES，一次确认做完：

```bash
ssh mac-mini "
cd ~/stacks/sonarqube
KIT=~/backups/sonarqube/upgrade-26.3-to-26.5
docker-compose stop -t 180 sonarqube

# 必须连到数据库 postgres（不能连着 sonarqube 库 DROP 自己）。
# 本实例 POSTGRES_USER=sonarqube，它就是超级用户，没有独立的 postgres 角色。
docker exec -i sonar-postgres psql -U sonarqube -d postgres -v ON_ERROR_STOP=1 <<'SQL'
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'sonarqube' AND pid <> pg_backend_pid();
DROP DATABASE sonarqube;
CREATE DATABASE sonarqube OWNER sonarqube;
SQL

# 灌进空库。禁止 --clean / --create，禁止 psql < plain.sql
docker exec -i sonar-postgres pg_restore -U sonarqube -d sonarqube \
  --no-owner --no-privileges --exit-on-error \
  < \"\$KIT/sonarqube-26.3.custom.dump\"

# 擦 data volume 里的 data/es8，不要 docker volume rm
docker run --rm -v sonarqube_data:/data alpine rm -rf /data/es8

cp \"\$KIT/docker-compose.yml.bak\" docker-compose.yml
docker cp \"\$KIT/sonarqube-community-branch-plugin-26.3.0.jar\" \
  sonarqube:/opt/sonarqube/extensions/plugins/sonarqube-community-branch-plugin-26.3.0.jar
docker run --rm -v sonarqube_extensions:/dest alpine sh -c '
  rm -f /dest/plugins/sonarqube-community-branch-plugin-26.5.0.jar
  chown 1000:0 /dest/plugins/sonarqube-community-branch-plugin-26.3.0.jar
'
git -C sonarqube-web reset --hard 4581dd19ea8e1946dc0748e10ed11f6205c4f291
git -C sonarqube-web clean -fd

docker-compose up -d --no-deps sonarqube
"
```

**重要**：schema 迁过之后只改镜像不够。`--clean` restore 打到已迁移 catalog 会留下 26.5 对象。26.5 可能抬高嵌入 ES，旧二进制会拒收新的 `es8`，所以 restore 和擦 `es8` 是同一次确认。

---

## 6. 常见问题

### Q: SonarQube 启动后日志反复报 `plugin xxx is not compatible with SonarQube X.Y`

A: 你装的 community-branch-plugin 主版本号和 SQ 不匹配（约束 ①）。换成精确匹配的 plugin 版本。

### Q: 升级后所有项目都不见了

A: 几乎不可能——数据在 PG 里。如果真的发生，先验证 PG 健康（`docker logs sonar-postgres`）、SonarQube 是否连对了 PG（`/api/system/info`）。

### Q: 升级后 CI 触发的扫描全部 401 Unauthorized

A: 不太可能。Token 在 DB 里，SQ 升级一般不让 token 失效。检查是不是有人误改了 SONAR_TOKEN secret 或者 token 被撤销。

### Q: 新版 SonarQube 启动很慢（>30 分钟）

A: 大概率是 ES 索引重建。`docker exec sonarqube tail -f /opt/sonarqube/logs/es.log`。302MB 库在 M4 mini 上**最多 15 分钟**够了。如果超过 30 分钟没动静，可能是 DB migration 卡住（看 `web.log`）。

### Q: 升级到大版本后，一些社区版功能不见了

A: SonarSource 偶尔会把功能从社区版移到付费版。看官方 release notes。如果是关键功能，回退到前一个版本，或者评估付费。

### Q: 26.5 起来后 healthcheck 一直失败 / `wget: not found`

A: `sonarqube:26.5.0.122743-community` 镜像里没有 `wget`，有 `curl`。healthcheck 改成 `curl -fsS http://127.0.0.1:9000/api/system/status | grep -q '"status":"UP"'`。`/setup` 期间要临时接受 `DB_MIGRATION_*`，否则 `unless-stopped` 虽不会因 unhealthy 自杀，但监控会一直 starting/unhealthy。

---

## 7. 维护历史

| 日期 | 操作 | SQ 版本 | plugin 版本 | PG 版本 | 操作人 |
|---|---|---|---|---|---|
| 2026-09-09 | 原地 26.3→26.5；kit `~/backups/sonarqube/upgrade-26.3-to-26.5/`；healthcheck 改为 curl | 26.5.0.122743 | 26.5.0 | 17.11 | Grok |
| 2026-05-13 | 从 dev-cypresso 迁移到 mac-mini | 26.3.0.120487 | 26.3.0 | 17.9 | k-cypresso |

未来每次升级在这里追加一行。当前服务版本以本表最新一行为准。

---

## 8. 关联文档

- 当前 SonarQube 架构：`docs/solutions/mac-mini/sonarqube-migrated-from-dev-cypresso-2026-05-13.md`
- web fork 仓库：https://github.com/cypressoai/sonarqube-web-patches
- 上一次 dev-cypresso 故障（引发本次迁移）：`docs/solutions/dev-cypresso/performance-issues/t3-cpu-credit-exhausted-instance-hang-2026-05-12.md`
- SonarQube 官方 docs：https://docs.sonarsource.com/sonarqube-server/latest/
- community-branch-plugin releases：https://github.com/mc1arke/sonarqube-community-branch-plugin/releases

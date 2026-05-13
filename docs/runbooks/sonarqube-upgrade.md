---
title: SonarQube 升级 runbook（mac-mini 上的 cypressoai SQ 实例）
last_updated: 2026-05-13
applies_to: mac-mini ~/stacks/sonarqube/，sonarqube:26.X-community + community-branch-plugin
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

**目标版本选择规则**：找两者主版本号（major.minor）匹配的最高组合。例如：

| SQ 版本 | plugin 26.3.0 | plugin 26.4.0 |
|---|---|---|
| 26.3.0 | ✅（当前在跑） | ❌ |
| 26.4.0 | ❌（plugin 较旧） | ✅（**可升的目标**） |
| 26.5.0 | ❌ | ❌（plugin 尚未发布 26.5） |

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

当前在 26.3，可直接升任意 26.x。如果未来跑到 27.x 出现，需要经过 26.X LTA（社区版的 LTA 标记看官方 release notes）。

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

# 1.2 备份：先 pg_dump 一份
ssh mac-mini "mkdir -p ~/backups/sonarqube && \
  docker exec sonar-postgres pg_dump -U sonarqube -d sonarqube \
    --no-owner --no-privileges --quote-all-identifiers --format=plain \
  > ~/backups/sonarqube/pre-upgrade-\$(date +%Y%m%d-%H%M).sql && \
  ls -lh ~/backups/sonarqube/"

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

按约束 ① 决策表选目标 SQ 版本 + plugin 版本。本节用 `26.3 → 26.4` 作为示例。

### 2.2 下载新 plugin jar

```bash
ssh mac-mini "
TARGET_PLUGIN_VERSION=26.4.0
cd /tmp
curl -fLO https://github.com/mc1arke/sonarqube-community-branch-plugin/releases/download/\${TARGET_PLUGIN_VERSION}/sonarqube-community-branch-plugin-\${TARGET_PLUGIN_VERSION}.jar
ls -lh sonarqube-community-branch-plugin-\${TARGET_PLUGIN_VERSION}.jar
"
```

### 2.3 处理 sonarqube-web fork

详见 §3。简单情况（新版官方已修 CSS Bug、不再需要 fork）：

```bash
ssh mac-mini "
cd ~/stacks/sonarqube/sonarqube-web
# 切到 vendor 分支（用官方原版）
git checkout vendor-26.4.0    # 假设你已经按 §3 创建好这个分支
"
```

需要继续 fork 的情况见 §3。

### 2.4 改 compose 配置

```bash
ssh mac-mini "
cd ~/stacks/sonarqube
cp docker-compose.yml docker-compose.yml.bak.\$(date +%Y%m%d)

# 改 image tag（用 sed 替换）
sed -i '' 's|sonarqube:26.3.0.120487-community|sonarqube:26.4.0.121862-community|' docker-compose.yml

# 改 JAVAOPTS 中的 plugin jar 文件名
sed -i '' 's|sonarqube-community-branch-plugin-26.3.0.jar|sonarqube-community-branch-plugin-26.4.0.jar|g' docker-compose.yml

# 验证
grep -E 'image:|community-branch-plugin' docker-compose.yml
"
```

### 2.5 把新 plugin jar 放进 extensions volume

```bash
ssh mac-mini "
TARGET_PLUGIN_VERSION=26.4.0
docker run --rm \
  -v sonarqube_extensions:/dest \
  -v /tmp:/src \
  alpine sh -c '
    # 删旧 jar，放新 jar
    rm -f /dest/plugins/sonarqube-community-branch-plugin-*.jar
    cp /src/sonarqube-community-branch-plugin-'\${TARGET_PLUGIN_VERSION}'.jar /dest/plugins/
    ls -la /dest/plugins/
  '
"
```

### 2.6 拉新镜像 + 重启

```bash
ssh mac-mini "
cd ~/stacks/sonarqube
docker compose pull sonarqube
docker compose up -d sonarqube
docker compose logs -f sonarqube
# 等到看到 'SonarQube is up'，Ctrl-C 退出 logs
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
# 期望：Deploy Community Branch Plugin / 26.4.0 / null

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

# 4.5 触发一次真实扫描验证 CI 链路
gh workflow run "SonarQube Analysis" --repo cypressoai/iCare-backend --ref develop
# 用 5 分钟监控
```

---

## 5. 回滚

如果升级后任何步骤失败，回滚到升级前状态：

```bash
ssh mac-mini "
cd ~/stacks/sonarqube

# 5.1 停服
docker compose down

# 5.2 恢复 compose 配置
cp docker-compose.yml.bak.YYYYMMDD docker-compose.yml

# 5.3 恢复 sonarqube-web 到升级前的 commit（如果换过分支）
cd sonarqube-web
git checkout main           # 或者 vendor-26.3.0
git reset --hard <升级前的 commit hash>

# 5.4 恢复 plugin（如果换过）
docker run --rm -v sonarqube_extensions:/dest alpine sh -c '
  rm -f /dest/plugins/sonarqube-community-branch-plugin-*.jar
'
# 然后重新放回旧版 jar（从 cypressoai/sonarqube-web-patches 仓库 release attachment 取，或者从备份 plugins.tar.gz 取）

# 5.5 恢复 DB（仅当新版跑过 schema migration 时需要）
docker exec -i sonar-postgres psql -U sonarqube -d sonarqube < ~/backups/sonarqube/pre-upgrade-YYYYMMDD-HHMM.sql

# 5.6 重启
cd ..
docker compose up -d
"
```

**重要**：跨大版本升级后**数据库 schema 已经变了**，回滚必须用升级前 pg_dump 全量还原，不能只回 compose。所以 §1.2 的备份步骤不能跳过。

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

---

## 7. 维护历史

| 日期 | 操作 | SQ 版本 | plugin 版本 | PG 版本 | 操作人 |
|---|---|---|---|---|---|
| 2026-05-13 | 从 dev-cypresso 迁移到 mac-mini | 26.3.0.120487 | 26.3.0 | 17.9 | k-cypresso |

未来每次升级在这里追加一行。

---

## 8. 关联文档

- 当前 SonarQube 架构：`docs/solutions/mac-mini/sonarqube-migrated-from-dev-cypresso-2026-05-13.md`
- web fork 仓库：https://github.com/cypressoai/sonarqube-web-patches
- 上一次 dev-cypresso 故障（引发本次迁移）：`docs/solutions/dev-cypresso/performance-issues/t3-cpu-credit-exhausted-instance-hang-2026-05-12.md`
- SonarQube 官方 docs：https://docs.sonarsource.com/sonarqube-server/latest/
- community-branch-plugin releases：https://github.com/mc1arke/sonarqube-community-branch-plugin/releases

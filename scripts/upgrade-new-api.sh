#!/usr/bin/env bash
# 一键升级 nyh-prod-2026 上的 new-api（tovo.sh）
#
# 用法:
#   ./scripts/upgrade-new-api.sh <target-tag|latest> [选项]
#
# 示例:
#   ./scripts/upgrade-new-api.sh latest --dry-run
#   ./scripts/upgrade-new-api.sh v1.0.0-rc.52 --dry-run
#   ./scripts/upgrade-new-api.sh v1.0.0-rc.52
#   ./scripts/upgrade-new-api.sh v1.0.0-rc.52 --yes

set -euo pipefail

SSH_HOST="nyh-prod-2026"
REMOTE_STACK_DIR="/opt/stacks/new-api"
REMOTE_BACKUP_DIR="/root/backups/new-api"
IMAGE_REPO="calciumion/new-api"
PG_BACKUP_IMAGE="postgres:18.6-alpine"
STATUS_URL="https://tovo.sh/api/status"
GITHUB_RELEASES_API="https://api.github.com/repos/QuantumNous/new-api/releases?per_page=15"
KEEP_BACKUPS=10

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/nyh-prod-2026/docker/new-api/compose.yaml"
README_FILE="$REPO_ROOT/nyh-prod-2026/README.md"

TARGET_INPUT=""
DRY_RUN=0
AUTO_YES=0
FORCE=0
SKIP_BACKUP=0

usage() {
  cat <<'EOF'
用法: scripts/upgrade-new-api.sh <target-tag|latest> [选项]

参数:
  <target-tag|latest>   目标版本号（如 v1.0.0-rc.52）或 latest（自动查 GitHub 最新 Release）

选项:
  --dry-run             仅做预检（Release Notes、文件一致性、在途任务），不修改任何文件或容器
  --yes, -y             跳过交互确认
  --force               忽略「在途异步任务 > 0」或「目标版本与当前版本相同」检查
  --skip-backup         跳过 RDS 数据库逻辑备份（不推荐）
  --help, -h            显示本帮助信息
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --yes|-y)
      AUTO_YES=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --skip-backup)
      SKIP_BACKUP=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      die "未知选项: $1（用 --help 查看用法）"
      ;;
    *)
      if [ -n "$TARGET_INPUT" ]; then
        die "多余的参数: $1"
      fi
      TARGET_INPUT="$1"
      shift
      ;;
  esac
done

if [ -z "$TARGET_INPUT" ]; then
  usage
  exit 1
fi

command -v python3 >/dev/null 2>&1 || die "缺少 python3"
command -v curl >/dev/null 2>&1 || die "缺少 curl"
command -v rsync >/dev/null 2>&1 || die "缺少 rsync"
command -v ssh >/dev/null 2>&1 || die "缺少 ssh"

[ -f "$COMPOSE_FILE" ] || die "找不到 $COMPOSE_FILE"
[ -f "$README_FILE" ] || die "找不到 $README_FILE"

# 1. 提取当前仓库版本
CURRENT_TAG="$(python3 - "$COMPOSE_FILE" "$IMAGE_REPO" <<'PY'
import re, sys
path, repo = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
m = re.search(rf"image:\s*{re.escape(repo)}:([^\s#]+)", text)
if not m:
    sys.exit(1)
print(m.group(1))
PY
)" || die "无法从 $COMPOSE_FILE 解析当前 ${IMAGE_REPO} 版本"

log "当前仓库版本: ${CURRENT_TAG}"

# 2. 检查 Git 分支与工作区状态
CURRENT_BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"
if [ "$CURRENT_BRANCH" != "main" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    log "警告: 当前 git 分支为 '${CURRENT_BRANCH}'（正式升级需在 main 分支）"
  else
    die "当前 git 分支为 '${CURRENT_BRANCH}'，请先切回 main 分支再执行升级"
  fi
fi

if [ "$DRY_RUN" -eq 0 ]; then
  DIRTY_FILES="$(git -C "$REPO_ROOT" status --porcelain -- "$COMPOSE_FILE" "$README_FILE")"
  if [ -n "$DIRTY_FILES" ]; then
    die "compose.yaml 或 README.md 有未提交改动，请先提交或暂存后再升级:\n$DIRTY_FILES"
  fi
fi

# 3. 查询 GitHub Release Notes（若目标为 latest 则自动解析最新 tag）
log "查询 GitHub Release 信息..."
RELEASES_JSON="$(curl -fsSL -H 'Accept: application/vnd.github+json' "$GITHUB_RELEASES_API")" \
  || die "无法请求 GitHub Releases API"

TARGET_TAG="$(python3 -c '
import json, sys
target = sys.argv[1]
releases = json.load(sys.stdin)
if target == "latest":
    if not releases:
        sys.exit(1)
    print(releases[0]["tag_name"])
else:
    print(target)
' "$TARGET_INPUT" <<<"$RELEASES_JSON")" || die "无法解析目标版本"

if ! printf '%s' "$TARGET_TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9._-]+)?$'; then
  die "目标版本号格式不合法: $TARGET_TAG"
fi

log "目标版本: ${TARGET_TAG}"

python3 -c '
import json, sys
cur, tgt = sys.argv[1], sys.argv[2]
releases = json.load(sys.stdin)
found_tgt = False
shown = 0
print("")
print("================ Release Notes 摘要 ================")
for r in releases:
    tag = r.get("tag_name", "")
    if tag == tgt:
        found_tgt = True
    if not found_tgt:
        continue
    if tag == cur and tgt != cur:
        break
    pub = r.get("published_at", "")
    pre = " [prerelease]" if r.get("prerelease") else ""
    print(f"--- {tag} ({pub}){pre} ---")
    body = (r.get("body") or "").strip()
    if len(body) > 900:
        body = body[:900] + "\n... (完整内容见 GitHub Release)"
    print(body)
    print("")
    shown += 1
    if tag == cur:
        break
if shown == 0:
    print(f"(未在最近 15 个 Release 中找到 {tgt} 的说明，请手动核对 GitHub)")
print("====================================================")
print("")
' "$CURRENT_TAG" "$TARGET_TAG" <<<"$RELEASES_JSON"

if [ "$TARGET_TAG" = "$CURRENT_TAG" ] && [ "$FORCE" -eq 0 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    log "目标版本与当前版本相同（${CURRENT_TAG}），继续执行只读预检..."
  else
    log "当前已是目标版本 ${TARGET_TAG}，无需升级（如需强制重建请加 --force）"
    exit 0
  fi
fi

# 4. 远端只读预检：compose 一致性、容器状态、RDS 在途任务
LOCAL_SHA256="$(shasum -a 256 "$COMPOSE_FILE" | awk '{print $1}')"
log "连接 ${SSH_HOST} 执行只读预检..."

PRECHECK_OUT="$(ssh "$SSH_HOST" bash -s -- "$REMOTE_STACK_DIR" "$PG_BACKUP_IMAGE" <<'EOF'
set -euo pipefail
STACK_DIR="$1"
PG_IMG="$2"

REMOTE_SHA=$(sha256sum "${STACK_DIR}/compose.yaml" | awk '{print $1}')
echo "REMOTE_SHA=${REMOTE_SHA}"

CONTAINER_STATUS=$(docker ps --filter "name=^/new-api$" --format "{{.Image}} | {{.Status}}" || true)
echo "CONTAINER_STATUS=${CONTAINER_STATUS}"

if docker image inspect "$PG_IMG" >/dev/null 2>&1; then
  echo "PG_IMG_PRESENT=1"
else
  echo "PG_IMG_PRESENT=0"
fi

SQL_DSN=$(grep "^SQL_DSN=" "${STACK_DIR}/.env" | cut -d= -f2-)
if docker image inspect "$PG_IMG" >/dev/null 2>&1; then
  INFLIGHT=$(docker run --rm "$PG_IMG" psql "$SQL_DSN" -tA -c "SELECT count(*) FROM tasks WHERE status NOT IN ('SUCCESS', 'FAILURE', 'FAILED', 'CANCELLED');" 2>/dev/null || echo "ERR")
  CHANNELS=$(docker run --rm "$PG_IMG" psql "$SQL_DSN" -tA -c "SELECT count(*) FROM channels;" 2>/dev/null || echo "ERR")
  USERS=$(docker run --rm "$PG_IMG" psql "$SQL_DSN" -tA -c "SELECT count(*) FROM users;" 2>/dev/null || echo "ERR")
  echo "INFLIGHT=${INFLIGHT}"
  echo "CHANNELS=${CHANNELS}"
  echo "USERS=${USERS}"
else
  echo "INFLIGHT=SKIP"
  echo "CHANNELS=SKIP"
  echo "USERS=SKIP"
fi
EOF
)"

REMOTE_SHA="$(printf '%s\n' "$PRECHECK_OUT" | sed -n 's/^REMOTE_SHA=//p')"
CONTAINER_STATUS="$(printf '%s\n' "$PRECHECK_OUT" | sed -n 's/^CONTAINER_STATUS=//p')"
PG_IMG_PRESENT="$(printf '%s\n' "$PRECHECK_OUT" | sed -n 's/^PG_IMG_PRESENT=//p')"
INFLIGHT="$(printf '%s\n' "$PRECHECK_OUT" | sed -n 's/^INFLIGHT=//p')"
CHANNELS="$(printf '%s\n' "$PRECHECK_OUT" | sed -n 's/^CHANNELS=//p')"
USERS="$(printf '%s\n' "$PRECHECK_OUT" | sed -n 's/^USERS=//p')"

log "远端容器: ${CONTAINER_STATUS:-未运行}"
log "RDS 统计: in-flight tasks=${INFLIGHT}, channels=${CHANNELS}, users=${USERS}"

if [ "$LOCAL_SHA256" != "$REMOTE_SHA" ]; then
  die "compose.yaml 校验和不一致！本机=${LOCAL_SHA256} 远端=${REMOTE_SHA}。请先排查服务器与仓库差异。"
fi
log "compose.yaml 校验和一致 (${LOCAL_SHA256:0:12}...)"

if [ "$INFLIGHT" = "ERR" ]; then
  die "查询 RDS tasks 表失败，请检查数据库连接"
elif [ "$INFLIGHT" != "SKIP" ] && [ "$INFLIGHT" != "0" ]; then
  if [ "$FORCE" -eq 1 ]; then
    log "警告: 存在 ${INFLIGHT} 个在途异步任务，因 --force 继续"
  else
    die "存在 ${INFLIGHT} 个在途异步任务，已中止升级（可稍后再试或加 --force）"
  fi
fi

if [ "$PG_IMG_PRESENT" != "1" ]; then
  log "提示: 远端尚未缓存 ${PG_BACKUP_IMAGE}，正式升级备份前将自动拉取"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  log "[DRY-RUN] 全部预检通过，未做任何变更。"
  exit 0
fi

# 5. 交互确认
if [ "$AUTO_YES" -eq 0 ]; then
  printf '\n即将把 %s 上的 new-api 从 %s 升级到 %s（预计短暂中断 5-10 秒）。\n' "$SSH_HOST" "$CURRENT_TAG" "$TARGET_TAG"
  printf '确认继续？[y/N] '
  read -r REPLY
  case "$REPLY" in
    y|Y|yes|YES) ;;
    *)
      log "已取消升级"
      exit 0
      ;;
  esac
fi

TS="$(date '+%Y%m%d-%H%M%S')"
BACKUP_COMPOSE="${REMOTE_BACKUP_DIR}/compose.yaml.before-${TARGET_TAG}.${TS}"
BACKUP_SQL="${REMOTE_BACKUP_DIR}/new_api-before-${TARGET_TAG}-${TS}.sql.gz"

# 6. 先在远端拉取新镜像（不断服，同时验证 tag 存在）
log "远端预拉取镜像 ${IMAGE_REPO}:${TARGET_TAG}..."
ssh "$SSH_HOST" "docker pull '${IMAGE_REPO}:${TARGET_TAG}'"

# 7. 远端备份 compose.yaml 与 RDS new_api 库
log "远端备份 compose.yaml 与 RDS new_api 库..."
ssh "$SSH_HOST" bash -s -- "$REMOTE_STACK_DIR" "$REMOTE_BACKUP_DIR" "$BACKUP_COMPOSE" "$BACKUP_SQL" "$PG_BACKUP_IMAGE" "$SKIP_BACKUP" "$KEEP_BACKUPS" <<'EOF'
set -euo pipefail
STACK_DIR="$1"
BACKUP_DIR="$2"
BACKUP_COMPOSE="$3"
BACKUP_SQL="$4"
PG_IMG="$5"
SKIP_BACKUP="$6"
KEEP="$7"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
cp -p "${STACK_DIR}/compose.yaml" "$BACKUP_COMPOSE"

if [ "$SKIP_BACKUP" -eq 0 ]; then
  if ! docker image inspect "$PG_IMG" >/dev/null 2>&1; then
    docker pull "$PG_IMG"
  fi
  SQL_DSN=$(grep "^SQL_DSN=" "${STACK_DIR}/.env" | cut -d= -f2-)
  umask 077
  docker run --rm "$PG_IMG" pg_dump --no-owner --no-privileges "$SQL_DSN" | gzip -c > "$BACKUP_SQL"
  ls -lh "$BACKUP_SQL"
else
  echo "已按 --skip-backup 跳过数据库备份"
fi

# 仅保留最近 KEEP 份备份，避免无限增长
ls -1t "${BACKUP_DIR}"/new_api-before-*.sql.gz 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f
ls -1t "${BACKUP_DIR}"/compose.yaml.before-* 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f
EOF

# 8. 更新本机仓库 compose.yaml 与 README.md 并推送
log "更新仓库版本号 (${CURRENT_TAG} -> ${TARGET_TAG})..."
python3 - "$COMPOSE_FILE" "$README_FILE" "$IMAGE_REPO" "$CURRENT_TAG" "$TARGET_TAG" <<'PY'
import sys
compose_path, readme_path, repo, cur, tgt = sys.argv[1:6]

old_img = f"{repo}:{cur}"
new_img = f"{repo}:{tgt}"

c_text = open(compose_path, encoding="utf-8").read()
if old_img not in c_text:
    sys.exit(f"compose.yaml 中未找到 {old_img}")
open(compose_path, "w", encoding="utf-8").write(c_text.replace(old_img, new_img, 1))

r_text = open(readme_path, encoding="utf-8").read()
if old_img in r_text:
    open(readme_path, "w", encoding="utf-8").write(r_text.replace(old_img, new_img, 1))
else:
    print(f"[WARN] README.md 中未找到 {old_img}，请手动检查", file=sys.stderr)
PY

log "rsync 同步 compose.yaml 到 ${SSH_HOST}..."
rsync -av --chown=root:root "$COMPOSE_FILE" "${SSH_HOST}:${REMOTE_STACK_DIR}/compose.yaml"

# 9. 重建容器并等待 healthy
log "重建 new-api 容器并等待健康检查..."
if ! ssh "$SSH_HOST" bash -s -- "$REMOTE_STACK_DIR" <<'EOF'
set -euo pipefail
cd "$1"
docker compose up -d new-api
for i in $(seq 1 30); do
  status=$(docker inspect -f "{{.State.Health.Status}}" new-api 2>/dev/null || echo "unknown")
  echo "  [${i}/30] health=${status}"
  if [ "$status" = "healthy" ]; then
    exit 0
  fi
  sleep 2
done
echo "=== 容器未在 60s 内 healthy，最近 40 行日志 ===" >&2
docker logs --tail 40 new-api >&2 || true
exit 1
EOF
then
  printf '\n[ERROR] 升级后健康检查失败！回滚参考：\n' >&2
  printf '  1) 恢复 compose: ssh %s "cp -p %s %s/compose.yaml && cd %s && docker compose up -d new-api"\n' \
    "$SSH_HOST" "$BACKUP_COMPOSE" "$REMOTE_STACK_DIR" "$REMOTE_STACK_DIR" >&2
  printf '  2) 如需回滚数据库，先停 new-api 再从 %s 恢复 RDS new_api 库。\n' "$BACKUP_SQL" >&2
  printf '  3) 恢复本机仓库: git checkout -- nyh-prod-2026/docker/new-api/compose.yaml nyh-prod-2026/README.md\n' >&2
  exit 1
fi

# 10. 公网版本核验
log "核验公网接口 ${STATUS_URL}..."
LIVE_VERSION="$(curl -fsSL "$STATUS_URL" | python3 -c 'import sys, json; print(json.load(sys.stdin)["data"].get("version", ""))')"
if [ "$LIVE_VERSION" != "$TARGET_TAG" ]; then
  die "公网返回版本 (${LIVE_VERSION}) 与目标版本 (${TARGET_TAG}) 不一致，请检查容器日志！"
fi

log "升级成功！当前线上版本: ${LIVE_VERSION}"
cat <<EOF

================ 升级完成汇总 ================
版本变更 : ${CURRENT_TAG} -> ${TARGET_TAG}
配置备份 : ${SSH_HOST}:${BACKUP_COMPOSE}
DB 备份  : ${SSH_HOST}:${BACKUP_SQL}
下一步   : 在 docs/operations/nyh-prod-2026.md 追加本次运维记录并 git commit
==============================================
EOF

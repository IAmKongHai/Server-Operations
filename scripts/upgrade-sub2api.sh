#!/usr/bin/env bash
# 一键蓝绿零停机升级 do-1 上的 sub2api（sub.tovo.sh）
#
# 流程：
#   1. 查询 GitHub Release Notes、官方 linux/amd64 包链接与目标 40 位 commit SHA
#   2. 远端预检当前活跃槽位、运行版本、目标 release 目录是否已存在
#   3. 在 do-1（旧金山直连 GitHub）下载官方预编译包并校验 checksums.txt，
#      合入对应 tag 的 backend/resources 与 version.txt
#   4. 交给 /usr/local/sbin/sub2api-deploy 完成 PG 备份、蓝绿切换、健康检查与旧槽排空
#   5. 核验新槽位与线上版本号
#
# 用法:
#   ./scripts/upgrade-sub2api.sh <target-tag|latest> [选项]
#
# 示例:
#   ./scripts/upgrade-sub2api.sh latest --dry-run
#   ./scripts/upgrade-sub2api.sh v0.2.25 --dry-run
#   ./scripts/upgrade-sub2api.sh v0.2.25
#   ./scripts/upgrade-sub2api.sh v0.2.25 --yes

set -euo pipefail

DO1_HOST="root@100.86.92.103"
SSH_KEY="${HOME}/.ssh/id_ed25519"
GITHUB_REPO="Wei-Shaw/sub2api"
GITHUB_RELEASES_API="https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=15"
TAILSCALE_BASE_URL="http://100.86.92.103:8080"

TARGET_INPUT=""
DRY_RUN=0
AUTO_YES=0

usage() {
  cat <<'EOF'
用法: scripts/upgrade-sub2api.sh <target-tag|latest> [选项]

参数:
  <target-tag|latest>   目标版本号（如 v0.2.25）或 latest（自动查 GitHub 最新 Release）

选项:
  --dry-run             仅做预检（Release Notes、commit SHA、远端槽位与版本状态），不做任何修改
  --yes, -y             跳过交互确认
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
command -v ssh >/dev/null 2>&1 || die "缺少 ssh"
[ -f "$SSH_KEY" ] || die "找不到 SSH 私钥: $SSH_KEY"

run_ssh() {
  ssh -i "$SSH_KEY" "$DO1_HOST" "$@"
}

# 1. 查询 GitHub Releases 信息
log "查询 GitHub Release 信息 (${GITHUB_REPO})..."
RELEASES_JSON="$(curl -fsSL -H 'Accept: application/vnd.github+json' "$GITHUB_RELEASES_API")" \
  || die "无法请求 GitHub Releases API"

RELEASE_META="$(python3 -c '
import json, sys
target = sys.argv[1]
releases = json.load(sys.stdin)
chosen = None
if target == "latest":
    if releases:
        chosen = releases[0]
else:
    for r in releases:
        if r.get("tag_name") == target:
            chosen = r
            break

if not chosen:
    # 未在最近 15 条中找到时允许按 tag 拼接兜底
    if target == "latest":
        sys.exit("未找到任何 Release")
    ver = target.lstrip("v")
    print(f"TAG={target}")
    print(f"ASSET_NAME=sub2api_{ver}_linux_amd64.tar.gz")
    print(f"ASSET_URL=https://github.com/Wei-Shaw/sub2api/releases/download/{target}/sub2api_{ver}_linux_amd64.tar.gz")
    print(f"CHECKSUM_URL=https://github.com/Wei-Shaw/sub2api/releases/download/{target}/checksums.txt")
    sys.exit(0)

tag = chosen["tag_name"]
asset_name = ""
asset_url = ""
checksum_url = ""
for a in chosen.get("assets", []):
    name = a.get("name", "")
    url = a.get("browser_download_url", "")
    if name.endswith("_linux_amd64.tar.gz"):
        asset_name = name
        asset_url = url
    elif name == "checksums.txt":
        checksum_url = url

if not asset_url:
    sys.exit(f"Release {tag} 中未找到 *_linux_amd64.tar.gz 资产")

print(f"TAG={tag}")
print(f"ASSET_NAME={asset_name}")
print(f"ASSET_URL={asset_url}")
print(f"CHECKSUM_URL={checksum_url}")
' "$TARGET_INPUT" <<<"$RELEASES_JSON")" || die "解析目标 Release 失败"

TARGET_TAG="$(printf '%s\n' "$RELEASE_META" | sed -n 's/^TAG=//p')"
ASSET_NAME="$(printf '%s\n' "$RELEASE_META" | sed -n 's/^ASSET_NAME=//p')"
ASSET_URL="$(printf '%s\n' "$RELEASE_META" | sed -n 's/^ASSET_URL=//p')"
CHECKSUM_URL="$(printf '%s\n' "$RELEASE_META" | sed -n 's/^CHECKSUM_URL=//p')"

if ! printf '%s' "$TARGET_TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9._-]+)?$'; then
  die "目标版本号格式不合法: $TARGET_TAG"
fi

log "目标版本: ${TARGET_TAG} (${ASSET_NAME})"

# 2. 解析目标 tag 对应的 40 位 commit SHA
TARGET_SHA="$(curl -fsSL -H 'Accept: application/vnd.github+json' \
  "https://api.github.com/repos/${GITHUB_REPO}/git/ref/tags/${TARGET_TAG}" | python3 -c '
import json, sys, urllib.request
d = json.load(sys.stdin)
obj = d["object"]
if obj["type"] == "tag":
    req = urllib.request.Request(obj["url"], headers={"Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req) as resp:
        t = json.loads(resp.read())
    print(t["object"]["sha"])
else:
    print(obj["sha"])
')" || die "无法解析 tag ${TARGET_TAG} 对应的 commit SHA"

if ! printf '%s' "$TARGET_SHA" | grep -Eq '^[0-9a-f]{40}$'; then
  die "解析出的 commit SHA 格式异常: $TARGET_SHA"
fi
log "目标 Commit SHA: ${TARGET_SHA}"

# 3. 远端只读预检
log "连接 do-1 (${DO1_HOST}) 执行只读预检..."
PRECHECK_OUT="$(run_ssh bash -s -- "$TARGET_SHA" <<'EOF'
set -euo pipefail
TARGET_SHA="$1"
ACTIVE_SLOT="$(tr -d '[:space:]' < /opt/sub2api/active_slot 2>/dev/null || echo 'unknown')"
CURRENT_SHA="$(tr -d '[:space:]' < /opt/sub2api/current/version.txt 2>/dev/null || echo 'unknown')"
if [ "$ACTIVE_SLOT" = "blue" ]; then
  ACTIVE_PORT=8081
  NEXT_SLOT="green"
  NEXT_PORT=8082
else
  ACTIVE_PORT=8082
  NEXT_SLOT="blue"
  NEXT_PORT=8081
fi
UNIT_STATE="$(systemctl is-active "sub2api@${ACTIVE_SLOT}" 2>/dev/null || true)"
LIVE_VER="$(curl -fsS "http://127.0.0.1:${ACTIVE_PORT}/api/v1/settings/public" 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("data",{}).get("version") or d.get("version") or "unknown")' 2>/dev/null || echo 'unknown')"
if [ -e "/opt/sub2api/releases/${TARGET_SHA}" ]; then
  RELEASE_EXISTS=1
else
  RELEASE_EXISTS=0
fi
echo "ACTIVE_SLOT=${ACTIVE_SLOT}"
echo "ACTIVE_PORT=${ACTIVE_PORT}"
echo "NEXT_SLOT=${NEXT_SLOT}"
echo "NEXT_PORT=${NEXT_PORT}"
echo "UNIT_STATE=${UNIT_STATE}"
echo "CURRENT_SHA=${CURRENT_SHA}"
echo "LIVE_VER=${LIVE_VER}"
echo "RELEASE_EXISTS=${RELEASE_EXISTS}"
EOF
)"

ACTIVE_SLOT="$(printf '%s\n' "$PRECHECK_OUT" | sed -n 's/^ACTIVE_SLOT=//p')"
ACTIVE_PORT="$(printf '%s\n' "$PRECHECK_OUT" | sed -n 's/^ACTIVE_PORT=//p')"
NEXT_SLOT="$(printf '%s\n' "$PRECHECK_OUT" | sed -n 's/^NEXT_SLOT=//p')"
NEXT_PORT="$(printf '%s\n' "$PRECHECK_OUT" | sed -n 's/^NEXT_PORT=//p')"
UNIT_STATE="$(printf '%s\n' "$PRECHECK_OUT" | sed -n 's/^UNIT_STATE=//p')"
CURRENT_SHA="$(printf '%s\n' "$PRECHECK_OUT" | sed -n 's/^CURRENT_SHA=//p')"
LIVE_VER="$(printf '%s\n' "$PRECHECK_OUT" | sed -n 's/^LIVE_VER=//p')"
RELEASE_EXISTS="$(printf '%s\n' "$PRECHECK_OUT" | sed -n 's/^RELEASE_EXISTS=//p')"

CURRENT_TAG="v${LIVE_VER#v}"
log "当前活跃槽位: ${ACTIVE_SLOT} (:${ACTIVE_PORT}, systemd=${UNIT_STATE})"
log "当前线上版本: ${CURRENT_TAG} (SHA=${CURRENT_SHA:0:12}...)"
log "目标部署槽位: ${NEXT_SLOT} (:${NEXT_PORT})"

# 4. 打印 Release Notes 摘要
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
    print(f"--- {tag} ({pub}) ---")
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

if [ "$TARGET_SHA" = "$CURRENT_SHA" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[DRY-RUN] 当前已是目标版本 ${TARGET_TAG}，全部预检通过，未做任何变更。"
    exit 0
  fi
  log "当前已是目标版本 ${TARGET_TAG} (${TARGET_SHA})，无需升级。"
  exit 0
fi

if [ "$RELEASE_EXISTS" = "1" ]; then
  die "远端 /opt/sub2api/releases/${TARGET_SHA} 已存在（sub2api-deploy 不允许覆盖）；如需切回旧版本请使用 /usr/local/sbin/sub2api-rollback。"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  log "[DRY-RUN] 全部预检通过，可执行蓝绿升级：${CURRENT_TAG} (${ACTIVE_SLOT}) -> ${TARGET_TAG} (${NEXT_SLOT})。"
  exit 0
fi

# 5. 交互确认
if [ "$AUTO_YES" -eq 0 ]; then
  printf '即将把 do-1 上的 sub2api 从 %s (%s) 蓝绿零停机升级到 %s (%s 槽 :%s)。\n' \
    "$CURRENT_TAG" "$ACTIVE_SLOT" "$TARGET_TAG" "$NEXT_SLOT" "$NEXT_PORT"
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

# 6. 远端下载、校验、封装并调用 /usr/local/sbin/sub2api-deploy
log "在 do-1 下载官方包、校验完整性并执行蓝绿发布..."
if ! run_ssh bash -s -- "$TARGET_TAG" "$TARGET_SHA" "$ASSET_NAME" "$ASSET_URL" "$CHECKSUM_URL" "$GITHUB_REPO" "$NEXT_SLOT" "$NEXT_PORT" <<'EOF'
set -euo pipefail
TARGET_TAG="$1"
TARGET_SHA="$2"
ASSET_NAME="$3"
ASSET_URL="$4"
CHECKSUM_URL="$5"
GITHUB_REPO="$6"
NEXT_SLOT="$7"
NEXT_PORT="$8"

WORK="$(mktemp -d "/tmp/sub2api-${TARGET_TAG}.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "[do-1] 下载 ${ASSET_NAME}..."
curl -fsSL -o "${WORK}/upstream.tar.gz" "$ASSET_URL"

if [ -n "$CHECKSUM_URL" ]; then
  echo "[do-1] 校验 checksums.txt..."
  curl -fsSL -o "${WORK}/checksums.txt" "$CHECKSUM_URL"
  EXPECTED="$(grep -F " ${ASSET_NAME}" "${WORK}/checksums.txt" | awk '{print $1}')"
  ACTUAL="$(sha256sum "${WORK}/upstream.tar.gz" | awk '{print $1}')"
  if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "[ERROR] sha256 校验失败: expected=${EXPECTED:-empty} actual=${ACTUAL}" >&2
    exit 1
  fi
  echo "[do-1] sha256 校验通过 (${ACTUAL:0:16}...)"
else
  echo "[do-1] 警告: Release 未提供 checksums.txt，跳过哈希校验"
fi

mkdir -p "${WORK}/stage"
tar -xzf "${WORK}/upstream.tar.gz" -C "${WORK}/stage" sub2api
chmod +x "${WORK}/stage/sub2api"

echo "[do-1] 提取 ${TARGET_TAG} 的 backend/resources..."
curl -fsSL -o "${WORK}/src.tar.gz" "https://github.com/${GITHUB_REPO}/archive/refs/tags/${TARGET_TAG}.tar.gz"
SRC_PREFIX="$(tar -tzf "${WORK}/src.tar.gz" | head -n 1 | cut -d/ -f1)"
tar -xzf "${WORK}/src.tar.gz" -C "$WORK" "${SRC_PREFIX}/backend/resources"
mv "${WORK}/${SRC_PREFIX}/backend/resources" "${WORK}/stage/resources"

printf '%s\n' "$TARGET_SHA" > "${WORK}/stage/version.txt"
tar -czf "${WORK}/release.tar.gz" -C "${WORK}/stage" .

echo "[do-1] 调用 /usr/local/sbin/sub2api-deploy ${TARGET_SHA}..."
/usr/local/sbin/sub2api-deploy "$TARGET_SHA" < "${WORK}/release.tar.gz"

echo "[do-1] 最新 PG 备份:"
ls -lh /var/backups/sub2api/ | tail -n 2
echo "[do-1] 校验新槽位 ${NEXT_SLOT} (:${NEXT_PORT}):"
systemctl is-active "sub2api@${NEXT_SLOT}"
curl -fsS "http://127.0.0.1:${NEXT_PORT}/health"; echo ""
EOF
then
  printf '\n[ERROR] 远端部署失败！旧槽 (%s) 应未受影响；如需回滚可执行:\n' "$ACTIVE_SLOT" >&2
  printf '  ssh -i %s %s "/usr/local/sbin/sub2api-rollback"\n' "$SSH_KEY" "$DO1_HOST" >&2
  exit 1
fi

# 7. 本机端到端核验
log "核验 Tailscale 入口 ${TAILSCALE_BASE_URL}..."
curl -fsS "${TAILSCALE_BASE_URL}/health" >/dev/null || die "Tailscale /health 检查失败"
NEW_LIVE_VER="$(curl -fsS "${TAILSCALE_BASE_URL}/api/v1/settings/public" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("data",{}).get("version") or d.get("version") or "")')"
EXPECTED_VER="${TARGET_TAG#v}"
if [ "${NEW_LIVE_VER#v}" != "$EXPECTED_VER" ]; then
  die "线上返回版本 (${NEW_LIVE_VER}) 与目标版本 (${TARGET_TAG}) 不一致！"
fi

log "升级成功！当前线上版本: v${NEW_LIVE_VER#v}"
cat <<EOF

================ 升级完成汇总 ================
版本变更 : ${CURRENT_TAG} -> ${TARGET_TAG}
Commit   : ${TARGET_SHA}
槽位切换 : ${ACTIVE_SLOT} (:${ACTIVE_PORT}) -> ${NEXT_SLOT} (:${NEXT_PORT})
回滚命令 : ssh -i ${SSH_KEY} ${DO1_HOST} "/usr/local/sbin/sub2api-rollback"
下一步   : 在 docs/operations/do-1.md 追加本次运维记录并 git commit
==============================================
EOF

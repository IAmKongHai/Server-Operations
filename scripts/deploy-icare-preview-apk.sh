#!/usr/bin/env bash
# deploy-icare-preview-apk.sh — 一键替换 mas-icare.cypress.sg 上的 preview APK
#
# 线上路径：/var/www/mas-icare.cypress.sg/apk/icare-preview.apk
# 公网 URL：https://mas-icare.cypress.sg/apk/icare-preview.apk
# SSH 别名：dev-cypresso（~/.ssh/config）
#
# 用法：
#   ./scripts/deploy-icare-preview-apk.sh
#   ./scripts/deploy-icare-preview-apk.sh /path/to/icare-preview.apk
#   SSH_HOST=dev-cypresso ./scripts/deploy-icare-preview-apk.sh
#   SKIP_VERIFY=1 ./scripts/deploy-icare-preview-apk.sh   # 跳过公网 HEAD 校验
#   KEEP_BACKUP=1 ./scripts/deploy-icare-preview-apk.sh   # 线上保留 .bak.<timestamp>
#
# 依赖：ssh、scp、curl（校验时）、shasum/sha256sum（可选，用于比对）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SSH_HOST="${SSH_HOST:-dev-cypresso}"
REMOTE_DIR="/var/www/mas-icare.cypress.sg/apk"
REMOTE_NAME="icare-preview.apk"
PUBLIC_URL="${PUBLIC_URL:-https://mas-icare.cypress.sg/apk/icare-preview.apk}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"
KEEP_BACKUP="${KEEP_BACKUP:-0}"

LOCAL_APK="${1:-$REPO_ROOT/icare-preview.apk}"

log()  { printf '==> %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
human() {
  # macOS / Linux 通用的人类可读体积（IEC，1024 进制）
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$1"
  else
    awk -v b="$1" 'BEGIN {
      split("B,KiB,MiB,GiB,TiB", u, ",")
      i = 1
      while (b >= 1024 && i < 5) { b /= 1024; i++ }
      printf "%.1f%s\n", b, u[i]
    }'
  fi
}

[[ -f "$LOCAL_APK" ]] || die "本地 APK 不存在: $LOCAL_APK"
[[ -r "$LOCAL_APK" ]] || die "本地 APK 不可读: $LOCAL_APK"

LOCAL_SIZE="$(wc -c < "$LOCAL_APK" | tr -d ' ')"
[[ "$LOCAL_SIZE" -gt 0 ]] || die "本地 APK 大小为 0: $LOCAL_APK"

LOCAL_SHA=""
if command -v shasum >/dev/null 2>&1; then
  LOCAL_SHA="$(shasum -a 256 "$LOCAL_APK" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  LOCAL_SHA="$(sha256sum "$LOCAL_APK" | awk '{print $1}')"
fi

log "本地文件: $LOCAL_APK"
log "大小:     $(human "$LOCAL_SIZE") ($LOCAL_SIZE bytes)"
[[ -n "$LOCAL_SHA" ]] && log "SHA256:   $LOCAL_SHA"
log "目标主机: $SSH_HOST"
log "远程路径: $REMOTE_DIR/$REMOTE_NAME"
log "公网 URL: $PUBLIC_URL"

log "检查 SSH 连通性…"
ssh -o BatchMode=yes -o ConnectTimeout=15 "$SSH_HOST" 'true' \
  || die "无法 SSH 到 $SSH_HOST（检查 ~/.ssh/config 与密钥）"

REMOTE_TMP="/tmp/${REMOTE_NAME}.$$.upload"
TS="$(date +%Y%m%d%H%M%S)"

log "上传到 $SSH_HOST:$REMOTE_TMP …"
scp -o Compression=no "$LOCAL_APK" "$SSH_HOST:$REMOTE_TMP"

log "原子替换线上文件…"
# shellcheck disable=SC2029
ssh "$SSH_HOST" bash -s -- "$REMOTE_TMP" "$REMOTE_DIR" "$REMOTE_NAME" "$KEEP_BACKUP" "$TS" <<'REMOTE'
set -euo pipefail
tmp="$1"
dir="$2"
name="$3"
keep_backup="$4"
ts="$5"
dest="$dir/$name"

sudo mkdir -p "$dir"

if [[ "$keep_backup" == "1" && -f "$dest" ]]; then
  sudo cp -a "$dest" "${dest}.bak.${ts}"
  echo "backup: ${dest}.bak.${ts}"
fi

# 先落到同目录临时名，再 rename，尽量缩短不可用窗口
sudo mv "$tmp" "${dest}.new.${ts}"
sudo chmod 644 "${dest}.new.${ts}"
sudo chown root:root "${dest}.new.${ts}"
sudo mv -f "${dest}.new.${ts}" "$dest"

remote_size="$(stat -c '%s' "$dest" 2>/dev/null || stat -f '%z' "$dest")"
echo "remote_size=$remote_size"
ls -lh "$dest"
REMOTE

log "比对远端体积…"
REMOTE_SIZE="$(ssh "$SSH_HOST" "stat -c '%s' '$REMOTE_DIR/$REMOTE_NAME' 2>/dev/null || stat -f '%z' '$REMOTE_DIR/$REMOTE_NAME'")"
[[ "$REMOTE_SIZE" == "$LOCAL_SIZE" ]] \
  || die "远端体积不一致: local=$LOCAL_SIZE remote=$REMOTE_SIZE"

if [[ -n "$LOCAL_SHA" ]]; then
  log "比对远端 SHA256…"
  REMOTE_SHA="$(ssh "$SSH_HOST" "sha256sum '$REMOTE_DIR/$REMOTE_NAME' 2>/dev/null | awk '{print \$1}' || shasum -a 256 '$REMOTE_DIR/$REMOTE_NAME' | awk '{print \$1}'")"
  [[ "$REMOTE_SHA" == "$LOCAL_SHA" ]] \
    || die "远端 SHA256 不一致: local=$LOCAL_SHA remote=$REMOTE_SHA"
  log "SHA256 一致"
fi

if [[ "$SKIP_VERIFY" != "1" ]]; then
  log "公网 HEAD 校验 $PUBLIC_URL …"
  # 跟随重定向；只要最终 200 且 Content-Length 对上即可
  HEAD_OUT="$(curl -sS -I -L --max-time 60 "$PUBLIC_URL")"
  printf '%s\n' "$HEAD_OUT" | head -n 20
  HTTP_CODE="$(printf '%s\n' "$HEAD_OUT" | awk 'BEGIN{c=""} /^HTTP\//{c=$2} END{print c}')"
  CL="$(printf '%s\n' "$HEAD_OUT" | awk 'BEGIN{IGNORECASE=1} /^Content-Length:/{print $2}' | tr -d '\r' | tail -n1)"
  [[ "$HTTP_CODE" == "200" ]] || die "公网 HTTP 非 200: $HTTP_CODE"
  [[ -z "$CL" || "$CL" == "$LOCAL_SIZE" ]] \
    || die "公网 Content-Length 不一致: expected=$LOCAL_SIZE got=$CL"
  log "公网校验通过 (HTTP $HTTP_CODE, Content-Length=${CL:-n/a})"
else
  log "已跳过公网校验 (SKIP_VERIFY=1)"
fi

log "完成。下载地址: $PUBLIC_URL"

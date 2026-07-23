#!/usr/bin/env bash
# prune-gocache.sh — 按「2 天未用 + 体积门槛」修剪 Go build cache（self-hosted runner）
#
# 策略（与 docs/runbooks/ci-runner-pools.md 对齐）：
#   1. 删除 GOCACHE 下 mtime 超过 DAYS（默认 2）的文件
#   2. 若修剪后仍超过 MAX_GB（默认 20）→ 整目录清空（保留目录本身）
#   3. 可选 ORPHAN 默认路径一并删除
#
# 用法：
#   ./scripts/prune-gocache.sh /path/to/cache/go-build
#   DAYS=2 MAX_GB=20 ./scripts/prune-gocache.sh /path/to/go-build
#   DRY_RUN=1 ./scripts/prune-gocache.sh /path/to/go-build
#
# 安全：有 Runner.Worker 时请勿对正在写入的 slot 执行；脚本不自动杀进程。

set -euo pipefail

DAYS="${DAYS:-2}"
MAX_GB="${MAX_GB:-20}"
DRY_RUN="${DRY_RUN:-0}"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <gocache-dir> [more-dirs...]" >&2
  exit 2
fi

bytes_of() {
  # du -sk: portable-ish; macOS and Linux
  du -sk "$1" 2>/dev/null | awk '{print $1 * 1024}'
}

prune_one() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "skip (not a dir): $dir"
    return 0
  fi

  local before after before_h after_h
  before="$(bytes_of "$dir")"
  before_h="$(du -sh "$dir" 2>/dev/null | awk '{print $1}')"
  echo "==> $dir  before=$before_h  (prune mtime>+${DAYS}d, then cap ${MAX_GB}G)"

  if [[ "$DRY_RUN" == "1" ]]; then
    local n
    n="$(find "$dir" -type f -mtime +"$DAYS" 2>/dev/null | wc -l | tr -d ' ')"
    echo "    dry-run: would delete $n files older than ${DAYS}d"
  else
    # 删除超过 DAYS 天未改动的 cache 文件；空目录稍后 find 清
    find "$dir" -type f -mtime +"$DAYS" -delete 2>/dev/null || true
    find "$dir" -type d -empty -delete 2>/dev/null || true
    # 保证根目录还在
    mkdir -p "$dir"
  fi

  after="$(bytes_of "$dir")"
  after_h="$(du -sh "$dir" 2>/dev/null | awk '{print $1}')"
  local max_bytes=$((MAX_GB * 1024 * 1024 * 1024))
  if [[ "$after" -gt "$max_bytes" ]]; then
    echo "    still >${MAX_GB}G ($after_h) → full clear"
    if [[ "$DRY_RUN" != "1" ]]; then
      find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
      mkdir -p "$dir"
    fi
    after_h="$(du -sh "$dir" 2>/dev/null | awk '{print $1}')"
  fi
  echo "    after=$after_h"
}

for d in "$@"; do
  prune_one "$d"
done

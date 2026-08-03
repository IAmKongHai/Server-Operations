#!/usr/bin/env bash
# gha-runner-maintenance.sh — self-hosted GHA runner 日常磁盘维护
#
# 目标：防 _work/_temp 与 go-build 撑盘；可选 prune pnpm store。
# 对齐 docs/runbooks/ci-runner-pools.md
#
# 用法：
#   WORK_DIRS="~/gha/s1 ~/gha/s2" GOCACHE_DIRS="..." \
#     ./scripts/gha-runner-maintenance.sh
#   MODE=daily|weekly DRY_RUN=1 ./scripts/gha-runner-maintenance.sh
#
# 环境变量：
#   WORK_DIRS      空格分隔的 workFolder 根（短路径，如 ~/gha/s1）
#   GOCACHE_DIRS   空格分隔的 per-slot go-build 目录
#   PNPM_STORE     可选，共享 pnpm store 路径
#   GOMODCACHE_DIR 可选，共享 go mod cache；weekly 且 > GOMOD_MAX_GB 时 go clean -modcache
#   MODE           daily（默认）| weekly
#   WORK_MTIME_DAYS  默认 1：只清 work 下 mtime 超过 N 天的可清目录
#   DAYS / MAX_GB  传给 prune-gocache（默认 2 / 20）
#   GOMOD_MAX_GB   默认 10
#   SKIP_IF_WORKER=1（默认）有 Runner.Worker 时跳过破坏性清理
#   DRY_RUN=1
#   LOG_FILE       可选日志路径

set -euo pipefail

MODE="${MODE:-daily}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_IF_WORKER="${SKIP_IF_WORKER:-1}"
WORK_MTIME_DAYS="${WORK_MTIME_DAYS:-1}"
DAYS="${DAYS:-2}"
MAX_GB="${MAX_GB:-20}"
GOMOD_MAX_GB="${GOMOD_MAX_GB:-10}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRUNE_GOCACHE="${PRUNE_GOCACHE:-$SCRIPT_DIR/prune-gocache.sh}"
LOG_FILE="${LOG_FILE:-}"

log() {
  local line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$line"
  if [[ -n "$LOG_FILE" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "$line" >>"$LOG_FILE" 2>/dev/null || true
  fi
}

expand_path() {
  # shellcheck disable=SC2086
  eval echo "$1"
}

worker_running() {
  pgrep -f 'Runner\.Worker' >/dev/null 2>&1
}

bytes_of() {
  du -sk "$1" 2>/dev/null | awk '{print $1 * 1024}'
}

human_df() {
  df -h / /System/Volumes/Data 2>/dev/null || df -h / 2>/dev/null || true
}

# 清理单个 workFolder：_temp 全清；仓库 run 目录仅在非活跃且较旧时删
# 保留 _tool / _actions / _PipelineMapping（避免 Sonar/工具反复下载）
clean_work_dir() {
  local root="$1"
  root="$(expand_path "$root")"
  if [[ ! -d "$root" ]]; then
    log "skip work (missing): $root"
    return 0
  fi

  local before after
  before="$(du -sh "$root" 2>/dev/null | awk '{print $1}')"
  log "work clean: $root (before=$before)"

  # _temp：job 临时目录，可清（mtime 过滤 + 无 worker 时全清过期）
  if [[ -d "$root/_temp" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      local n
      n="$(find "$root/_temp" -mindepth 1 -mtime +0 2>/dev/null | wc -l | tr -d ' ')"
      log "  dry-run: would prune _temp entries ~$n (mtime>+0d)"
    else
      find "$root/_temp" -mindepth 1 -mtime +0 -exec rm -rf {} + 2>/dev/null || true
      # 若 _temp 仍巨大且无 worker，再清剩余
      if ! worker_running; then
        find "$root/_temp" -mindepth 1 -exec rm -rf {} + 2>/dev/null || true
      fi
    fi
  fi

  # 仓库工作区：形如 _work/<repo>/<run>；清 mtime 较旧且非当前活跃的
  # 短路径布局：root 下直接是 repo 名或 _temp/_tool
  local d
  for d in "$root"/*; do
    [[ -e "$d" ]] || continue
    local base
    base="$(basename "$d")"
    case "$base" in
      _tool|_actions|_PipelineMapping|_update|_update.sh|_temp) continue ;;
    esac
    if [[ ! -d "$d" ]]; then
      continue
    fi
    # 目录 mtime 超过 WORK_MTIME_DAYS 才删（避免清正在用的）
    if [[ -n "$(find "$d" -maxdepth 0 -mtime +"$WORK_MTIME_DAYS" 2>/dev/null)" ]]; then
      if [[ "$DRY_RUN" == "1" ]]; then
        log "  dry-run: would rm -rf $d"
      else
        log "  rm stale repo dir: $d"
        rm -rf "$d"
      fi
    fi
  done

  after="$(du -sh "$root" 2>/dev/null | awk '{print $1}')"
  log "  after=$after"
}

maybe_prune_pnpm() {
  local store="${PNPM_STORE:-}"
  [[ -n "$store" ]] || return 0
  store="$(expand_path "$store")"
  [[ -d "$store" ]] || {
    log "pnpm store missing, mkdir: $store"
    [[ "$DRY_RUN" == "1" ]] || mkdir -p "$store"
    return 0
  }

  local size_h
  size_h="$(du -sh "$store" 2>/dev/null | awk '{print $1}')"
  log "pnpm store: $store size=$size_h"

  if [[ "$MODE" != "weekly" ]]; then
    return 0
  fi

  if command -v pnpm >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log "  dry-run: pnpm store prune --store-dir $store"
    else
      pnpm store prune --store-dir "$store" 2>&1 | tail -5 || log "  pnpm store prune failed (non-fatal)"
    fi
  else
    log "  pnpm not in PATH; skip store prune (dir kept for next install)"
  fi
}

maybe_prune_gomod() {
  local dir="${GOMODCACHE_DIR:-}"
  [[ -n "$dir" ]] || return 0
  dir="$(expand_path "$dir")"
  [[ -d "$dir" ]] || return 0

  local size_h size_b max_b
  size_h="$(du -sh "$dir" 2>/dev/null | awk '{print $1}')"
  size_b="$(bytes_of "$dir")"
  max_b=$((GOMOD_MAX_GB * 1024 * 1024 * 1024))
  log "GOMODCACHE: $dir size=$size_h (cap ${GOMOD_MAX_GB}G)"

  if [[ "$MODE" != "weekly" ]]; then
    return 0
  fi
  if [[ "$size_b" -le "$max_b" ]]; then
    log "  under cap; skip go clean -modcache"
    return 0
  fi
  if worker_running && [[ "$SKIP_IF_WORKER" == "1" ]]; then
    log "  Worker running; skip modcache clean"
    return 0
  fi
  if command -v go >/dev/null 2>&1; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log "  dry-run: GOMODCACHE=$dir go clean -modcache"
    else
      GOMODCACHE="$dir" go clean -modcache 2>&1 | tail -5 || true
      mkdir -p "$dir"
      log "  after=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')"
    fi
  else
    log "  go not in PATH; skip modcache clean"
  fi
}

main() {
  log "=== gha-runner-maintenance MODE=$MODE DRY_RUN=$DRY_RUN host=$(hostname) user=$(whoami) ==="
  human_df | while read -r line; do log "df: $line"; done

  if worker_running && [[ "$SKIP_IF_WORKER" == "1" ]]; then
    log "WARNING: Runner.Worker detected — only safe _temp age prune; skip full GOCACHE wipe paths"
  fi

  if [[ -n "${WORK_DIRS:-}" ]]; then
    # shellcheck disable=SC2086
    for w in $WORK_DIRS; do
      clean_work_dir "$w"
    done
  else
    log "WORK_DIRS empty; skip work clean"
  fi

  if [[ -n "${GOCACHE_DIRS:-}" ]]; then
    if [[ -x "$PRUNE_GOCACHE" ]] || [[ -f "$PRUNE_GOCACHE" ]]; then
      if worker_running && [[ "$SKIP_IF_WORKER" == "1" ]]; then
        log "skip GOCACHE prune while Worker running"
      else
        # shellcheck disable=SC2086
        DRY_RUN="$DRY_RUN" DAYS="$DAYS" MAX_GB="$MAX_GB" bash "$PRUNE_GOCACHE" $GOCACHE_DIRS || log "prune-gocache non-zero"
      fi
    else
      log "prune-gocache.sh not found at $PRUNE_GOCACHE"
    fi
  fi

  maybe_prune_pnpm
  maybe_prune_gomod

  human_df | while read -r line; do log "df-after: $line"; done
  log "=== done ==="
}

main "$@"

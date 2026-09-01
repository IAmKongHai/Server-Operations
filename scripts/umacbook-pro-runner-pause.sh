#!/bin/bash
# Pause umacbook-pro-1/2 for a long absence (laptop going to school).
# Keeps Tailscale. Does not unregister GitHub runners.
#
# Must run as root to stop LaunchDaemons:
#   sudo /Users/for-konghai/gha/scripts/umacbook-pro-runner-pause.sh
#   sudo /Users/for-konghai/gha/scripts/umacbook-pro-runner-pause.sh --clean-cache
#
# Cache-only (no root; refuses if a Worker is still running):
#   /Users/for-konghai/gha/scripts/umacbook-pro-runner-pause.sh --clean-cache-only
#
# Resume later:
#   sudo /Users/for-konghai/gha/scripts/umacbook-pro-runner-resume.sh
#
# Do not touch system/homebrew.mxcl.tailscale.
set -euo pipefail

USER_HOME="/Users/for-konghai"
LOG="${USER_HOME}/Library/Logs/umacbook-pro-runner-pause.log"
CLEAN_CACHE=0
CLEAN_ONLY=0

RUNNER_LABELS=(
  actions.runner.cypressoai.umacbook-pro-1
  actions.runner.cypressoai.umacbook-pro-2
)
MAINT_LABELS=(
  com.cypressoai.gha-runner-maintenance
  com.cypressoai.gha-runner-maintenance-weekly
)

log() {
  local line="[$(date '+%Y-%m-%d %H:%M:%S %Z')] $*"
  echo "$line"
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  echo "$line" >>"$LOG" 2>/dev/null || true
}

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \?//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean-cache) CLEAN_CACHE=1 ;;
    --clean-cache-only) CLEAN_ONLY=1; CLEAN_CACHE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# Match the binary path only. A bare `pgrep -f Runner.Listener` also hits
# this script, ssh monitors, and `zsh -c '...Runner.Listener...'`.
worker_pids() {
  pgrep -f '/actions-runner/umacbook-pro-.*/.*Runner\.Worker' || true
}

worker_running() {
  [[ -n "$(worker_pids)" ]]
}

listener_pids() {
  pgrep -f '/actions-runner/umacbook-pro-.*/.*Runner\.Listener' || true
}

clean_cache() {
  if worker_running; then
    log "ERROR: Runner.Worker still running; refuse to clean cache"
    pgrep -lf 'Runner\.Worker' || true
    return 1
  fi

  log "=== disk before cache clean ==="
  df -h / /System/Volumes/Data 2>/dev/null || df -h /

  local dir
  for dir in \
    "${USER_HOME}/actions-runner/umacbook-pro-1/cache/go-build" \
    "${USER_HOME}/actions-runner/umacbook-pro-2/cache/go-build"
  do
    if [[ -d "$dir" ]]; then
      log "wipe GOCACHE $dir ($(du -sh "$dir" 2>/dev/null | awk '{print $1}'))"
      find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    fi
  done

  for dir in "${USER_HOME}/gha/u1" "${USER_HOME}/gha/u2"; do
    if [[ -d "$dir" ]]; then
      log "wipe workFolder $dir ($(du -sh "$dir" 2>/dev/null | awk '{print $1}'))"
      find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    else
      mkdir -p "$dir"
      chown for-konghai:staff "$dir" 2>/dev/null || true
    fi
  done

  if [[ -d "${USER_HOME}/go/pkg/mod" ]]; then
    log "wipe GOMODCACHE ${USER_HOME}/go/pkg/mod ($(du -sh "${USER_HOME}/go/pkg/mod" 2>/dev/null | awk '{print $1}'))"
    if command -v go >/dev/null 2>&1; then
      GOMODCACHE="${USER_HOME}/go/pkg/mod" go clean -modcache || true
    fi
    find "${USER_HOME}/go/pkg/mod" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
  fi

  for dir in \
    "${USER_HOME}/gha/cache/pnpm-store" \
    "${USER_HOME}/Library/Caches/pnpm"
  do
    if [[ -d "$dir" ]]; then
      log "wipe pnpm $dir ($(du -sh "$dir" 2>/dev/null | awk '{print $1}'))"
      find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    fi
  done

  for slot in 1 2; do
    local root="${USER_HOME}/actions-runner/umacbook-pro-${slot}"
    if [[ -d "${root}/_diag" ]]; then
      log "wipe _diag ${root}/_diag"
      find "${root}/_diag" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    fi
    # previous runner payload; current is bin.2.336.0
    if [[ -d "${root}/bin.2.335.1" ]]; then
      log "remove old ${root}/bin.2.335.1"
      rm -rf "${root}/bin.2.335.1"
    fi
    if [[ -d "${root}/externals.2.335.1" ]]; then
      log "remove old ${root}/externals.2.335.1"
      rm -rf "${root}/externals.2.335.1"
    fi
  done

  log "=== disk after cache clean ==="
  df -h / /System/Volumes/Data 2>/dev/null || df -h /
  du -sh \
    "${USER_HOME}/actions-runner/umacbook-pro-1" \
    "${USER_HOME}/actions-runner/umacbook-pro-2" \
    "${USER_HOME}/gha" \
    "${USER_HOME}/go" \
    2>/dev/null || true
}

if [[ "$CLEAN_ONLY" -eq 1 ]]; then
  clean_cache
  exit 0
fi

if [[ $(id -u) -ne 0 ]]; then
  echo "must run as root: sudo $0" >&2
  exit 1
fi

log "=== pause start $(date) ==="
log "hostname=$(hostname) user=$(id -un) clean_cache=${CLEAN_CACHE}"

if [[ -n "$(pgrep -f 'homebrew.mxcl.tailscale|tailscaled' || true)" ]]; then
  log "Tailscale left running (pid $(pgrep -f '/opt/homebrew/.*/tailscaled' | tr '\n' ' '))"
else
  log "WARN: tailscaled not found; not starting it (user asked to keep it, not to launch it)"
fi

log "disable runner + maintenance LaunchDaemons (not Tailscale)"
for label in "${RUNNER_LABELS[@]}" "${MAINT_LABELS[@]}"; do
  launchctl disable "system/${label}" && log "disabled system/${label}" || log "disable failed system/${label}"
done

# `launchctl disable` does NOT stop KeepAlive on an already-loaded job.
# SIGTERM on Listener just lets launchd restart it, and the wait loop never ends.
# Wait only for a real Worker; idle Listener is safe to bootout (ExitTimeOut ~20s).
waited=0
while worker_running; do
  log "waiting for Worker to finish (waited ${waited}s): $(pgrep -lf '/actions-runner/umacbook-pro-.*/.*Runner\.Worker' | tr '\n' '; ')"
  sleep 5
  waited=$((waited + 5))
  if [[ "$waited" -ge 7200 ]]; then
    log "ERROR: Worker still running after ${waited}s; not bootout (would kill the job)"
    exit 1
  fi
done
log "no Runner.Worker; bootout idle Listeners now"

log "bootout runner + maintenance"
for label in "${RUNNER_LABELS[@]}" "${MAINT_LABELS[@]}"; do
  if launchctl print "system/${label}" >/dev/null 2>&1; then
    launchctl bootout "system/${label}" && log "bootout system/${label}" || log "bootout failed system/${label}"
  else
    log "already unloaded system/${label}"
  fi
done

log "=== launchctl (expect runners/maintenance disabled, Tailscale still enabled) ==="
launchctl print system 2>/dev/null | grep -E "actions.runner.cypressoai.umacbook-pro|gha-runner-maintenance|homebrew.mxcl.tailscale" || true
log "=== processes ==="
ps aux | grep -E "Runner\.(Listener|Worker)|tailscaled" | grep -v grep || true

if [[ "$CLEAN_CACHE" -eq 1 ]]; then
  clean_cache
fi

log "=== pause end $(date) ==="
echo "logged to $LOG"
echo "resume later: sudo ${USER_HOME}/gha/scripts/umacbook-pro-runner-resume.sh"

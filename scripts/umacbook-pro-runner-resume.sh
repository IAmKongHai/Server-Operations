#!/bin/bash
# Resume umacbook-pro-1/2. Since 2026-08-19 these slots are LaunchDaemons
# (system/actions.runner.cypressoai.umacbook-pro-N), not Agents.
#
# After a long pause (disable + bootout, e.g. laptop at school) this also
# re-enables and bootstraps the plists, plus the maintenance timers.
# Does not touch Tailscale.
#
#   sudo /Users/for-konghai/gha/scripts/umacbook-pro-runner-resume.sh
set -u
USER_HOME="${HOME:-/Users/for-konghai}"
if [[ $(id -u) -eq 0 ]]; then
  USER_HOME="/Users/for-konghai"
fi
LOG="${USER_HOME}/Library/Logs/umacbook-pro-runner-resume.log"

RUNNER_LABELS=(
  actions.runner.cypressoai.umacbook-pro-1
  actions.runner.cypressoai.umacbook-pro-2
)
MAINT_LABELS=(
  com.cypressoai.gha-runner-maintenance
  com.cypressoai.gha-runner-maintenance-weekly
)

{
  echo "=== resume start $(date) ==="
  if [[ $(id -u) -ne 0 ]]; then
    echo "must run as root: sudo $0"
    echo "=== resume end $(date) (not root) ==="
    exit 1
  fi

  for label in "${RUNNER_LABELS[@]}" "${MAINT_LABELS[@]}"; do
    plist="/Library/LaunchDaemons/${label}.plist"
    echo "enable system/${label}"
    launchctl enable "system/${label}" || true
    if ! launchctl print "system/${label}" >/dev/null 2>&1; then
      if [[ -f "$plist" ]]; then
        echo "bootstrap $plist"
        launchctl bootstrap system "$plist" || true
      else
        echo "missing plist: $plist"
      fi
    fi
  done

  for label in "${RUNNER_LABELS[@]}"; do
    echo "kickstart -k system/${label}"
    launchctl kickstart -k "system/${label}" || true
    launchctl print "system/${label}" 2>&1 | grep -E "state =|pid =|error" | head -5 || echo "not loaded: $label"
  done

  echo "maintenance timers enabled (calendar interval; not kickstarted)"
  for label in "${MAINT_LABELS[@]}"; do
    launchctl print "system/${label}" 2>&1 | grep -E "state =|pid =|error|disabled" | head -5 || echo "not loaded: $label"
  done

  echo "=== resume end $(date) ==="
} >>"$LOG" 2>&1
echo "logged to $LOG"

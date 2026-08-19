#!/bin/bash
# Resume lemon-imac-1/2. Since 2026-08-19 these slots are LaunchDaemons
# (system/actions.runner.cypressoai.lemon-imac-N), not Agents.
# kickstart needs root; KeepAlive should already restart a crashed slot.
set -u
USER_HOME="${HOME:-/Users/for-konghai}"
LOG="${USER_HOME}/Library/Logs/lemon-imac-runner-resume.log"
{
  echo "=== resume start $(date) ==="
  labels=(
    system/actions.runner.cypressoai.lemon-imac-1
    system/actions.runner.cypressoai.lemon-imac-2
  )
  for label in "${labels[@]}"; do
    if [[ $(id -u) -eq 0 ]]; then
      launchctl kickstart -k "$label" || true
    fi
    launchctl print "$label" 2>&1 | grep -E "state =|pid =|error" | head -5 || echo "not loaded: $label"
  done
  echo "=== resume end $(date) ==="
} >>"$LOG" 2>&1
echo "logged to $LOG"

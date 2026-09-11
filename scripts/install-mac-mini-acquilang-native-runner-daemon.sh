#!/bin/bash
# 把仓库级 runner mac-mini-acquilang-native-1 装成 LaunchDaemon。
# 注销图形用户、重启后仍在线。必须在 mac-mini 上以 root 运行：
#   sudo /Users/konghai/gha/scripts/install-mac-mini-acquilang-native-runner-daemon.sh
#
# 不要运行 ./svc.sh install / start，那会把 LaunchAgent 装回
# ~/Library/LaunchAgents，登录后和 Daemon 双开。
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "must run as root: sudo $0" >&2
  exit 1
fi

if pgrep -f '/Users/konghai/actions-runner/mac-mini-acquilang-native-1/.*/Runner.Worker' >/dev/null; then
  echo "ERROR: Runner.Worker is running; wait for the job to finish." >&2
  pgrep -lf 'mac-mini-acquilang-native-1.*Runner.Worker' || true
  exit 1
fi

USER_NAME="konghai"
GROUP_NAME="staff"
USER_HOME="/Users/${USER_NAME}"
ROOT="${USER_HOME}/actions-runner/mac-mini-acquilang-native-1"
LABEL="actions.runner.konghai-friends-lab-AcquiLangAI.mac-mini-acquilang-native-1"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
SRC_PLIST="${ROOT}/${LABEL}.plist"
LOG_DIR="${USER_HOME}/Library/Logs/${LABEL}"

if [[ ! -x "${ROOT}/runsvc.sh" ]]; then
  echo "missing ${ROOT}/runsvc.sh" >&2
  exit 1
fi
if [[ ! -f "$SRC_PLIST" ]]; then
  echo "missing ${SRC_PLIST}" >&2
  exit 1
fi

# 先停掉临时 nohup。旧进程 argv 可能是 `./runsvc.sh`，不含绝对路径，
# 只 pgrep 绝对路径会漏掉，Daemon 会和残留 Listener 抢同一个 GitHub session。
python3 - "$ROOT" <<'PY'
import os, signal, subprocess, sys, time

root = sys.argv[1]

def cwd_of(pid):
    try:
        out = subprocess.check_output(
            ["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"],
            text=True, stderr=subprocess.DEVNULL,
        )
        return next((x[1:] for x in out.splitlines() if x.startswith("n")), "")
    except subprocess.CalledProcessError:
        return ""

out = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True)
victims = []
for line in out.splitlines():
    pid = int(line.split(None, 1)[0])
    if pid == os.getpid() or pid == os.getppid():
        continue
    cmd = line.split(None, 1)[1] if " " in line.strip() else ""
    cwd = cwd_of(pid)
    if cwd == root or root in cmd:
        victims.append(pid)
        print(f"stop leftover pid={pid} cwd={cwd} cmd={cmd}", flush=True)

for pid in victims:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
time.sleep(2)
PY

mkdir -p "$LOG_DIR"
chown "${USER_NAME}:${GROUP_NAME}" "$LOG_DIR"

cp "$SRC_PLIST" "$PLIST"
chown root:wheel "$PLIST"
chmod 644 "$PLIST"
plutil -lint "$PLIST" >/dev/null

if launchctl print "system/${LABEL}" >/dev/null 2>&1; then
  launchctl bootout "system/${LABEL}" || true
fi
launchctl bootstrap system "$PLIST"
launchctl enable "system/${LABEL}"
launchctl kickstart -k "system/${LABEL}"

printf '%s\n' "$PLIST" >"${ROOT}/.service"
chown "${USER_NAME}:${GROUP_NAME}" "${ROOT}/.service"

sleep 2
echo "=== launchd ==="
launchctl print "system/${LABEL}" | grep -E 'state =|pid =|path =' || true
echo "=== processes ==="
ps aux | grep -E "mac-mini-acquilang-native-1.*(runsvc|Runner.Listener)" | grep -v grep || true
echo "done: system/${LABEL}"

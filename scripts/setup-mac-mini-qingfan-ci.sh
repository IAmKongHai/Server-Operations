#!/bin/bash
# 2026-10-30 一次性变更：mac-mini 上给 qingfan 装 runner 服务，并撤下 mac-mini-acquilang-native-1 的服务。
#   sudo /Users/hon/gha/scripts/setup-mac-mini-qingfan-ci.sh
#
# 1. 卸下 native-1 的 LaunchDaemon，plist 移到备份目录（不删除）。GitHub 注册和程序目录另行清理。
# 2. 用 install-mac-mini-qingfan-ci-runner-daemon.sh 安装 mac-mini-qingfan-ci-1..3 的 LaunchDaemon。
# 3. 把仓库版 install-mac-mini-team-services-daemons.sh 装到 /usr/local/sbin/hon-team-services.sh，
#    再用 --maintenance 重装维护任务（WORK_DIRS 去掉 al1、加 qf1..3）。
# 可重复执行：已完成的步骤会跳过。由 sudo 以 /bin/bash 3.2 运行，不要用 bash 4+ 语法。
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "请使用 sudo 运行：$0" >&2
  exit 1
fi

SCRIPTS=/Users/hon/gha/scripts
BACKUP_DIR=/Users/hon/gha/backups/qingfan-ci-20261030
NATIVE_LABEL=actions.runner.konghai-friends-lab-AcquiLangAI.mac-mini-acquilang-native-1
NATIVE_PLIST=/Library/LaunchDaemons/${NATIVE_LABEL}.plist
NATIVE_ROOT=/Users/hon/actions-runner/mac-mini-acquilang-native-1

echo "== 1/3 撤下 mac-mini-acquilang-native-1 的服务"
if pgrep -f "${NATIVE_ROOT}/bin/Runner.Worker" >/dev/null; then
  echo "native-1 正在执行 job，先不动它，退出。" >&2
  exit 1
fi
if launchctl print "system/${NATIVE_LABEL}" >/dev/null 2>&1; then
  launchctl bootout "system/${NATIVE_LABEL}"
  echo "已 bootout system/${NATIVE_LABEL}"
else
  echo "服务已不在，跳过 bootout"
fi
if [[ -e $NATIVE_PLIST ]]; then
  mkdir -p "$BACKUP_DIR"
  mv "$NATIVE_PLIST" "${BACKUP_DIR}/${NATIVE_LABEL}.plist.removed"
  echo "plist 已移到 ${BACKUP_DIR}/${NATIVE_LABEL}.plist.removed"
fi

echo "== 2/3 安装 mac-mini-qingfan-ci-1..3 的 LaunchDaemon"
"${SCRIPTS}/install-mac-mini-qingfan-ci-runner-daemon.sh" 1 2 3

echo "== 3/3 更新维护任务"
install -o root -g wheel -m 755 "${SCRIPTS}/install-mac-mini-team-services-daemons.sh" /usr/local/sbin/hon-team-services.sh
/usr/local/sbin/hon-team-services.sh --maintenance
/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:WORK_DIRS' /Library/LaunchDaemons/com.cypressoai.gha-runner-maintenance.plist

echo "完成。"

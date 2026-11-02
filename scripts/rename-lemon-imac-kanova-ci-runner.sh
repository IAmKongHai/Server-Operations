#!/bin/bash
# 将 lemon-imac 上的 lemon-imac-acquilang-ci-1 彻底改名为 lemon-imac-kanova-ci-1（含目录、GitHub 注册、LaunchDaemon）。
#
# 用法：
#   sudo /Users/for-konghai/gha/scripts/rename-lemon-imac-kanova-ci-runner.sh
#
# 前置条件：
#   /Users/for-konghai/gha/backups/kanova-rename-20261102/tokens.env 中已写入 REMOVE_TOKEN 与 REG_TOKEN（600）。
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "请使用 sudo 运行：${0}" >&2
  exit 1
fi

USER_NAME="for-konghai"
GROUP_NAME="staff"
USER_HOME="/Users/${USER_NAME}"
OLD_NAME="lemon-imac-acquilang-ci-1"
NEW_NAME="lemon-imac-kanova-ci-1"
OLD_ROOT="${USER_HOME}/actions-runner/${OLD_NAME}"
NEW_ROOT="${USER_HOME}/actions-runner/${NEW_NAME}"
OLD_LABEL="actions.runner.IAmKongHai-AcquiLangAI.${OLD_NAME}"
NEW_LABEL="actions.runner.IAmKongHai-Kanova.${NEW_NAME}"
OLD_PLIST="/Library/LaunchDaemons/${OLD_LABEL}.plist"
NEW_PLIST="/Library/LaunchDaemons/${NEW_LABEL}.plist"
SOURCE_PLIST="${NEW_ROOT}/${NEW_LABEL}.plist"
LOG_DIR="${USER_HOME}/Library/Logs/${NEW_LABEL}"
WORK_FOLDER="${USER_HOME}/gha/alci1"
SCOPE_URL="https://github.com/IAmKongHai/Kanova"
LABELS="kanova-build"
BACKUP_DIR="${USER_HOME}/gha/backups/kanova-rename-20261102"
TOKENS_FILE="${BACKUP_DIR}/tokens.env"

if pgrep -f "${USER_HOME}/actions-runner/lemon-imac-(acquilang|kanova)-ci-1/.*/Runner.Worker" >/dev/null 2>&1; then
  echo "Runner 正在执行 job，请等待结束后再运行。" >&2
  exit 1
fi

if [[ ! -f "${TOKENS_FILE}" ]]; then
  echo "缺少 token 文件：${TOKENS_FILE}" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${TOKENS_FILE}"
: "${REMOVE_TOKEN:?缺少 REMOVE_TOKEN}" "${REG_TOKEN:?缺少 REG_TOKEN}"

mkdir -p "${BACKUP_DIR}"
chown "${USER_NAME}:${GROUP_NAME}" "${BACKUP_DIR}"

echo "== 1/6 备份并卸载旧 LaunchDaemon (${OLD_LABEL})"
if [[ -f "${OLD_PLIST}" ]]; then
  cp -p "${OLD_PLIST}" "${BACKUP_DIR}/${OLD_LABEL}.plist.bak"
fi
launchctl bootout "system/${OLD_LABEL}" 2>/dev/null || true
launchctl disable "system/${OLD_LABEL}" 2>/dev/null || true
rm -f "${OLD_PLIST}"

pkill -TERM -f "${OLD_ROOT}/(bin/Runner.Listener|runsvc.sh)" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if ! pgrep -f "${OLD_ROOT}/(bin/Runner.Listener|runsvc.sh)" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if pgrep -f "${OLD_ROOT}/(bin/Runner.Listener|runsvc.sh)" >/dev/null 2>&1; then
  echo "旧 Runner.Listener 未退出，中止。" >&2
  exit 1
fi

echo "== 2/6 备份配置并注销旧 GitHub runner (${OLD_NAME})"
if [[ -d "${OLD_ROOT}" ]]; then
  for f in .runner .credentials .credentials_rsaparams .env .path .service; do
    if [[ -f "${OLD_ROOT}/${f}" ]]; then
      cp -p "${OLD_ROOT}/${f}" "${BACKUP_DIR}/${f}.bak"
    fi
  done
  rm -f "${OLD_ROOT}/.service" "${OLD_ROOT}/${OLD_LABEL}.plist"*
  for link in bin externals; do
    if [[ -L "${OLD_ROOT}/${link}" ]]; then
      target="$(basename "$(readlink "${OLD_ROOT}/${link}")")"
      ln -sfn "${target}" "${OLD_ROOT}/${link}"
      chown -h "${USER_NAME}:${GROUP_NAME}" "${OLD_ROOT}/${link}"
    fi
  done
  if [[ -f "${OLD_ROOT}/.runner" ]]; then
    sed -i '' 's#https://github.com/IAmKongHai/AcquiLangAI#https://github.com/IAmKongHai/Kanova#g' "${OLD_ROOT}/.runner"
    chown "${USER_NAME}:${GROUP_NAME}" "${OLD_ROOT}/.runner"
    (cd "${OLD_ROOT}" && sudo -u "${USER_NAME}" -H ./config.sh remove --token "${REMOVE_TOKEN}") || rm -f "${OLD_ROOT}/.runner" "${OLD_ROOT}/.credentials" "${OLD_ROOT}/.credentials_rsaparams"
  fi

  echo "== 3/6 重命名目录 ${OLD_ROOT} -> ${NEW_ROOT}"
  if [[ -e "${NEW_ROOT}" ]]; then
    echo "目标目录已存在：${NEW_ROOT}" >&2
    exit 1
  fi
  mv "${OLD_ROOT}" "${NEW_ROOT}"
fi

if [[ ! -d "${NEW_ROOT}" ]]; then
  echo "找不到新目录：${NEW_ROOT}" >&2
  exit 1
fi

echo "== 4/6 注册新 runner (${NEW_NAME})"
rm -f "${NEW_ROOT}/.service"
(cd "${NEW_ROOT}" && sudo -u "${USER_NAME}" -H ./config.sh --unattended --replace \
  --url "${SCOPE_URL}" \
  --token "${REG_TOKEN}" \
  --name "${NEW_NAME}" \
  --labels "${LABELS}" \
  --work "${WORK_FOLDER}")

echo "== 5/6 恢复 .env 与 .path"
if [[ -f "${BACKUP_DIR}/.env.bak" ]]; then
  cp -p "${BACKUP_DIR}/.env.bak" "${NEW_ROOT}/.env"
  chown "${USER_NAME}:${GROUP_NAME}" "${NEW_ROOT}/.env"
  chmod 600 "${NEW_ROOT}/.env"
fi
printf '%s\n' "${NEW_ROOT}/shims:/usr/bin:/bin:/usr/sbin:/sbin" > "${NEW_ROOT}/.path"
chown "${USER_NAME}:${GROUP_NAME}" "${NEW_ROOT}/.path"
chmod 600 "${NEW_ROOT}/.path"

echo "== 6/6 安装并启动新 LaunchDaemon (${NEW_LABEL})"
mkdir -p "${LOG_DIR}"
chown "${USER_NAME}:${GROUP_NAME}" "${LOG_DIR}"
cat > "${SOURCE_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${NEW_LABEL}</string>
  <key>ProgramArguments</key><array><string>${NEW_ROOT}/runsvc.sh</string></array>
  <key>UserName</key><string>${USER_NAME}</string>
  <key>GroupName</key><string>${GROUP_NAME}</string>
  <key>WorkingDirectory</key><string>${NEW_ROOT}</string>
  <key>RunAtLoad</key><false/>
  <key>KeepAlive</key><dict><key>PathState</key><dict>
    <key>${USER_HOME}/gha/.ciwork-mounted</key><true/>
  </dict></dict>
  <key>SessionCreate</key><true/>
  <key>StandardOutPath</key><string>${LOG_DIR}/stdout.log</string>
  <key>StandardErrorPath</key><string>${LOG_DIR}/stderr.log</string>
  <key>EnvironmentVariables</key><dict>
    <key>ACTIONS_RUNNER_SVC</key><string>1</string>
    <key>HOME</key><string>${USER_HOME}</string>
    <key>LANG</key><string>en_US.UTF-8</string>
    <key>LC_ALL</key><string>en_US.UTF-8</string>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>PNPM_STORE_PATH</key><string>${USER_HOME}/gha/cache/acquilang-pnpm-store</string>
    <key>npm_config_store_dir</key><string>${USER_HOME}/gha/cache/acquilang-pnpm-store</string>
    <key>NPM_CONFIG_CACHE</key><string>${USER_HOME}/gha/cache/acquilang-npm</string>
  </dict>
</dict></plist>
EOF
chown "${USER_NAME}:${GROUP_NAME}" "${SOURCE_PLIST}"
plutil -lint "${SOURCE_PLIST}"
install -o root -g wheel -m 644 "${SOURCE_PLIST}" "${NEW_PLIST}"
printf '%s\n' "${NEW_PLIST}" > "${NEW_ROOT}/.service"
chown "${USER_NAME}:${GROUP_NAME}" "${NEW_ROOT}/.service"

launchctl enable "system/${NEW_LABEL}"
launchctl bootstrap system "${NEW_PLIST}"
rm -f "${TOKENS_FILE}"

sleep 3
launchctl print "system/${NEW_LABEL}" | grep -E 'state =|pid =|path =' || true
echo "== 完成：system/${NEW_LABEL}"

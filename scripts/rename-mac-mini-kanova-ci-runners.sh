#!/bin/bash
# 将 mac-mini 上的 mac-mini-acquilang-ci-1..5 彻底改名为 mac-mini-kanova-ci-1..5（含目录、GitHub 注册、LaunchDaemon）。
# 其中 slot 1..3 在线重注册并启动；slot 4..5 保持 disabled。
#
# 用法：
#   sudo /Users/hon/gha/scripts/rename-mac-mini-kanova-ci-runners.sh
#
# 前置条件：
#   /Users/hon/gha/backups/kanova-rename-20261102/tokens.env 中已写入 REMOVE_TOKEN 与 REG_TOKEN（600）。
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "请使用 sudo 运行：${0}" >&2
  exit 1
fi

USER_NAME="hon"
GROUP_NAME="staff"
USER_HOME="/Users/${USER_NAME}"
SCOPE_URL="https://github.com/IAmKongHai/Kanova"
LABELS="kanova-build,kanova-ci"
RUNNER_PATH="/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
BACKUP_ROOT="${USER_HOME}/gha/backups/kanova-rename-20261102"
TOKENS_FILE="${BACKUP_ROOT}/tokens.env"

if pgrep -f "${USER_HOME}/actions-runner/mac-mini-(acquilang|kanova)-ci-[1-5]/.*/Runner.Worker" >/dev/null 2>&1; then
  echo "有 Runner 正在执行 job，请等待结束后再运行。" >&2
  exit 1
fi

if [[ ! -f "${TOKENS_FILE}" ]]; then
  echo "缺少 token 文件：${TOKENS_FILE}" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${TOKENS_FILE}"
: "${REMOVE_TOKEN:?缺少 REMOVE_TOKEN}" "${REG_TOKEN:?缺少 REG_TOKEN}"

rename_slot() {
  local slot="$1"
  local active="$2"
  local old_name="mac-mini-acquilang-ci-${slot}"
  local new_name="mac-mini-kanova-ci-${slot}"
  local old_root="${USER_HOME}/actions-runner/${old_name}"
  local new_root="${USER_HOME}/actions-runner/${new_name}"
  local old_label="actions.runner.IAmKongHai-AcquiLangAI.${old_name}"
  local new_label="actions.runner.IAmKongHai-Kanova.${new_name}"
  local old_plist="/Library/LaunchDaemons/${old_label}.plist"
  local new_plist="/Library/LaunchDaemons/${new_label}.plist"
  local source_plist="${new_root}/${new_label}.plist"
  local log_dir="${USER_HOME}/Library/Logs/${new_label}"
  local work_folder="${USER_HOME}/gha/alc${slot}"
  local backup_dir="${BACKUP_ROOT}/slot-${slot}"

  echo "=== 处理 slot ${slot} (${old_name} -> ${new_name}, active=${active}) ==="
  mkdir -p "${backup_dir}"
  chown "${USER_NAME}:${GROUP_NAME}" "${backup_dir}"

  if [[ -f "${old_plist}" ]]; then
    cp -p "${old_plist}" "${backup_dir}/${old_label}.plist.bak"
  fi
  launchctl bootout "system/${old_label}" 2>/dev/null || true
  launchctl disable "system/${old_label}" 2>/dev/null || true
  rm -f "${old_plist}"

  pkill -TERM -f "${old_root}/(bin/Runner.Listener|runsvc.sh)" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if ! pgrep -f "${old_root}/(bin/Runner.Listener|runsvc.sh)" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  if pgrep -f "${old_root}/(bin/Runner.Listener|runsvc.sh)" >/dev/null 2>&1; then
    echo "slot ${slot} 的旧 Runner.Listener 未退出，中止。" >&2
    exit 1
  fi

  if [[ -d "${old_root}" ]]; then
    for f in .runner .credentials .credentials_rsaparams .env .path .service; do
      if [[ -f "${old_root}/${f}" ]]; then
        cp -p "${old_root}/${f}" "${backup_dir}/${f}.bak"
      fi
    done
    rm -f "${old_root}/.service" "${old_root}/${old_label}.plist"*
    for link in bin externals; do
      if [[ -L "${old_root}/${link}" ]]; then
        local target
        target="$(basename "$(readlink "${old_root}/${link}")")"
        ln -sfn "${target}" "${old_root}/${link}"
        chown -h "${USER_NAME}:${GROUP_NAME}" "${old_root}/${link}"
      fi
    done
    if [[ -f "${old_root}/.runner" ]]; then
      sed -i '' 's#https://github.com/IAmKongHai/AcquiLangAI#https://github.com/IAmKongHai/Kanova#g' "${old_root}/.runner"
      chown "${USER_NAME}:${GROUP_NAME}" "${old_root}/.runner"
      if [[ "${active}" == "1" ]]; then
        (cd "${old_root}" && sudo -u "${USER_NAME}" -H ./config.sh remove --token "${REMOVE_TOKEN}") || rm -f "${old_root}/.runner" "${old_root}/.credentials" "${old_root}/.credentials_rsaparams"
      else
        sed -i '' "s#${old_name}#${new_name}#g" "${old_root}/.runner"
        chown "${USER_NAME}:${GROUP_NAME}" "${old_root}/.runner"
      fi
    fi

    if [[ -e "${new_root}" ]]; then
      echo "目标目录已存在：${new_root}" >&2
      exit 1
    fi
    mv "${old_root}" "${new_root}"
  fi

  if [[ ! -d "${new_root}" ]]; then
    echo "找不到新目录：${new_root}" >&2
    exit 1
  fi

  if [[ "${active}" == "1" ]]; then
    rm -f "${new_root}/.service"
    (cd "${new_root}" && sudo -u "${USER_NAME}" -H ./config.sh --unattended --replace \
      --url "${SCOPE_URL}" \
      --token "${REG_TOKEN}" \
      --name "${new_name}" \
      --labels "${LABELS}" \
      --work "${work_folder}")
  fi

  if [[ -f "${backup_dir}/.env.bak" ]]; then
    cp -p "${backup_dir}/.env.bak" "${new_root}/.env"
    chown "${USER_NAME}:${GROUP_NAME}" "${new_root}/.env"
    chmod 600 "${new_root}/.env"
  fi
  printf '%s\n' "${RUNNER_PATH}" > "${new_root}/.path"
  chown "${USER_NAME}:${GROUP_NAME}" "${new_root}/.path"
  chmod 600 "${new_root}/.path"

  mkdir -p "${log_dir}"
  chown "${USER_NAME}:${GROUP_NAME}" "${log_dir}"
  cat > "${source_plist}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${new_label}</string>
  <key>ProgramArguments</key><array><string>${new_root}/runsvc.sh</string></array>
  <key>UserName</key><string>${USER_NAME}</string>
  <key>GroupName</key><string>${GROUP_NAME}</string>
  <key>WorkingDirectory</key><string>${new_root}</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>SessionCreate</key><true/>
  <key>StandardOutPath</key><string>${log_dir}/stdout.log</string>
  <key>StandardErrorPath</key><string>${log_dir}/stderr.log</string>
  <key>EnvironmentVariables</key><dict>
    <key>ACTIONS_RUNNER_SVC</key><string>1</string>
    <key>DOCKER_HOST</key><string>unix:///Users/hon/.colima/team/docker.sock</string>
    <key>HOME</key><string>${USER_HOME}</string>
    <key>LANG</key><string>en_US.UTF-8</string>
    <key>LC_ALL</key><string>en_US.UTF-8</string>
    <key>PATH</key><string>${RUNNER_PATH}</string>
  </dict>
</dict></plist>
EOF
  chown "${USER_NAME}:${GROUP_NAME}" "${source_plist}"
  plutil -lint "${source_plist}"
  install -o root -g wheel -m 644 "${source_plist}" "${new_plist}"
  printf '%s\n' "${new_plist}" > "${new_root}/.service"
  chown "${USER_NAME}:${GROUP_NAME}" "${new_root}/.service"

  if [[ "${active}" == "1" ]]; then
    launchctl enable "system/${new_label}"
    launchctl bootstrap system "${new_plist}"
    launchctl print "system/${new_label}" | grep -E 'state =|pid =|path =' || true
  else
    launchctl disable "system/${new_label}"
    echo "已安装并保持 disabled：system/${new_label}"
  fi
}

rename_slot 1 1
rename_slot 2 1
rename_slot 3 1
rename_slot 4 0
rename_slot 5 0

rm -f "${TOKENS_FILE}"
echo "== 全部完成（slot 1..3 已启动，slot 4..5 保持 disabled）"

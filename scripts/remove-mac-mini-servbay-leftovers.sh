#!/bin/bash
# 清除 mac-mini 上 ServBay 卸载后的残留（应用本体早已删除）：
#   /etc/sudoers.d/servbay      admin 组免密以 root 跑 launchctl / kill / security 等，
#                               以及 /Applications/ServBay/** 下任意脚本（目录已不存在，admin 可自建）
#   /etc/hosts                  "Custom ServBay Hosts" 块（servbay.host / agent.nyh / center.nyh）
#   System 钥匙串               3 张 ServBay 根证书
# shell 配置里的 ServBay PATH 已由 konghai 自己删除（备份 ~/.zshrc.bak-20261023-servbay 等）。
#
# 在 mac-mini 上以 konghai 运行（需要 sudo 密码）：
#   sudo ~/hon-migrate-src/remove-mac-mini-servbay-leftovers.sh
set -euo pipefail

[[ $(id -u) -eq 0 ]] || { echo "请用 sudo 运行" >&2; exit 1; }

BACKUP_DIR=/var/backups/servbay-removal-$(date +%Y%m%d)
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# 1. sudoers（visudo -c 对非 0440 的文件报错并返回失败，先把 sudoers.d 统一成标准权限，规则内容不变）
chmod 0440 /etc/sudoers.d/*
if [[ -f /etc/sudoers.d/servbay ]]; then
  mv /etc/sudoers.d/servbay "$BACKUP_DIR/sudoers.servbay"
  visudo -c >/dev/null
  echo "已移除 /etc/sudoers.d/servbay"
fi

# 2. /etc/hosts 中 ServBay 生成的块
if grep -q '^# BEGIN Custom ServBay Hosts' /etc/hosts; then
  cp -p /etc/hosts "$BACKUP_DIR/hosts"
  sed -i '' '/^# BEGIN Custom ServBay Hosts/,/^# END Custom ServBay Hosts/d' /etc/hosts
  dscacheutil -flushcache
  killall -HUP mDNSResponder 2>/dev/null || true
  echo "已移除 /etc/hosts 中的 ServBay 块"
fi

# 3. System 钥匙串里的 ServBay 根证书（按 SHA-1 逐张删，先导出备份）
hashes=$(security find-certificate -a -Z -c ServBay /Library/Keychains/System.keychain 2>/dev/null | awk '/SHA-1 hash:/ {print $3}')
if [[ -n $hashes ]]; then
  security find-certificate -a -p -c ServBay /Library/Keychains/System.keychain >"$BACKUP_DIR/servbay-certs.pem"
fi
for hash in $hashes; do
  security delete-certificate -Z "$hash" /Library/Keychains/System.keychain
  echo "已删除证书 $hash"
done

echo "--- 复查"
ls /etc/sudoers.d
grep -ci servbay /etc/hosts || true
security find-certificate -a -c ServBay /Library/Keychains/System.keychain 2>/dev/null | grep -c labl || true
echo "备份：$BACKUP_DIR"

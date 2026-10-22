#!/bin/bash
# 安装 hon 迁移用的 root 脚本和临时 sudoers（迁移结束后在 U6 删除）。
# 在 mac-mini 上以 konghai 运行（需要 sudo 密码）；脚本改动后重跑即可覆盖：
#   sudo ~/hon-migrate-src/install-hon-migrate.sh
set -euo pipefail

[[ $(id -u) -eq 0 ]] || { echo "请用 sudo 运行" >&2; exit 1; }

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
SUDOERS=/etc/sudoers.d/konghai-hon-migrate

install -o root -g wheel -m 755 "$SRC_DIR/migrate-mac-mini-team-to-hon.sh" /usr/local/sbin/hon-migrate.sh
install -o root -g wheel -m 755 "$SRC_DIR/install-mac-mini-team-services-daemons.sh" /usr/local/sbin/hon-team-services.sh

# 先写临时文件并校验，语法错误时不覆盖现有 sudoers
tmp=$(mktemp)
echo 'konghai ALL=(root) NOPASSWD: /usr/local/sbin/hon-migrate.sh, /usr/local/sbin/hon-team-services.sh' >"$tmp"
visudo -cf "$tmp"
install -o root -g wheel -m 440 "$tmp" "$SUDOERS"
rm -f "$tmp"

ls -l /usr/local/sbin/hon-migrate.sh /usr/local/sbin/hon-team-services.sh "$SUDOERS"
echo "安装完成"

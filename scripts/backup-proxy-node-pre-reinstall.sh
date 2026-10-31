#!/usr/bin/env bash
# 代理节点（Rocky/EL + S-UI + nginx）整装前的全量配置备份，只读，不改任何服务。
# 用法（本机）：ssh <alias> 'bash -s' -- <alias> < scripts/backup-proxy-node-pre-reinstall.sh
# 产物：/root/<alias>-pre-reinstall-<时间戳>.tar.gz 和 .sha256，随后用 scp 拉回本机 _backups/。
# 包内含私钥、REALITY 密钥、客户端 UUID、tailscale 状态等敏感数据，只能放 gitignore 目录。
set -euo pipefail

NODE_ALIAS="${1:-$(hostname -s)}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_NAME="${NODE_ALIAS}-pre-reinstall-${STAMP}"
OUT="/root/${BACKUP_NAME}"
SUI_DB="/usr/local/s-ui/db/s-ui.db"

mkdir -p "$OUT"/{meta,system,ssh,network,firewall,sysctl,systemd,cron,s-ui,nginx,letsencrypt,tailscale,vnstat,root-home,opt}
chmod 700 "$OUT"

# 复制路径（保留属性与符号链接），不存在则跳过
copy_if_exists() {
  local src="$1" dest="$2"
  [ -e "$src" ] && cp -a "$src" "$dest" || true
}

# ---- 主机元信息（重建时对照用）----
{
  cat /etc/os-release; echo; uname -a; echo; hostnamectl 2>/dev/null; echo
  timedatectl 2>/dev/null; echo; lscpu | head -20; echo; free -h; echo
  lsblk; echo; df -hT
} > "$OUT/meta/host-snapshot.txt" 2>&1
ip -d addr > "$OUT/meta/ip-addr.txt" 2>&1
ip route > "$OUT/meta/ip-route.txt" 2>&1
ip -6 route > "$OUT/meta/ip6-route.txt" 2>&1
ss -tlnpu > "$OUT/meta/ss-tlnpu.txt" 2>&1
ps auxww > "$OUT/meta/ps-aux.txt" 2>&1
rpm -qa | sort > "$OUT/meta/rpm-qa.txt" 2>&1
dnf repolist --all > "$OUT/meta/dnf-repolist.txt" 2>&1 || true
systemctl list-unit-files --state=enabled --no-legend > "$OUT/meta/services-enabled.txt" 2>&1
systemctl list-units --type=service --state=running --no-legend > "$OUT/meta/services-running.txt" 2>&1
ls -la /usr/local/bin > "$OUT/meta/usr-local-bin.txt" 2>&1
[ -x /usr/local/bin/pip3.13 ] && /usr/local/bin/pip3.13 list > "$OUT/meta/pip3.13-list.txt" 2>&1 || true
getenforce > "$OUT/meta/selinux.txt" 2>&1 || true

# ---- 账户 ----
for account_file in passwd group shadow gshadow sudoers; do
  copy_if_exists "/etc/$account_file" "$OUT/system/"
done
copy_if_exists /etc/sudoers.d "$OUT/system/"
copy_if_exists /etc/chrony.conf "$OUT/system/"
copy_if_exists /etc/selinux/config "$OUT/system/selinux-config"
copy_if_exists /etc/localtime "$OUT/system/"

# ---- SSH：sshd 配置、主机密钥（恢复后客户端不报 host key 变更）、root 公钥 ----
copy_if_exists /etc/ssh "$OUT/ssh/etc-ssh"
copy_if_exists /root/.ssh "$OUT/ssh/root-dot-ssh"

# ---- 网络 ----
for net_file in hostname hosts resolv.conf; do
  copy_if_exists "/etc/$net_file" "$OUT/network/"
done
copy_if_exists /etc/sysconfig/network-scripts "$OUT/network/"
copy_if_exists /etc/NetworkManager/system-connections "$OUT/network/nm-connections"

# ---- 防火墙 ----
copy_if_exists /etc/firewalld "$OUT/firewall/etc-firewalld"
firewall-cmd --list-all-zones > "$OUT/firewall/list-all-zones.txt" 2>&1 || true
firewall-cmd --get-active-zones > "$OUT/firewall/active-zones.txt" 2>&1 || true
iptables-save > "$OUT/firewall/iptables-save.txt" 2>&1 || true
nft list ruleset > "$OUT/firewall/nft-ruleset.txt" 2>&1 || true

# ---- sysctl ----
copy_if_exists /etc/sysctl.conf "$OUT/sysctl/"
copy_if_exists /etc/sysctl.d "$OUT/sysctl/"
sysctl -a > "$OUT/sysctl/sysctl-a.txt" 2>/dev/null || true

# ---- systemd 自定义 unit ----
find /etc/systemd/system -maxdepth 1 -type f -name '*.service' -exec cp -a {} "$OUT/systemd/" \;
for unit in s-ui nginx tailscaled vnstat; do
  systemctl cat "$unit" > "$OUT/systemd/${unit}.cat.txt" 2>&1 || true
done

# ---- cron ----
crontab -l > "$OUT/cron/root-crontab.txt" 2>&1 || true
copy_if_exists /var/spool/cron "$OUT/cron/var-spool-cron"
copy_if_exists /etc/cron.d "$OUT/cron/"

# ---- S-UI：在线一致性备份 + 结构化导出（不导出体积巨大的 stats/changes）----
if [ -f "$SUI_DB" ]; then
  sqlite3 "$SUI_DB" ".backup '$OUT/s-ui/s-ui.db'"
  sqlite3 "$OUT/s-ui/s-ui.db" "PRAGMA integrity_check;" > "$OUT/s-ui/integrity-check.txt"
  sqlite3 "$OUT/s-ui/s-ui.db" ".tables" > "$OUT/s-ui/tables.txt"
  sqlite3 "$OUT/s-ui/s-ui.db" ".schema" > "$OUT/s-ui/schema.sql"
  for table in clients inbounds tls settings users outbounds endpoints services tokens; do
    sqlite3 -json "$OUT/s-ui/s-ui.db" "SELECT * FROM $table;" > "$OUT/s-ui/${table}.json" 2>&1 || true
  done
  sqlite3 -header -separator $'\t' "$OUT/s-ui/s-ui.db" \
    "SELECT id, name, enable, volume, expiry, up, down, inbounds, \"desc\" FROM clients ORDER BY id;" \
    > "$OUT/s-ui/clients-summary.tsv" 2>&1 || true
  copy_if_exists /usr/local/s-ui/s-ui.service "$OUT/s-ui/"
  copy_if_exists /usr/local/s-ui/s-ui.sh "$OUT/s-ui/"
  /usr/local/s-ui/sui -v > "$OUT/s-ui/version.txt" 2>&1 || true
  /usr/local/s-ui/sui setting -show > "$OUT/s-ui/setting-show.txt" 2>&1 || true
fi

# ---- nginx + 证书（证书保留 live→archive 符号链接）----
copy_if_exists /etc/nginx "$OUT/nginx/etc-nginx"
nginx -T > "$OUT/nginx/nginx-T.txt" 2>&1 || true
copy_if_exists /etc/letsencrypt "$OUT/letsencrypt/etc-letsencrypt"
certbot certificates > "$OUT/letsencrypt/certbot-certificates.txt" 2>&1 || true

# ---- tailscale 状态（恢复可保留同一节点身份与 100.x IP）----
copy_if_exists /var/lib/tailscale "$OUT/tailscale/var-lib-tailscale"
tailscale status > "$OUT/tailscale/status.txt" 2>&1 || true
tailscale ip > "$OUT/tailscale/ip.txt" 2>&1 || true

# ---- vnstat 历史 ----
copy_if_exists /var/lib/vnstat "$OUT/vnstat/var-lib-vnstat"
copy_if_exists /etc/vnstat.conf "$OUT/vnstat/"
vnstat --json > "$OUT/vnstat/vnstat.json" 2>&1 || true
vnstat -m > "$OUT/vnstat/vnstat-m.txt" 2>&1 || true

# ---- /opt 与 /root（跳过旧 S-UI 库副本、二进制、缓存，只留清单）----
copy_if_exists /opt "$OUT/opt/opt"
find /root -path "$OUT" -prune -o -ls > "$OUT/root-home/root-full-index.txt" 2>&1 || true
( cd /root && find . -path "./${BACKUP_NAME}" -prune -o \
    \( -path './.cache' -o -path './.local' -o -path './.npm' \) -prune -o \
    -type f -size -5M ! -name '*s-ui.db*' ! -name 'sui.*' ! -name '*.tar.gz' -print0 \
  | tar --null -T - -cf - ) | tar -xf - -C "$OUT/root-home"

# ---- 打包 ----
cd /root
tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
sha256sum "${BACKUP_NAME}.tar.gz" > "${BACKUP_NAME}.tar.gz.sha256"
chmod 600 "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}.tar.gz.sha256"
du -sh "$OUT" "${BACKUP_NAME}.tar.gz"
echo "BACKUP_TARBALL=/root/${BACKUP_NAME}.tar.gz"

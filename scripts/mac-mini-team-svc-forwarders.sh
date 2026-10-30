#!/bin/zsh
# mac-mini → team-svc（PVE VM 150，192.168.2.23）的过渡期 TCP 转发。
# 2026-10-31 colima team 的服务迁到 team-svc 后，保持 mac-mini:<端口> 这些老地址可用，
# 等客户端逐个改连 team-svc 后再撤掉。计划：docs/plans/2026-10-31-0010-ops-mac-mini-vms-to-pve-plan.md
#
# 部署：/Users/hon/.local/bin/team-svc-forwarders（hon crontab @reboot 拉起；本脚本自带单实例与重启）
#   0.0.0.0   9000 SonarQube、5432 richer-postgres、3001 richer-grafana、5437 nyh-postgres、
#             5433 acquilang-postgres、18080 sub2api
#   127.0.0.1 5434 shared-dev-postgres、6379 shared-dev-redis、3900 shared-dev-s3
#             （原来就只听回环，由 tailscale serve 转到 tailnet，保持暴露面不变）
#
# 用 /usr/bin/ssh -L 而不是 socat：mac-mini 开着应用防火墙，Homebrew 的 socat 未签名，
# 外部入站会被拦（只有本机回环能通），放行它需要 root；系统自带的 ssh 默认允许入站。

export PATH=/usr/bin:/bin:/usr/sbin:/sbin
TARGET=ubuntu@192.168.2.23
run_dir="$HOME/.local/run"
log_file="$HOME/Library/Logs/team-svc-forwarders.log"
pid_file="$run_dir/team-svc-forwarders.pid"

/bin/mkdir -p "$run_dir" "${log_file:h}"

# 单实例：已有存活的 supervisor 就退出
if [[ -f "$pid_file" ]]; then
  existing_pid="$(<"$pid_file")"
  if [[ "$existing_pid" == <-> ]] && /bin/kill -0 "$existing_pid" 2>/dev/null &&
     [[ "$(/bin/ps -p "$existing_pid" -o command=)" == *team-svc-forwarders* ]]; then
    exit 0
  fi
fi
print -r -- "$$" >| "$pid_file"
exec >> "$log_file" 2>&1

forwards=()
for port in 9000 5432 3001 5437 5433 18080; do forwards+=(-L "0.0.0.0:$port:127.0.0.1:$port"); done
for port in 5434 6379 3900; do forwards+=(-L "127.0.0.1:$port:127.0.0.1:$port"); done

ssh_pid=""
cleanup() {
  [[ -n "$ssh_pid" ]] && /bin/kill "$ssh_pid" 2>/dev/null
  /bin/rm -f "$pid_file"
  exit 0
}
trap cleanup INT TERM

# ssh 断开（VM 重启、网络抖动）后 10 秒重连
while true; do
  print -r -- "$(/bin/date -Iseconds) connecting $TARGET"
  /usr/bin/ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o ConnectTimeout=10 \
    "${forwards[@]}" "$TARGET" &
  ssh_pid=$!
  wait "$ssh_pid"
  print -r -- "$(/bin/date -Iseconds) ssh exited ($?), retry in 10s"
  ssh_pid=""
  /bin/sleep 10
done

# Handoff：给 iCare-public-backend 部署加 DB 连通性 pre-flight

- 日期：2026-08-10
- 目标仓库：`cypressoai/iCare-public-backend`（**不在本机，需在代码仓开新 session 处理**）
- base 分支：**`develop`**（iCare 活跃分支，base 到 main 对团队不生效）
- 背景来源：`docs/operations/dev-cypresso.md` → 2026-08-10 12:02 条目

---

## 一、为什么要做（本次真实故障）

2026-08-09 重装 `tizi-cyp` 后重新登录 Tailscale，其 IP 由 `100.88.178.78` → `100.116.91.14`。

`dev-cypresso` 上 iCare public-backend 访问 `mssql-ref` 的 MSSQL **不直连**（直连太慢），
而是经 `tizi-cyp` 的 socat 跳板：

```
dev-cypresso → tizi-cyp 100.116.91.14:1433 --socat--> mssql-ref 100.124.140.78:1433
               （mssql-ref-proxy.service，已 enabled 持久化）
```

跳板地址硬编码在宿主机 `/home/ec2-user/stacks/icare/public-backend/.env.{app,hr,map}`
的 `WEBKIT_DB_HOST`。IP 变了但 env 没同步 → 三个容器启动即
`dial tcp 100.88.178.78:1433: i/o timeout` → 崩溃重启循环 → CI 部署 job 连续失败
（run `31350189741` 已是第 4 次 attempt）。

**这批 `.env.*` 由宿主机本地维护、不入库，CI 无从校验。**

### 当前排查体验有多差

失败 job 的表现是：`docker compose up` 报告"成功"，然后健康检查轮询
`127.0.0.1:8090/8091/8092` 的 `/api/v1/health/live` 共 30 次 × 2s = **等满 60 秒**，
才 `docker compose logs --tail=200` 倒出 200 行日志再 `exit 1`。

那 200 行几乎全是同一条 DB 超时在刷屏，真正的根因（"配置里的 IP 已经不存在了"）
被淹没在噪声里，且要人肉比对 `tailscale status` 才能发现。

**pre-flight 的价值**：把这 60 秒 + 200 行噪声，换成启动前 2 秒内一条明确报错。

---

## 二、要做什么

在部署流程里、**`docker compose up` 之前**，探测各 env 文件里
`WEBKIT_DB_HOST:WEBKIT_DB_PORT` 的 TCP 连通性；**不通则立即 `exit 1`**（已与用户确认）。

### 为什么选"直接失败退出"而非"告警继续"

失败退出能保留上一版仍在运行的容器（若其健康），避免用坏配置把好容器换掉。
本次故障中容器已全崩，无此差别；但配置错误发生在服务正常时，这个选择能防止扩大故障。

---

## 三、落点

workflow 里 `Login GHCR and deploy` 这一步的脚本，现有开头是：

```bash
set -euo pipefail
test -f "$BASE_DIR/.env.app"
test -f "$BASE_DIR/.env.hr"
test -f "$BASE_DIR/.env.map"
# CYP-1911: non-local rejects SWAGGER_ENABLED=true; pin host env before up.
bash ./scripts/ensure-deploy-swagger-off.sh \
  "$BASE_DIR/.env.app" "$BASE_DIR/.env.hr" "$BASE_DIR/.env.map"
docker network inspect shared-services >/dev/null
...
$COMPOSE_CMD -f "$COMPOSE_FILE" pull public-app public-hr public-map
$COMPOSE_CMD -f "$COMPOSE_FILE" up -d public-app public-hr public-map
```

**建议**：仿照已有的 `ensure-deploy-swagger-off.sh`，新增
`scripts/preflight-db-reachable.sh`，紧跟其后调用、在 `up` 之前。

两个必须注意的点：

1. **脚本在 checkout 出来的仓库根目录里**（`./scripts/...`），
   **不在** `$BASE_DIR`（`/home/ec2-user/stacks/icare/public-backend`）。
   我在服务器上确认过 `$BASE_DIR/scripts/` 不存在，别搞混。
2. **同一 workflow 还有 `Deploy to mas-go-dev` job**（本次它是成功的）。
   两个 job 的部署脚本是各自独立的，若希望两边都受益，需要**两处都加**。
   mas-go-dev 的 env 指向地址是对的，加了不会破坏它 —— 但请确认它的
   env 文件里同样有 `WEBKIT_DB_*` 变量名，否则脚本需容忍"变量缺失"的情况。

---

## 四、参考实现

```bash
#!/usr/bin/env bash
# 部署前探测 WEBKIT_DB 可达性。
# 背景：WEBKIT_DB_HOST 指向 tizi-cyp 的 socat 跳板（非数据库本身），
# 跳板机重装/换 Tailscale IP 后该值会失效，导致容器崩溃循环、
# 健康检查空等 60s 才失败。见 2026-08-10 故障。
set -euo pipefail

timeout_sec="${PREFLIGHT_TIMEOUT:-5}"
failed=0

for env_file in "$@"; do
  [ -f "$env_file" ] || { echo "preflight: 缺少 env 文件 $env_file" >&2; exit 1; }

  # 只取行首匹配，避免被注释行或同名后缀变量干扰
  db_host="$(sed -n 's/^WEBKIT_DB_HOST=//p' "$env_file" | tail -n1)"
  db_port="$(sed -n 's/^WEBKIT_DB_PORT=//p' "$env_file" | tail -n1)"
  db_enabled="$(sed -n 's/^WEBKIT_DB_ENABLED=//p' "$env_file" | tail -n1)"

  # 未启用 webkit DB 的 profile 直接跳过
  if [ "${db_enabled:-true}" != "true" ]; then
    echo "preflight: $(basename "$env_file") WEBKIT_DB_ENABLED=$db_enabled，跳过"
    continue
  fi

  if [ -z "$db_host" ] || [ -z "$db_port" ]; then
    echo "preflight: $(basename "$env_file") 缺少 WEBKIT_DB_HOST/WEBKIT_DB_PORT" >&2
    failed=1
    continue
  fi

  if timeout "$timeout_sec" bash -c \
      "cat < /dev/null > /dev/tcp/${db_host}/${db_port}" 2>/dev/null; then
    echo "preflight ok: $(basename "$env_file") -> ${db_host}:${db_port}"
  else
    echo "preflight FAIL: $(basename "$env_file") -> ${db_host}:${db_port} 不可达" >&2
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  cat >&2 <<'EOF'

────────────────────────────────────────────────────────────
部署已中止：数据库（经跳板）不可达，容器起来也会崩溃循环。

WEBKIT_DB_HOST 指向的是 tizi-cyp 上的 socat 跳板，不是数据库本身。
常见原因与排查：

1) 跳板机 tizi-cyp 换了 Tailscale IP（重装系统后最常见）
   ssh tizi-cyp 'tailscale ip -4'
   若与 env 中的 WEBKIT_DB_HOST 不一致，需更新部署机上的
   .env.app / .env.hr / .env.map（这些文件不在仓库里，需登录宿主机改）

2) 跳板服务没起来
   ssh tizi-cyp 'systemctl status mssql-ref-proxy'

3) 跳板后端 mssql-ref 本身不可达
   ssh tizi-cyp 'timeout 5 bash -c "cat < /dev/null > /dev/tcp/100.124.140.78/1433"'

参考：Server 仓库 docs/operations/dev-cypresso.md（2026-08-10 条目）
────────────────────────────────────────────────────────────
EOF
  exit 1
fi
```

调用处（插在 `ensure-deploy-swagger-off.sh` 之后、`docker network inspect` 之前）：

```bash
bash ./scripts/preflight-db-reachable.sh \
  "$BASE_DIR/.env.app" "$BASE_DIR/.env.hr" "$BASE_DIR/.env.map"
```

### 实现细节说明

- 用 bash 的 `/dev/tcp`，无需在 runner 上装 `nc`/`socat`；
  但**要求 workflow 的 shell 是 bash**（`/dev/tcp` 是 bash 内建，dash/sh 没有）。
  确认 workflow step 未设成 `shell: sh`。
- `sed -n 's/^X=//p'` 锚定行首，避免匹配到注释或 `FOO_WEBKIT_DB_HOST=` 这类变量。
- 尊重 `WEBKIT_DB_ENABLED=false`，避免给未启用该 DB 的 profile 误报。
- `timeout` 默认 5s，比现在空等 60s 快一个数量级。

---

## 五、验收建议

1. **正常路径**：在 dev-cypresso 现状（已修复）下跑一次部署，
   应打印三条 `preflight ok` 且照常完成部署。
2. **失败路径**：临时把某个 env 的 `WEBKIT_DB_HOST` 改成
   一个不可达 IP（如 `100.88.178.78`，即本次故障的旧 IP），
   确认 job 在数秒内失败并打印排查指引，**且不重建容器**（原容器仍 healthy）。
   验完记得改回 `100.116.91.14`。

---

## 六、需要留意的坑（来自本次实操）

- `dev-cypresso` **没有 compose v2 CLI 插件**，`docker compose` 会报
  `unknown shorthand flag: 'f'`；机上是 `/usr/local/bin/docker-compose`（自身 v2.24.5）。
  workflow 已有 `COMPOSE_CMD` 探测回退逻辑，是对的，别"顺手简化"掉。
- 手工重建容器时必须
  `export PUBLIC_BACKEND_IMAGE=ghcr.io/cypressoai/icare-public-backend:<sha>`，
  否则 compose 回退到默认 `icare/public-backend:local`，报 GHCR
  `pull access denied`。
- `WEBKIT_DB_PASSWORD` 等敏感值就在这些 env 文件里，
  **脚本输出只打印 host:port，不要 echo 整个文件**。

---

## 七、当前状态

- 第 1 项（改 IP + 重建容器）**已完成并验证**：三容器 `RestartCount=0`、
  `healthy`，三个端口 `/api/v1/health/live` 首次尝试即 `"status":"up"`。
  备份在 `$BASE_DIR/.env.{app,hr,map}.bak.20260810`。
- 失败的 CI job 可以直接 re-run，现在应能通过。
- 本 handoff 对应的 pre-flight 改动 **尚未开始**。

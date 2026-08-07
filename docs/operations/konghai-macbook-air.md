# macbook（本机 MacBook Air）运维时间线

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`konghai-macbook-air`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：本机 Mac.lan：CLEAN。python walk 覆盖 ~/Code 共 83 个 node_modules；存在 keyv/flat-cache 等正常依赖目录，但其内无恶意 setup.mjs/Math_Symbol.js/math_init.js；无 preinstall 钩子、无高危 lock 版本、无 IDE 钩子。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

## 2026-07-10 11:00 CST - MSSQL 访问恢复：mssql-ref 已 Tailscale direct（~8–10ms）

- 设备：本机 `macbook-air`（`100.92.181.15`，办公室 `192.168.6.111`）
- 原因：上午 DERP 中继导致库极慢；已在家宽侧为节点分配独立 UDP 端口后打通 direct。
- 本机动作：`tailscale down/up` 重连、多次 `tailscale ping` 强制探测；未改本机持久配置。
- 验证：
  - `tailscale status`：`mssql-ref ... active; direct 112.117.237.252:41364`
  - `ping 100.124.140.78` ≈ **8–10 ms**（修复前平均 300–500ms+，峰值 1s+）
  - 连库建议：`100.124.140.78:1433` 或 MagicDNS `mssql-ref`（走 peer direct）；`192.168.2.20` 仍经 `pve` 子网路由，可能慢一截。
- 完整变更见 `docs/operations/mssql-ref.md` / `docs/operations/pve.md` 同时间条目。

## 2026-07-10 10:48 CST - MSSQL 感觉极慢：本机经 Tailscale DERP(km) 访问，未建立直连

- 设备：本机 `macbook-air`（Tailscale `100.92.181.15`），局域网 `192.168.6.111/24`（网关 `192.168.6.1`）。
- 原因：访问 `mssql-ref`（`192.168.2.20` / `100.124.140.78`）极慢；用户确认根因是 **Tailscale 隧道未打通直连**。
- 影响：只读排查；本机与远端均未改配置。
- 关键现象：
  - 到 `192.168.2.20` 的路由走 `utun4`（Tailscale 子网路由），不走本地默认网关。
  - `ping 100.124.140.78`：avg 约 `515 ms`，max 约 `1326 ms`，偶发 timeout 感（用户截图）。
  - `tailscale status`：`mssql-ref` / `pve` 均为 `active; relay "km"`。
  - `tailscale ping mssql-ref` / `pve`：全部 `via DERP(km)`，`direct connection not established`。
  - `tailscale netcheck`：`MappingVariesByDestIP: true`，`PortMapping` 空，Nearest DERP Kunming ~`113 ms`。
- 对照：PVE 宿主机同网段 ping `192.168.2.20` 仅约 `0.2 ms`；`mssql-ref` 上 SQL 服务与 guest 资源正常。详见 `docs/operations/pve.md` 同时间条目。
- 回滚：无变更。
- 恢复直连后自检：`tailscale ping mssql-ref` 应出现 direct 路径；再 `ping 100.124.140.78` / 连 `1433` 验证延迟是否回到正常。

## 2026-07-07 23:35 CST - 安装 actionlint 用于 GitHub Actions workflow 静态检查

- 原因：用户希望本机可直接检查 GitHub Actions workflow，例如 `frontend-mas/.github/workflows/sonar.yml` 的 shard / runner label 配置。
- 影响：
  - 通过 Homebrew 安装 `actionlint` 1.7.12。
  - Homebrew 同时安装依赖 `shellcheck` 0.11.0。
  - Homebrew 自动执行了一次 cleanup，清理本机 Homebrew 缓存和旧日志；未修改任何仓库文件。
- 回滚方式：
  - `brew uninstall actionlint`
  - 如不再需要 shell 脚本检查依赖，也可 `brew uninstall shellcheck`。
- 验证结果：
  - `actionlint -version` 返回 1.7.12。
  - 对 `frontend-mas/.github/workflows/sonar.yml` 执行 `actionlint -ignore 'label ".*" is unknown'` 通过。
- 注意事项：
  - 该仓库使用多个 self-hosted runner 自定义标签；裸跑 `actionlint` 会报 `mac-mini-sonar`、`lemon-imac`、`mas-go-dev`、`frontend-sonar-ci` 等 label unknown。若要把 actionlint 纳入常规检查，应在仓库内补 `actionlint.yaml` 声明自定义 runner labels，或在命令中忽略这类误报。

## 2026-07-04 15:40 CST - 定论：AFK auto-continue 触发条件是「终端失焦」而非「键盘空闲」，实测 180s 生效

- 原因：
  - 按 15:10 那条把配置改对（`askUserQuestionTimeout: 5m` + `CLAUDE_AFK_TIMEOUT_MS: 180000`）、并**新开会话**后，用户干等 4 分钟，AskUserQuestion 仍不自动继续，连倒计时横幅都不出现。
  - 一度怀疑「文件手写不生效 / schema 被 `.catch` 吞掉 / key 只能经 `/config` 写」。经排查全部证伪，最终定位到真正的触发条件与测试姿势有关。
- 影响：
  - 纯排查 + 结论沉淀，无配置改动（配置在 15:10 已定），本仓库仅追加本条记录。
- 做了什么（关键排查链）：
  1. **证实配置已读到**：`/config` 界面里 "Question auto-continue timeout" 显示为 `5m`（不是 `never`），说明手写到用户级 `~/.claude/settings.json` 顶层**已被 runtime 正确采纳**，功能开关是开的。→ 推翻了「手写无效 / Scope 只认 /config」的猜测。
  2. **证实 env 已注入**：当前新会话的子进程环境里 `CLAUDE_AFK_TIMEOUT_MS=180000`、`CLAUDE_AFK_COUNTDOWN_MS=60000` 均在。
  3. **反查二进制定位真因**：倒计时 hook `VFc({enabled,timeoutMs,...})` 的 `useEffect` 首行 `if(!e)return`；`enabled` 由 `askUserQuestionTimeout` 换算值（`5m`→300000，truthy）决定，确应启用。但计时推进依赖**空闲基准** `c.current`，组件内 `if(W2e()===true) c.current=当下`（聚焦即不断重置基准，计时永远归零）。
  4. **`W2e()` 的真身**：`W2e()=Hvr`，`Hvr` 由 `Pvr(e)` 设置，而唯一调用点是终端焦点事件处理器 `Pno(e){Dno=e?"focused":"blurred";Pvr(e)}`。即 **AFK 的「用户在场」判据 = 终端窗口是否聚焦，与键盘敲击无关**。另有 `_0()=qt.lastInteractionTime`、阈值 `Dun=60000` 作为兜底活跃判定。
  5. **按正确姿势重测**：弹出 AskUserQuestion 后**立即切走窗口让终端失焦**，不手动选择。
- 验证结果：
  - 失焦后计时正常推进，工具在 **180s** 返回 `No response after 180s — the user may be away from keyboard`，**自动继续成功**。180s 正是 `CLAUDE_AFK_TIMEOUT_MS=180000` 的值，证明它成功覆盖了 `5m` 档，且「demo/测试 override」在**交互式会话**里同样生效（前提是终端失焦）。
- 注意事项 / 复用经验：
  - **触发条件是「终端失去焦点」，不是「没敲键盘」**。人离开但窗口仍聚焦时，idle 基准被焦点状态持续重置，等再久也不触发、倒计时也不出——前两次测试失败的唯一原因就在此。验证或依赖此功能时，必须让 Claude Code 终端真正失焦（切到别的 App / 桌面）。
  - 若用 tmux / 部分终端复用器 / 某些 SSH 场景，xterm focus reporting（焦点上报）可能传不进来，`Pno` 收不到 blurred，这套 AFK 在那种环境下不会触发。本机原生终端切走窗口可正常上报失焦。
  - 前述 15:10 那条的配置方案（开关 + env 覆盖 + 倒计时提前量）经本次实测确认**完全正确**，无需再改。

## 2026-07-04 15:10 CST - 订正：AFK auto-continue 需用 askUserQuestionTimeout 开关，单设 CLAUDE_AFK_TIMEOUT_MS 无效

- 原因：
  - 用户实测反馈：按上一条（07-04 13:25）配置后，等待超过 4 分钟，AskUserQuestion 选择题仍不自动按默认项继续，即「3 分钟自动继续」功能根本没生效。
  - 复盘发现上一条的**核心结论错了**：当时以为「环境变量优先级高于设置项」，就把开关 `askUserQuestionTimeout` 删掉、只留 `env.CLAUDE_AFK_TIMEOUT_MS`。但在本机 v2.1.201 上，`CLAUDE_AFK_TIMEOUT_MS` **不是开关、只是时长**，开关没打开时它空转。
- 影响：
  - 修改本机个人全局配置 `/Users/konghai/.claude/settings.json`（**不在** Server 运维笔记仓库范围内，无 git 变更；本仓库仅追加本条时间线记录）。
  - 顶层新增 `askUserQuestionTimeout: "5m"`（打开 auto-continue 功能开关）。
  - `env` 内保留 `CLAUDE_AFK_TIMEOUT_MS: "180000"`（覆盖 `5m`，把实际等待精确压到 3 分钟，落在 5 分钟 prompt cache TTL 窗口内）。
  - `env` 内新增 `CLAUDE_AFK_COUNTDOWN_MS: "60000"`（超时前 60 秒开始显示倒计时横幅）。
- 回滚方式：
  - 删除顶层 `askUserQuestionTimeout` 与 `env` 里的 `CLAUDE_AFK_TIMEOUT_MS` / `CLAUDE_AFK_COUNTDOWN_MS` 三项，即恢复默认（v2.1.201 默认 `never` = 关闭 auto-continue）。
- 做了什么：
  1. 直接从本机 `claude` v2.1.201 二进制反查真实逻辑（`strings` + `grep -a`），确认三点：
     - 真正的开关是设置项 `askUserQuestionTimeout`（`/config` 里显示为 "Question auto-continue timeout"），枚举 `["never","60s","5m","10m"]`，**默认 `never`**。
     - 二进制内官方描述原文：`Defaults to never — auto-continue only runs when explicitly set to 60s/5m/10m.`；换算函数对 `never` 与「未设置」都返回 `null`（=功能不启用），此时倒计时组件根本不渲染。
     - 组件内时长解析为 `t = CLAUDE_AFK_TIMEOUT_MS ?? (askUserQuestionTimeout换算值) ?? 默认`，故功能一旦开启，`CLAUDE_AFK_TIMEOUT_MS` 在 `??` 链排第一，会**覆盖** `5m` 档；另有 `CLAUDE_AFK_COUNTDOWN_MS`（受 `Math.min(countdown, timeout)` 约束）控制倒计时提前量。
  2. 据此纠正上一条的选型：环境变量优先级确实更高，但它只在「功能已开启」之后才参与计算——**必须同时保留 `askUserQuestionTimeout` 非 `never` 作为开关**，不能只留环境变量。最终采用「`askUserQuestionTimeout: 5m` 开开关 + `CLAUDE_AFK_TIMEOUT_MS: 180000` 覆盖成 3 分钟」组合。
  3. 环境变量的值必须是**毫秒整数字符串**：`CLAUDE_AFK_COUNTDOWN_MS` 写 `"60000"` 而非 `"60s"`（代码不解析 `60s` 这种字符串，只有 `askUserQuestionTimeout` 那个枚举才接受档位字符串）。
- 验证结果：
  - `python3 -c "import json; json.load(open('~/.claude/settings.json'))"` 语法有效；`askUserQuestionTimeout = 5m`、`env` 含 `CLAUDE_AFK_TIMEOUT_MS=180000` + `CLAUDE_AFK_COUNTDOWN_MS=60000` 均已落盘。
  - 逻辑正确性由二进制反查佐证（开关 → 时长覆盖 → 倒计时三段链路），非仅凭文档推断。
- 注意事项：
  - 设置需**新开会话**才加载，当前会话仍是旧行为，实际「3 分钟自动继续 + 60 秒倒计时」要下次开会话验证。
  - 为何选 3 分钟而非 `5m` 档的深层原因（用户补充）：Claude 服务端 prompt cache TTL 为 5 分钟，若用 `5m` 档，每次 askUser 都恰好等满 5 分钟才自动继续，那一跳几乎必然 cache miss、重读整段上下文；压到 3 分钟可稳落在 TTL 窗口内、命中热缓存。这才是 `CLAUDE_AFK_TIMEOUT_MS` 覆盖 `5m` 的实际收益。
  - `CLAUDE_AFK_TIMEOUT_MS` 与用于倒计时提前量的 `CLAUDE_AFK_COUNTDOWN_MS` 是两个不同变量，勿混。

## 2026-07-04 13:25 CST - 配置 Claude Code AFK 超时为 3 分钟并加 AskUserQuestion 声音提醒 hook

- 原因：
  - `AskUserQuestion` 选择题默认无应答超时太短，无人值守时会卡住、有人值守时又想给足看题思考时间。
  - 希望 Claude 弹选择题时能播放声音，提醒用户回终端处理。
- 影响：
  - 修改本机个人全局配置 `/Users/konghai/.claude/settings.json`（**不在** Server 运维笔记仓库范围内，无 git 变更）。
  - 新增 `env.CLAUDE_AFK_TIMEOUT_MS = "180000"`（3 分钟），控制 AskUserQuestion 选择题无应答后自动按默认项继续的等待时长；只影响选择题，权限确认 / 计划审批不受它控制。
  - 新增 `PreToolUse` hook（matcher `AskUserQuestion`），每次弹选择题前播放 `firstblood.caf`；复用现成脚本 `/Users/konghai/hooks/play_completion_sound.sh`，与 Stop 完成音 `xm3828.mp3` 区分。
- 回滚方式：
  - 删除 `settings.json` 中的 `env.CLAUDE_AFK_TIMEOUT_MS`（恢复默认；本机为 v2.1.201，默认关闭 auto-continue）。
  - 删除 `PreToolUse` 里 matcher 为 `AskUserQuestion` 的 hook 块。
- 做了什么：
  1. 查官方文档确认 `CLAUDE_AFK_TIMEOUT_MS`（单位毫秒，需 v2.1.198+）与 `askUserQuestionTimeout`（枚举 `never/60s/5m/10m`，需 v2.1.200+）；本机 v2.1.201 均满足。
  2. 选型：`askUserQuestionTimeout` 缺 `3m` 档，`5m` 会必然击穿 5 分钟 prompt cache TTL（无人值守时每次 askUser 都等满 5m→冷启动，又慢又贵），`60s` 又太急看不完题；最终用 `env + CLAUDE_AFK_TIMEOUT_MS = 180000` 精确取 3 分钟（3min < 5min TTL，不必然击穿缓存）。环境变量优先级高于设置项，故同时删掉先前误加的 `askUserQuestionTimeout` 避免误导。
  3. 声音 hook 选型：Claude Code 无 `AskUserQuestion` 专属 hook 事件；实测 `PreToolUse + matcher=AskUserQuestion` 能精准命中弹窗（证明 AskUserQuestion 确是工具，可被 PreToolUse 捕获，纠正了「它只是 UI 交互、抓不到」的说法）。未用语义更泛的 `Notification`（实测其 `notification_type=permission_prompt` 是权限确认触发，会误响）。
  4. 用临时探针 hook（写 `/tmp/hook-probe.log`）实测验证命中后，换成正式播放声音；用户试听候选音效后选定 `firstblood.caf`。
- 验证结果：
  - `python3 -m json.tool settings.json` 语法有效。
  - 探针日志证实弹 AskUserQuestion 时 `PreToolUse matcher=AskUserQuestion FIRED` 命中。
  - 当场多次调 AskUserQuestion，用户确认能听到 `firstblood.caf` 提醒音，hook 工作正常。
- 注意事项：
  - 声音 hook 为动态生效（当前会话即触发）；但 `env.CLAUDE_AFK_TIMEOUT_MS` 需**新开会话**才加载，当前会话仍是旧行为。
  - 3 分钟只是「不必然」击穿缓存：若弹窗前那次请求已用掉 TTL 里三四分钟，叠加 3min 等待仍可能越过 5min 线；彻底根治方向是无人值守长任务事先用 plan mode 敲定方案、不产生 askUser 决策点。

## 2026-07-02 00:56 CST - 安装 Apple container 并验证 daohen-diary 容器化兼容性

- 原因：用户希望在本机安装 Apple 开源项目 `apple/container`，并评估 `/Users/konghai/Code_local/Project/daohen-diary` 是否可用它部署。
- 影响：
  - 本机安装 `container` CLI 1.0.0 到 `/usr/local/bin/container`，同时安装 `/usr/local/bin/update-container.sh` 与 `/usr/local/bin/uninstall-container.sh`。
  - 启动 Apple `container` system service，应用数据目录为 `/Users/konghai/Library/Application Support/com.apple.container/`。
  - 首次启动时安装默认 kernel：`vmlinux-6.18.15-186`。
  - 测试过程中拉取/构建了若干本机镜像：`alpine:latest`、`daohen-backend:local`、`daohen-frontend:local`、`golang:1.22-bookworm`、`debian:bookworm-slim`、`node:20-alpine`、`nginx:1.27-alpine`。
  - 未改动生产服务器；未改动本运维仓库以外的服务器环境。
- 回滚方式：
  - 停止 system service：`container system stop`。
  - 保留用户数据卸载：`/usr/local/bin/uninstall-container.sh -k`。
  - 删除用户数据卸载：`/usr/local/bin/uninstall-container.sh -d`。
  - 如只清理测试镜像/容器，可用 `container rm`、`container image rm`、`container prune` 按需删除。
- 做了什么：
  1. 确认本机满足官方要求：Apple Silicon，macOS 26.5.1，Homebrew 已安装；本运维仓库当前在 `main` 分支且工作区干净。
  2. 从 GitHub Release 下载官方签名安装包 `container-1.0.0-installer-signed.pkg`。
  3. 校验安装包 SHA-256：`13f45f26da94c354adcbefe1e8f7631e7f126e93c5d4dd6a5a538aa66b4f479d`，与 GitHub Release asset digest 一致。
  4. 用 `pkgutil --check-signature` 验证安装包由 `Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)` 签名，且 Apple notarization 可信。
  5. 通过 macOS 图形安装器完成安装；随后执行 `container system start`，按提示安装默认 kernel。
  6. 用 `container run --rm docker.io/library/alpine:latest echo container-ok` 验证基础镜像拉取与容器执行链路。
  7. 检查 `daohen-diary`：项目是 Go 后端 + Svelte/nginx 前端 + SQLite，已有 `Dockerfile`、`Dockerfile.frontend`、`docker-compose.yml`。
  8. 发现 `daohen-diary` 后端 `Dockerfile` 写死 `GOARCH=amd64`，Apple `container` 在本机默认以 `linux/arm64` 运行，直接启动时报 `Exec format error`；加 `--rosetta` 可临时运行，但不是原生方案。
  9. 临时修改 `daohen-diary/Dockerfile` 改用 `TARGETOS` / `TARGETARCH` 后重新构建，确认 Apple `container build` 产物为 `GOARCH=arm64`，不加 `--rosetta` 可启动后端并访问 `/api/health`。
  10. 构建前端镜像成功，但完整模拟 Compose 时，前端 nginx 的 `proxy_pass http://backend:8080/api/` 在 Apple `container` 网络内无法解析 `backend`，nginx 启动失败；说明 Apple `container` 不能直接等价替代 `docker compose up`。
  11. 按用户要求清理测试后端相关容器和测试网络；保留 Apple `container` builder。
- 验证结果：
  - `container --version`：`container CLI version 1.0.0 (build: release, commit: ee848e3)`。
  - `container system status`：`status running`，`apiserver.version container-apiserver version 1.0.0`。
  - Alpine 最小容器输出 `container-ok`。
  - `daohen-diary` 后端在修正架构构建后，`curl http://127.0.0.1:18081/api/health` 返回 `{"ok":true}`。
  - `daohen-diary/backend` 执行 `go test ./...` 通过。
  - 清理后 `container ls -a` 仅剩 Apple `container` 的 `buildkit` builder 容器运行。
- 结论：
  - Apple `container` 已可在本机使用，适合运行单容器或手工编排的 OCI 镜像。
  - `daohen-diary` 后端经过 Dockerfile 架构修正后可用 Apple `container` 原生运行。
  - `daohen-diary` 现有双容器部署仍以 Docker Compose 为准；若要正式支持 Apple `container`，需补充专用启动脚本，并处理前端到后端的服务发现 / nginx upstream 配置。

## 2026-06-10 22:35 CST

- 原因：本机注册 runner 后运行 CI job 时 CPU 满载发热，用户合盖使用，担心高温烫坏屏幕；且本机 label 已与 mac-mini 漂移（mac-mini 的 4 个 runner 第四 label 已是 `backend-ci`，本机仍是 `macbook` 且注册时用 `--no-default-labels` 去掉了 `self-hosted`，导致接不到改用 `runs-on: [self-hosted, backend-ci]` 的 backend CI job，分担队列的初衷已基本失效）。综合决定彻底下线本机 runner。
- 影响：org `cypressoai` 移除 self-hosted runner `macbook-1`；本机不再承接任何 CI job，CI 全部回落到 mac-mini（`mac-mini-sonar-1~4`）/ EC2 / `mas-go-dev` 等 runner；本机不再因 CI 发热。
- 回滚方式：如需重新上线，重新下载 runner 解压、`gh api -X POST orgs/cypressoai/actions/runners/registration-token` 取注册 token、`./config.sh` 注册到 org（**这次不要再用 `--no-default-labels`**，并把 label 对齐到 backend CI 共享池所需的 `self-hosted,backend-ci`，否则仍领不到 job）。
- 做了什么：
  1. `cd ~/actions-runner/macbook-1 && ./svc.sh stop` 停服务（Stopped）。
  2. `./svc.sh uninstall` 卸载 LaunchAgent（中途报 `Unload failed: 5: Input/output error`，因服务已先停、属无害报错；`launchctl list` 已无该服务、plist 文件已删，确认卸载成功）。
  3. `gh api -X POST orgs/cypressoai/actions/runners/remove-token` 取注销 token，`./config.sh remove --token <token>` 从 org 注销（Runner removed，`.credentials`/`.runner` 已清）。
  4. 清理 runner 目录：`~/actions-runner/macbook-1`（含 work 目录大量小文件，`rm -rf` 卡约 20 秒属正常）已删；`~/gha/m1` 删一半被 Ctrl+C 打断后，用户在访达内手动删除剩余 runner 缓存（`_PipelineMapping`/`_tool`/`iCare-frontend-mas`，均为 runner 工作缓存，非个人文件）。
- 验证结果：`gh api orgs/cypressoai/actions/runners` 列表已无 `macbook-1`；`~/actions-runner`、`~/gha` 两目录均 `No such file or directory`，已清空；家目录个人文件完好，未误删。
- 注意事项：macOS 默认无系统级文件删除审计日志（未开 `auditd`），删除是直接 unlink；本次删除参数写死两个 runner 专属路径、无通配符，不会波及个人文件。

## 2026-06-10 18:05 CST

- 原因：CI 队列大量积压，mac-mini 4 个 runner 不够消化；本机（MacBook Air M5，10 核 / 32GB / arm64）CPU 大多数时候空闲，注册为补充 runner 分担队列。
- 影响：org `cypressoai` 新增 self-hosted runner `macbook-1`，label 为 `mac-mini-sonar, macos, arm64, macbook`（与 mac-mini 4 个 runner 共享前三个 label，因此会领取同一队列的 job）；CI job 会在本机执行，占用本机 CPU / 磁盘。合盖或断网时 runner 掉线，job 回到队列由 mac-mini 接手。
- 回滚方式：`cd ~/actions-runner/macbook-1 && ./svc.sh stop` 临时下线；彻底移除执行 `./svc.sh uninstall`，再用 `gh api -X POST orgs/cypressoai/actions/runners/remove-token --jq .token` 取 token 后执行 `./config.sh remove --token <token>`。
- 做了什么：下载 runner v2.335.1 解压到 `~/actions-runner/macbook-1/`；用 `gh auth refresh -s admin:org` 提权后通过 API 取注册 token；`./config.sh` 注册到 org `cypressoai`，`--no-default-labels`，workFolder 用短路径 `/Users/konghai/gha/m1`（避免 mac-mini 2026-06-09 踩过的 GNUPGHOME 路径过长问题）；确认 `.path` 已含 `/opt/homebrew/bin`（gpg 可用）；`./svc.sh install && ./svc.sh start` 装成 LaunchAgent 开机自启。
- 验证结果：GitHub API 显示 `macbook-1 [online] busy=true`，启动后立即领取了排队 job；`launchctl` 服务 `actions.runner.cypressoai.macbook-1` Started（退出码 0）。
- 注意事项：MacBook Air 无风扇，长时间满载会热降频，定位为分担队列的补充 runner；`pmset` 显示 `sleep 0` 不会自动休眠，但合盖会掉线。

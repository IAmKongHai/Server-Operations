# tk-flywheel CI

2026-09-16 按用户确认，在 mas-go-dev 新增仓库级 runner 和固定 CI 数据库。配置 PR：[IAmKongHai/tk-flywheel#3](https://github.com/IAmKongHai/tk-flywheel/pull/3)。

## Runner

| 项目 | 配置 |
| --- | --- |
| 名称 / GitHub ID | `mas-go-dev-tk-flywheel-ci-1` / `2` |
| 范围 | 私有仓库 `IAmKongHai/tk-flywheel` |
| Labels | `self-hosted`, `Linux`, `X64`, `tk-flywheel-ci` |
| 系统用户 | `tk-flywheel-ci`；无 sudo / Docker 组权限 |
| systemd | `actions.runner.IAmKongHai-tk-flywheel.mas-go-dev-tk-flywheel-ci-1.service` |
| 程序 | `/opt/tk-flywheel-ci/runner`，初装 2.337.0，官方包 SHA-256 已校验 |
| 工作区 / 缓存 | `/opt/tk-flywheel-ci/work` / `/opt/tk-flywheel-ci/cache` |
| 资源 | CPUQuota 200%，MemoryHigh 2560M，MemoryMax 3G，TasksMax 512 |

一个 slot 串行承接 Backend、frontend、extension、agent 四个 job。现有 iCare / shared-sit runner 不添加新 label，也不承担这个个人仓库的任务。

[runner-override.conf](runner-override.conf) 对应 `/etc/systemd/system/<上述服务名>.d/override.conf`；[runner.env](runner.env) 为追加到程序目录 `.env` 的缓存与并发配置，保留安装器原有环境。服务通过 `EnvironmentFile` 加载。Go 编译最多 2 路；npm 和 Go 使用独立持久缓存，GitHub 缓存关闭。`.env` 中没有数据库密码。

## PostgreSQL

- 复用 `shared-sit-postgres` PostgreSQL 18.6，入口 `127.0.0.1:5432`。
- 固定数据库和 LOGIN 角色均为 `tk_flywheel_ci`，数据库 owner 为 `postgres`，各设连接上限 12。
- CI 角色无超级用户 / 建库 / 建角色 / 复制 / 绕过 RLS 权限；只授目标库 `CONNECT, CREATE, TEMPORARY`。目标库和 `public` schema 已撤销 PUBLIC 权限。
- 角色默认 `statement_timeout=30s`、`lock_timeout=5s`、`idle_in_transaction_session_timeout=30s`。
- root 专用目录 `/opt/shared-sit/tk-flywheel-ci/` 为 700，`credentials.env` 为 600。连接串同时存 GitHub Actions Secret `CI_DATABASE_URL`，仅 Backend job 使用。
- 每次测试创建随机 `test_*` schema，正常退出时删除。库长期保留；强制取消 / OOM / 超时杀进程可能留下 schema，清理前检查活动连接、owner 和具体 schema，不能批量清空数据库或业务表。

缺少 Secret 时 workflow 直接失败，避免 Go 测试跳过数据库覆盖却让 CI 显示成功。该 runner 只执行可信仓库代码；系统用户与数据库权限隔离不等于虚拟机隔离。

## 只读检查

```bash
gh api repos/IAmKongHai/tk-flywheel/actions/runners --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
ssh mas-go-dev 'sudo systemctl status actions.runner.IAmKongHai-tk-flywheel.mas-go-dev-tk-flywheel-ci-1.service --no-pager'
ssh mas-go-dev 'sudo du -sh /opt/tk-flywheel-ci/cache; free -h'
```

## 首轮验证

[CI 34997551965](https://github.com/IAmKongHai/tk-flywheel/actions/runs/34997551965) 四个 job 全部通过，均使用此 runner。数据库集成测试实际执行且通过；测试后随机 schema 和 CI 连接均为 0。原有容器启动时间未变化；runner 峰值内存约 1.53 GiB，无 OOM。PR 尚未合并，main 配置待合并生效。

## 备份与回滚

建库、装 runner 前的备份：`/opt/shared-sit/backups/tk-flywheel-ci-20260916-0041`（root 700）。含 PostgreSQL globals、原有三个库的 schema、共享 PostgreSQL Compose、原 runner 服务配置、容器启动时间与资源快照；globals 含凭据，文件均为 600，不能提交。此备份用于还原配置与权限依据，不是业务数据全量备份。

回滚 CI 配置可还原 tk-flywheel 的 workflow；确认新 runner 没有 job 后，经授权仅停止并禁用上述新 systemd 服务。不要停止共享 PostgreSQL 或其他 runner。保留 CI 数据库、角色、缓存和备份；若要彻底删除，需另行确认。修改本机 runner 配置前，先备份现有 `.env` 和 override。

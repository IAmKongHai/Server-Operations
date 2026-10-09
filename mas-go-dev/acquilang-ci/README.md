# AcquiLangAI CI

2026-10-10 在 mas-go-dev 增加一个仓库级 runner，分担 mac-mini 上的 AcquiLang 日常检查。

## Runner

| 项目 | 配置 |
| --- | --- |
| 名称 / GitHub ID | `mas-go-dev-acquilang-ci-1` / `27` |
| 范围 | 私有仓库 `IAmKongHai/AcquiLangAI` |
| Labels | `self-hosted`, `Linux`, `X64`, `acquilang-build` |
| 系统用户 | `acquilang-ci`；无 sudo / Docker 组权限 |
| systemd | `actions.runner.IAmKongHai-AcquiLangAI.mas-go-dev-acquilang-ci-1.service` |
| 程序 / 工作区 | `/opt/acquilang-ci/runner` / `/opt/acquilang-ci/work` |
| 缓存 | `/opt/acquilang-ci/cache/pnpm-store`、`/opt/acquilang-ci/cache/npm` |
| 资源 | CPUQuota 200%，MemoryHigh 1536M，MemoryMax 2G，TasksMax 512 |
| Python | 系统 `/usr/bin/python3.12`（3.12.12） |
| pnpm | `pnpm/action-setup` 自带的 pnpm 11 需要系统包 `libatomic`（`libatomic.so.1`） |
| runner 包 | `actions-runner-linux-x64-2.337.0`，SHA-256 `70920811a4f8ad4328818682bca5c6469c1c942fab52448868071d0063816613` |

一个 slot。backend、admin、web 和 CI 汇总使用 `acquilang-build`，可以落在这台机器或 mac-mini 的 `ci-1` … `3`。native 额外要求 `macos` 和 `arm64`：jest-expo 的邮箱验证门禁用例在 Linux 上 `render` 起不来。Sonar 仍要求 `macos` + `arm64` + `acquilang-ci`，因为后端测试库在 mac-mini 的 localhost。现有 iCare / shared-sit / tk-flywheel runner 不添加这个 label。

[runner-override.conf](runner-override.conf) 对应 `/etc/systemd/system/<服务名>.d/override.conf`。`.env` 只有语言和 pnpm / npm 缓存路径，没有数据库密码。

## 只读检查

```bash
gh api repos/IAmKongHai/AcquiLangAI/actions/runners --jq '.runners[] | select(.name|startswith("mas-go-dev-acquilang"))'
ssh mas-go-dev 'systemctl status actions.runner.IAmKongHai-AcquiLangAI.mas-go-dev-acquilang-ci-1.service --no-pager'
```

## 回滚

确认没有 job 后，只停止并禁用上述 systemd 服务。不要停止共享 PostgreSQL、SIT 容器或其他 runner。注册、目录和缓存先留着；要彻底删除需另行确认。

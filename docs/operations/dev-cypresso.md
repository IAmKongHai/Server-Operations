# dev-cypresso 运维时间线

## 2026-05-19 10:03 CST - 记录 nginx 安全升级待办

- 服务器：`dev-cypresso`
- 操作人：`Codex`
- 原因：近期 nginx 披露 `CVE-2026-42945` 等安全问题，需要确认 `dev-cypresso` 是否需要升级。
- 影响：本次只读检查和记录 TODO，未修改服务器配置，未升级软件，未 reload/restart nginx。
- 当前状态：
  - OS：Amazon Linux 2023
  - nginx：`nginx/1.28.2`，RPM 为 `nginx-1.28.2-1.amzn2023.0.1`
  - `nginx.service`：`active (running)`
  - `nginx -t`：通过，但存在既有 warning：`conflicting server name "_" on 0.0.0.0:80, ignored`
  - ASLR：`/proc/sys/kernel/randomize_va_space=2`
- 风险判断：
  - nginx 官方安全公告显示 `CVE-2026-42945` 的修复边界是 `1.30.1+` 或 `1.31.0+`，当前 `1.28.2` 在受影响版本范围内。
  - AWS CVE Explorer 中 Amazon Linux 2023 的 `nginx / CVE-2026-42945` 状态仍是 `Pending Fix`。
  - Amazon Linux 2023 官方仓库当前只提供到 `1.28.2-1.amzn2023.0.1`，没有可直接 `dnf update nginx` 的修复包。
  - nginx.org 官方 Amazon Linux 2023 stable 仓库已有 `1.30.1`，但 dnf 模拟安装失败，因为包依赖 `libssl.so.3(OPENSSL_3.5.0)`，而当前系统 OpenSSL 是 `3.2.2`。
- 配置观察：
  - `/etc/nginx/conf.d/mas-icare.cypress.sg.conf` 中有一条 `rewrite ^/api/(.*)$ /api/$1 break;`，使用了 `$1`。
  - 这条 rewrite 没有 `?`，不完全命中 `CVE-2026-42945` 描述里的典型触发条件，但后续建议改成 named capture 降低暴露面。
- 回滚：本次没有做服务器变更，无需回滚。
- TODO：
  - [ ] 过几天复查 Amazon Linux 2023 是否发布 nginx 修复包；如果已发布，优先走 Amazon 官方仓库升级。
  - [ ] 复查 nginx.org `1.30.1` 或更新包是否仍依赖 OpenSSL 3.5；不要为了 nginx 单独升级系统 OpenSSL，除非有明确兼容性方案。
  - [ ] 如官方修复仍未发布，考虑先备份并修改 `mas-icare.cypress.sg.conf`，把 `$1` rewrite 改为 named capture 后执行 `nginx -t && systemctl reload nginx`。
  - [ ] 修复完成后补一篇 `docs/solutions/dev-cypresso/security-issues/` 文档，记录 nginx CVE 处置方案。

## 2026-05-19 09:42 CST - 停止已迁出服务相关 Docker 容器

- 服务器：`dev-cypresso`
- 操作人：`Codex`
- 原因：部分服务已迁出 `dev-cypresso`，需要停止原服务器上的遗留容器，并确保服务器重启后这些容器不会自动启动。
- 影响：以下容器对应服务在 `dev-cypresso` 上停止；容器、镜像、数据卷均未删除。
- 回滚：

```bash
ssh dev-cypresso 'docker start shared-mongodb shared-clickhouse shared-rabbitmq cypresso-ui-web cypresso-api cypresso-doc hr-icare-portal'
```

如后续确认仍需随服务器启动自动拉起，再恢复 restart policy：

```bash
ssh dev-cypresso 'docker update --restart=unless-stopped shared-mongodb shared-clickhouse shared-rabbitmq cypresso-ui-web cypresso-api cypresso-doc hr-icare-portal'
```

### 变更

- 目标容器来自用户确认的编号：`1, 4, 5, 10, 11, 12, 13, 14`。
- 编号 `1` 对应的临时 buildx 容器 `buildx_buildkit_builder-93669b86-1e97-4178-9c2f-ec3ed32ed5690` 在操作前已不存在于 `docker ps -a`，未执行停止。
- 对以下容器执行 `docker update --restart=no`，防止服务器重启后自动启动：
  - `shared-mongodb`
  - `shared-clickhouse`
  - `shared-rabbitmq`
  - `cypresso-ui-web`
  - `cypresso-api`
  - `cypresso-doc`
  - `hr-icare-portal`
- 随后对上述容器执行 `docker stop`。

### 操作前状态

```text
/shared-mongodb       Status=running  Restart=unless-stopped  Image=mongodb/mongodb-atlas-local:8.0
/shared-clickhouse    Status=running  Restart=unless-stopped  Image=clickhouse/clickhouse-server:25.3
/shared-rabbitmq      Status=running  Restart=unless-stopped  Image=rabbitmq:4.2.3-management
/cypresso-ui-web      Status=running  Restart=unless-stopped  Image=cypresso-ui:latest
/cypresso-api         Status=running  Restart=unless-stopped  Image=cypresso-api:latest
/cypresso-doc         Status=running  Restart=unless-stopped  Image=cypresso-doc:latest
/hr-icare-portal      Status=running  Restart=unless-stopped  Image=icare-hr-portal
```

### 验证结果

目标容器停止后状态：

```text
/shared-mongodb       Status=exited  Restart=no
/shared-clickhouse    Status=exited  Restart=no
/shared-rabbitmq      Status=exited  Restart=no
/cypresso-ui-web      Status=exited  Restart=no
/cypresso-api         Status=exited  Restart=no
/cypresso-doc         Status=exited  Restart=no
/hr-icare-portal      Status=exited  Restart=no
```

操作后仍在运行的容器：

```text
icare-backend-api-1    Up, healthy
mas-icare-portal       Up
telegram-bot-bot-1     Up
shared-postgres        Up, healthy
shared-redis           Up, healthy
shared-sqlserver       Up
```

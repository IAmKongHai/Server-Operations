# dev-cypresso

iCare 项目集成测试服务器。AWS EC2 上的 Amazon Linux，登录用户 `ec2-user`。

虽然是测试环境，iCare 团队日常在用，破坏性操作前仍需先通知或备份。

2026-08-18 起，公网 MAS / HR / MAP SIT 入口已改为静态说明页，引导访问 UAT。门户容器未停。APK 下载地址不变。

## 连接

```bash
ssh dev-cypresso
```

公网 IP：`32.192.186.193`（见 `~/.ssh/config`）。

## 发布 iCare preview APK

公网下载：`https://mas-icare.cypress.sg/apk/icare-preview.apk`（SIT 站点关闭后仍可用）  
线上路径：`/var/www/mas-icare.cypress.sg/apk/icare-preview.apk`

把仓库根目录的 `icare-preview.apk` 一键替换到线上：

```bash
# 默认上传仓库根目录 ./icare-preview.apk
./scripts/deploy-icare-preview-apk.sh

# 或指定路径
./scripts/deploy-icare-preview-apk.sh /path/to/icare-preview.apk

# 可选：保留线上旧文件为 .bak.<timestamp>
KEEP_BACKUP=1 ./scripts/deploy-icare-preview-apk.sh
```

## 公网站点

宿主 Nginx 1.28 反代，证书由 certbot 签发自动续期。vhost 在 `/etc/nginx/conf.d/`。

| 域名                | 用途                 | 反代目标           | 仓库内对照                |
| ------------------- | -------------------- | ------------------ | ------------------------- |
| `zzz.konghai.me`    | new-api（AI 网关）   | `127.0.0.1:3000`   | [`new-api/`](./new-api/)  |
| `sub2api.cypresso.ai` | Sub2API（AI 网关） | `127.0.0.1:18180`  | [`sub2api/`](./sub2api/)  |

> 本表暂只列 new-api。同机还有 `t.moospark.com`（moo-ticket）、`evp.moospark.com` /
> `evp-admin.moospark.com`（EVP）等既有站点，待后续补齐。

## 共享基础设施栈

位置：`/home/ec2-user/stacks/infra/`，由一份 `docker-compose.yml` 编排。

| 服务            | 容器名              | 镜像                                           | 端口（仅 `127.0.0.1`） |
| --------------- | ------------------- | ---------------------------------------------- | --------------------- |
| SQL Server      | `shared-sqlserver`  | `shared-sqlserver-fts:2017-cyp327`（自构建）   | `1433`                |
| MongoDB Atlas   | `shared-mongodb`    | `mongodb/mongodb-atlas-local:8.0`              | `27017`               |
| RabbitMQ        | `shared-rabbitmq`   | `rabbitmq:4.2.3-management`                    | `5672`, `15672`       |
| PostgreSQL      | `shared-postgres`   | `postgres:18`                                  | `5432`                |
| ClickHouse      | `shared-clickhouse` | `clickhouse/clickhouse-server:25.3`            | `8123`, `9001`        |
| Redis           | `shared-redis`      | `redis:8.4`                                    | `6379`                |
| SonarQube       | `sonarqube`         | `sonarqube:26.3.0.120487-community`            | `9000`                |

所有端口都绑 `127.0.0.1`，外部只能通过 SSH 隧道访问。

租户库（各项目在 `shared-postgres` 上独立建库建角色，不共用管理员账号）：

| 库           | 角色           | 使用方                        |
| ------------ | -------------- | ----------------------------- |
| `new_api`    | `new_api`      | new-api（`zzz.konghai.me`）   |
| `sub2api`    | `sub2api`      | Sub2API（`sub2api.cypresso.ai`） |
| `moo_ticket` | `moo_ticket`   | moo-ticket（`t.moospark.com`）|
| `evp`        | `evp`          | EVP                           |

> 注意：目前 `new_api`、`sub2api` 与 `evp` 三个库 `REVOKE CONNECT FROM PUBLIC`，
> 其余库任何已认证角色都能连上。新建库时记得一并收紧。

## SQL Server 容器细节

- **版本**：SQL Server 2017 Developer Edition，build `14.0.3520.4`（RTM-CU31-GDR, KB5077471, 2026-02-13）
- **特性**：装了 `mssql-server-fts`（全文检索）
- **基础镜像**：`mcr.microsoft.com/mssql/server:2017-latest`，在其上 `apt-get install mssql-server=14.0.3520.4-1 mssql-server-fts=14.0.3520.4-1`
- **Dockerfile**：`/home/ec2-user/stacks/infra/mssql-fts/Dockerfile`
- **数据卷**：`shared_sqlserver_data` → `/var/opt/mssql`
- **restart**：`unless-stopped`
- **PID**：Developer Edition
- **凭据**：见 [`secrets.local.md`](./secrets.local.md)（本地，未入库）

## 常用查询

```bash
# 版本
ssh dev-cypresso 'docker exec shared-sqlserver /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P "<SA 密码，见 secrets.local.md>" \
  -Q "SELECT @@VERSION"'

# 当前所有数据库
ssh dev-cypresso 'docker exec shared-sqlserver /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P "<...>" \
  -Q "SELECT name, state_desc FROM sys.databases"'
```

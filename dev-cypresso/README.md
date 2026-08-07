# dev-cypresso

iCare 项目集成测试服务器。AWS EC2 上的 Amazon Linux，登录用户 `ec2-user`。

虽然是测试环境，iCare 团队日常在用，破坏性操作前仍需先通知或备份。

## 连接

```bash
ssh dev-cypresso
```

公网 IP：`32.192.186.193`（见 `~/.ssh/config`）。

## 发布 iCare preview APK

公网下载：`https://mas-icare.cypress.sg/apk/icare-preview.apk`  
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

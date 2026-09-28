# sub2api @ dev-cypresso 对照

以服务器 `/home/ec2-user/stacks/sub2api/` 为准。本目录只放不含密钥的对照副本。

入口：`https://sub2api.cypresso.ai`（宿主 Nginx 反代到 `127.0.0.1:18180`，Let's Encrypt 证书）

镜像钉 `weishaw/sub2api:0.2.9`。全新空库，不从 mac-mini 迁数据。

## 组件

| 组件 | 说明 |
| --- | --- |
| `sub2api` 容器 | 镜像钉 `weishaw/sub2api:0.2.9`，只绑 `127.0.0.1:18180` |
| `sub2api-redis` 容器 | 专用 Redis，带密码 + AOF，不发布宿主端口，不复用 `shared-redis` |
| 数据库 | 复用 infra 栈的 `shared-postgres`（PostgreSQL 18）上的独立库 `sub2api` + 同名角色 |
| 反代 | 宿主 Nginx 1.28，vhost `/etc/nginx/conf.d/sub2api.cypresso.ai.conf` |
| 备份 | `sub2api-backup.timer` 每日 04:20 UTC，`pg_dump -Fc` 到 `/home/ec2-user/backups/sub2api/`，保留 14 份 |

## 文件对照

| 本目录 | 服务器 |
| --- | --- |
| `docker-compose.yml` | `/home/ec2-user/stacks/sub2api/docker-compose.yml` |
| `.env.example` | `/home/ec2-user/stacks/sub2api/.env`（600，含真实密钥） |
| `nginx/sub2api.cypresso.ai.conf` | `/etc/nginx/conf.d/sub2api.cypresso.ai.conf` |
| `systemd/sub2api-backup.sh` | `/home/ec2-user/stacks/sub2api/sub2api-backup.sh`（750） |
| `systemd/sub2api-backup.{service,timer}` | `/etc/systemd/system/` |

真实密钥只在服务器 600 权限文件与本地 gitignore 的 `dev-cypresso/secrets.local.md`。

## 注意

- 该机没有 `docker compose` 插件，只能用独立二进制 `docker-compose`（v2.24.5）。
- `shared-postgres` 属于 infra 栈：只在其上执行 sub2api 自己的库/角色 DDL，不改 `stacks/infra/` 任何文件，不在该目录 `up -d`。
- `JWT_SECRET` 与 `TOTP_ENCRYPTION_KEY` 首次部署即固定。轮换 JWT 会踢掉登录；轮换 TOTP 密钥会让已绑定的双因素认证失效。
- 数据卷 `sub2api_data` 挂在 `/app/data`，里面是应用写出的 `config.yaml`。删卷等于丢掉这份运行配置，库本身还在 `shared-postgres`。

## 回滚

```bash
cd /home/ec2-user/stacks/sub2api
docker-compose down          # 不要带 -v，卷里是 Redis AOF 和应用 config
                             # 也不要带 --remove-orphans
sudo rm /etc/nginx/conf.d/sub2api.cypresso.ai.conf
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl disable --now sub2api-backup.timer
# 库与角色 DROP、certbot delete、DNS 记录删除需另行确认
```

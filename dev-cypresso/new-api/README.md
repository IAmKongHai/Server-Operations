# new-api @ dev-cypresso 对照

以服务器 `/home/ec2-user/stacks/new-api/` 为准。本目录只放不含密钥的对照副本。

入口：`https://zzz.konghai.me`（宿主 Nginx 反代到 `127.0.0.1:3000`，Let's Encrypt 证书）

## 组件

| 组件 | 说明 |
| --- | --- |
| `new-api` 容器 | 镜像钉 `calciumion/new-api:v1.0.0-rc.37`，只绑 `127.0.0.1:3000` |
| `new-api-redis` 容器 | 专用 Redis，带密码 + AOF，不发布宿主端口，不复用 `shared-redis` |
| 数据库 | 复用 infra 栈的 `shared-postgres`（PG 18.3）上的独立库 `new_api` + 同名角色 |
| 反代 | 宿主 Nginx 1.28，vhost `/etc/nginx/conf.d/zzz.konghai.me.conf` |
| 备份 | `new-api-backup.timer` 每日 04:10 UTC，`pg_dump -Fc` 到 `/home/ec2-user/backups/new-api/`，保留 14 份 |

## 文件对照

| 本目录 | 服务器 |
| --- | --- |
| `docker-compose.yml` | `/home/ec2-user/stacks/new-api/docker-compose.yml` |
| `.env.example` | `/home/ec2-user/stacks/new-api/.env`（600，含真实密钥） |
| `nginx/zzz.konghai.me.conf` | `/etc/nginx/conf.d/zzz.konghai.me.conf` |
| `systemd/new-api-backup.sh` | `/home/ec2-user/stacks/new-api/new-api-backup.sh`（750） |
| `systemd/new-api-backup.{service,timer}` | `/etc/systemd/system/` |

真实密钥只在服务器 600 权限文件与本地 gitignore 的 `dev-cypresso/secrets.local.md`。

## 注意

- 该机**没有** `docker compose` 插件，只能用独立二进制 `docker-compose`（v2.24.5）。
- `shared-postgres` 属于 infra 栈：只在其上执行 new-api 自己的库/角色 DDL，不改 `stacks/infra/` 任何文件，不在该目录 `up -d`。
- 改 `.env` 会触发容器 recreate（既有复盘：`docs/solutions/dev-cypresso/integration-issues/docker-compose-env-file-edit-triggers-recreate-2026-05-28.md`），不是问题但要预期到。
- `SESSION_SECRET` 与 `CRYPTO_SECRET` 首次部署即固定：轮换 `CRYPTO_SECRET` 会让已保存的上游渠道密钥无法解密。
- 未挂 `/data` 卷，文件日志留在容器写层，随重建清零。

## 回滚

```bash
cd /home/ec2-user/stacks/new-api
docker-compose down          # 不要带 -v，卷里是 Redis AOF
                             # 也不要带 --remove-orphans
sudo rm /etc/nginx/conf.d/zzz.konghai.me.conf
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl disable --now new-api-backup.timer
# 库与角色 DROP、certbot delete、Cloudflare 记录删除需另行确认
```

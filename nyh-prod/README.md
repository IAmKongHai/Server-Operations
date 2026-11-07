# nyh-prod 服务器档案

运维时间线见 `docs/operations/nyh-prod.md`。这里只放长期有效的公共设施说明与登记表。

## 共享 Redis：`shared-redis`

2026-11-07 起，供 nyh-prod 上各项目共用（第一个接入方是 `nyh-wechat-mp`）。本仓库负责它的升级、登记表和备份策略。

| 项 | 值 |
| --- | --- |
| 容器 | `shared-redis`，镜像 `redis:7.4.12`（固定小版本），`--restart=always`，`--memory=256m --memory-swap=256m`，日志 10m×3 |
| 运行身份 | 宿主机专用系统用户 `shared-redis`（`--user` 运行；不要用镜像默认的 uid 999，它在这台机器上是 `nyh-notify`） |
| 端口 | 只绑 `127.0.0.1:6379`（宝塔自带 Redis 在 7480，与此无关） |
| 目录 | `/www/docker/shared-redis/`（root 700）：`data/`（RDB）、`conf/redis.conf`、`conf/users.acl`、`.admin_pw`、`.<项目>_pw`（root 600） |
| 内存 | `maxmemory 200mb`，`maxmemory-policy volatile-lru` |
| 持久化 | RDB：`save 900 1 / 300 10 / 60 10000`，无 AOF |

### 约定（所有接入项目都要遵守）

- **只放可以丢的数据**（缓存、会话、计数等）。业务数据放数据库。
- **所有 key 必须设过期时间**。淘汰策略是 `volatile-lru`，只淘汰带 TTL 的 key；不带 TTL 的 key 写满后会导致写入报错，影响所有项目。
- **每个项目一个 ACL 账号，key 限定在自己的前缀下**，不靠 DB 编号隔离。模板：

  ```
  user <项目账号> on #<密码 sha256> ~<前缀>:* resetchannels +@all -@dangerous -@admin -scan -randomkey
  ```

  `-@dangerous -@admin` 挡住 `FLUSHALL`、`CONFIG`、`KEYS` 等能影响其它项目的命令；`SCAN`、`RANDOMKEY` 不在 `@dangerous` 里且不受前缀限制，必须单独去掉，否则能列出所有项目的 key 名。
- `default` 用户关闭；`admin` 是运维账号（`~* &* +@all`），只给人用。
- ACL 文件里只存密码的 sha256，明文密码在宿主机 root 600 文件里，不出现在命令行。

### 运维操作

```bash
# 用某个账号执行命令（密码经 stdin 传进容器，不进命令行；用文件形式执行，别塞进 ssh heredoc）
docker exec -i shared-redis sh -c 'read -r P; REDISCLI_AUTH="$P" redis-cli --no-auth-warning --user admin "$@"' _ INFO memory < /www/docker/shared-redis/.admin_pw
```

- **新增项目账号**：生成密码存 `/www/docker/shared-redis/.<项目>_pw`（root 600），按模板在 `conf/users.acl` 追加一行（写 sha256），再用 admin 执行 `ACL LOAD`（不用重启），最后更新下面的登记表。
- **升级**：换镜像小版本需要重建容器（数据在 `data/`，RDB 会保留），会短暂中断所有接入方，先在登记表里确认各项目都能容忍 Redis 不可用。
- **备份**：当前只放可丢数据，不单独备份 RDB。

### 登记表

| 项目 | ACL 账号 | key 前缀 | 用途 | 预计内存 | Redis 不可用时的影响 | 接入时间 |
| --- | --- | --- | --- | --- | --- | --- |
| nyh-wechat-mp | `nyh_wechat_mp` | `wxmp:*` | access_token 缓存、后台会话、登录失败计数 | < 1MB | 回调不受影响；token 退回进程内缓存；后台登录提示「会话服务不可用」 | 2026-11-07 |

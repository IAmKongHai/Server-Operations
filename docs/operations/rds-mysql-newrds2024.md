# NewRDS2024（MySQL）运维时间线

阿里云香港 MySQL 8.0 RDS `rm-j6cb0v171f2al0h41`（控制台名 **NewRDS2024**，`mysql.n2e.medium.1`，包年包月）。内网 `172.31.138.204:3306`，公网 `rm-j6cb0v171f2al0h41bo.mysql.rds.aliyuncs.com`。应用从 `nyh-prod`（`172.31.138.210`）经 VPC 访问。

## 2026-11-07 15:40 CST - 只读评估 fa.nanyahui.com / konghai.me 迁往 PostgreSQL 的可行性

- 服务器：`nyh-prod`、阿里云 RDS `rm-j6cb0v171f2al0h41` / `pgm-j6cf5kaej216sx0z`
- 操作人：`Claude`
- 原因：MySQL 实例将于 2026-11-08 00:00 CST 到期，用户想把仍在用的两个站点迁到 PG。
- 影响：无变更，只读查询。
- 回滚方式：无需回滚。

### 发现

| 站点 | 程序 | 库 / 规模 | PHP | 迁 PG 的难度 |
| --- | --- | --- | --- | --- |
| `konghai.me` | Typecho 1.3.0（`config.inc.php` 用 `Pdo_Mysql`，前缀 `typecho_`） | `konghai_me_db`，7 张表，约 330 行，<1MB | `enable-php-82`，**php82 没有 `pdo_pgsql`** | 低：Typecho 自带 `Pgsql` 适配器 |
| `fa.nanyahui.com` | FastAdmin 1.6.1（ThinkPHP 5）+ `weixin` 插件，`.env` 配库 | `fast_admin_db`，30 张表，主要是 `fa_weixin_fans` 18216 行 / 7MB | `enable-php-74`，php74 已有 `pdo_pgsql` | 高：核心代码写死 MySQL 语法（反引号、`SHOW TABLE STATUS`、`FIELD()`、`DATE_FORMAT/FROM_UNIXTIME`、`information_schema` 按 `TABLE_SCHEMA` 查） |

- `fa.nanyahui.com` 今天的访问主要是 `/addons/weixin/index/wechat`（公众号回调）24 次，后台几乎无人用。
- PG 实例实际是 **PostgreSQL 18.0**（`pg.n2.2c.1m`，100G，到期 2027-11-04），之前笔记里的 17.7 已过时。
- `nyh-prod` 本机没有跑 MySQL / MariaDB 服务（只有 MariaDB 11.8 客户端，连 RDS 需加 `--skip-ssl`）；有 Docker；内存 7.2G、可用约 4.5G，磁盘剩 53G。

## 2026-11-07 13:20 CST - 到期前只读盘点（用户不打算续费）

- 服务器：阿里云 RDS `rm-j6cb0v171f2al0h41`；附带在 `nyh-prod` 上只读排查
- 操作人：`Claude`
- 原因：实例 `ExpireTime=2026-11-07T16:00:00Z`（即 **2026-11-08 00:00 CST** 到期），用户不想续费，先确认还有没有业务在用。
- 影响：无变更，全部是只读查询。
- 回滚方式：无需回滚。

### 本机阿里云 CLI

- `aliyun` 3.4.10，profile `default`（AK，地域 `cn-hongkong`）有效；`sts GetCallerIdentity` 返回 RAM 用户 `power-user-access`。
- 全地域扫描只有香港有 RDS：本实例 + `pgm-j6cf5kaej216sx0z`（RDS-Pg-2025，到期 2027-11-04，不受影响）。

### 实例现状

| 项 | 值 |
| --- | --- |
| 状态 | `Running`，`DeletionProtection=false` |
| 自动续费 | 未开（`Status=Normal`，`Duration=0`） |
| 库 | 29 个：`ddricher`、`test_ddricher`、`nyh_center`、`nyh_center_test`、`nyh_agent*`（14 个）、`nyh_feidaolife`、`nyh_feikuaichong`、`actitime_db`（描述「生产数据库」）、`fast_admin_db`、`konghai_me_db`、`ai_key_air`、`about_apple`、`sky_sms`、`us_stock`、`us_stock_backup`、`wxmagic`、`load` |
| 备份 | 每天 10:23 CST 快照全备，近 7 天都成功；保留 7 天；`ReleasedKeepPolicy=Lastest`（实例释放后保留最后一份备份） |
| 近 24h 负载 | QPS 平均 5.78（峰值 14.8），TPS 恒为 0.33，活跃会话约 0，总会话 1–3：看起来是空闲基线 |

### nyh-prod 上的引用

- 当前唯一常驻连接：supervisor `YysgCreateOrder`（`php74 /www/wwwroot/yysg.nanyahui.com/think queue:work --queue createOrderJobQueue`）。
- 配置仍指向本实例的站点 / 服务（12 个文件）：`yysg.nanyahui.com`、`tiancheng.nanyahui.com`、`test-agent.nanyahui.cn`、`fa.nanyahui.com`、`konghai.me`、`phpmyadmin.nanyahui.com`、`ddricher/richer_web`、`richer_test/richer_web`、`sms-admin`（`FINANCE_DB_HOST`）、`python/ActiTime`、`python/ai-key-air`。
- 今天的访问日志：`yysg` 7183 条，其中 6344 条是 `43.156.28.236` 请求 `/vapi/get-order` 并返回 404，其余是扫描；`konghai.me` 396 条（首页 200 约 30 次，其余是扫描）；`fa.nanyahui.com` 有 19 次 `/addons/weixin/index/wechat` 返回 200；`test-agent` 只有零星访问。
- `load.nanyahui.com` 的 `nyh-sms-worker` 不连本实例。

### 结论

没看到明显的业务读写，但配置引用很多，而且库里有标注为生产的 `actitime_db`、`nyh_center`、`ddricher`。到期前建议先做一次逻辑导出留底，再让它到期。

### 后续

- 用户确认是否导出、导到哪里，以及到期后是否清理 nyh-prod 上的 `YysgCreateOrder` 进程和各站点配置（这些都要先确认再做）。

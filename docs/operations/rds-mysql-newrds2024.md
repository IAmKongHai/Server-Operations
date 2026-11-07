# NewRDS2024（MySQL）运维时间线

阿里云香港 MySQL 8.0 RDS `rm-j6cb0v171f2al0h41`（控制台名 **NewRDS2024**，`mysql.n2e.medium.1`，包年包月）。内网 `172.31.138.204:3306`，公网 `rm-j6cb0v171f2al0h41bo.mysql.rds.aliyuncs.com`。应用从 `nyh-prod`（`172.31.138.210`）经 VPC 访问。

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

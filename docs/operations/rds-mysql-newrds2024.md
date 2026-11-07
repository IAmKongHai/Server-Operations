# NewRDS2024（MySQL）运维时间线

阿里云香港 MySQL 8.0 RDS `rm-j6cb0v171f2al0h41`（控制台名 **NewRDS2024**，`mysql.n2e.medium.1`，包年包月）。内网 `172.31.138.204:3306`，公网 `rm-j6cb0v171f2al0h41bo.mysql.rds.aliyuncs.com`。应用从 `nyh-prod`（`172.31.138.210`）经 VPC 访问。

## 2026-11-07 16:40 CST - 修正：公众号回调真正的入口是 nyhAgent，FastAdmin 只是被转发的下游

- 服务器：`nyh-prod`；本机代码 `~/Code/Project/nyh/nyhAgent`、`nyhCenter`
- 操作人：`Claude`
- 原因：用户想知道 nyhAgent / nyhCenter 对 FastAdmin 的依赖，以及能不能完全移除 FastAdmin。
- 影响：无变更，只读。
- 回滚方式：无需回滚。

### 调用链（以生产日志和配置为准）

```text
微信服务器（81.69.103.x / 175.24.214.x）
  → POST https://load.nanyahui.com/notify/weixin/index   （nyhAgent，php74，库已在 PG nyh_agent）
      ├─ 文本 TD / DY：退订 / 打开返佣通知，直接回复并 exit
      ├─ 菜单 myPoster：UserPosterModel::sendPoster 发专属海报，exit
      ├─ subscribe：按 scene（custom_ / user_ / web_）建用户、记上级、二维码计数
      ├─ unsubscribe：标记取关
      ├─ SCAN web_：VIP 网页扫码登录，回复「登陆成功！」
      └─ transmit()：把原始报文原样 POST 给 load_config.wq_url，并把返回内容 echo 给微信
             wq_url = https://fa.nanyahui.com/addons/weixin/index/wechat （FastAdmin weixin 插件：关键词回复 / 默认回复）
```

- 今天 `load.nanyahui.com` 日志里 `/notify/weixin` 有 25 次；`fa.nanyahui.com` 收到的 24 次回调全部来自本机公网 IP `47.239.167.8`，说明都是 nyhAgent 转发过来的。
- 代码里注释掉的旧地址 `https://wx.nanyahui.com/api.php?id=2` 是更早的第三方转发目标。
- `nyhCenter` 里也有一个 `notify/WeixinController`，但生产上 `center.nanyahui.com` 没有回调流量，不在这条链路上。
- 两个仓库都没有直接依赖 FastAdmin 的代码，唯一的耦合就是 `wq_url` 这个配置。
- `transmit()` 的 `http_post` **没有设 curl 超时**：如果 FastAdmin 因为 MySQL 到期而卡住，nyhAgent 的回调会被一起拖住，超过微信的 5 秒限制。
- 「微擎消息转发地址」这项配置（PG `nyh_agent.load_config`，`group=3`）：
  - `id=57 wq_url`：值是 `https://fa.nanyahui.com/addons/weixin/index/wechat`，备注「用于微信公众号消息转发」。只有 `WeixinController::transmit()` 读它，可以在 nyhAgent 后台「系统配置」（`admin/ConfigController`）里修改。`update_time` 还停在 2019-06-20，看来改成 fa 地址时是直接改的库。
  - `id=56 wq_token`：名字叫「微擎token」，但实际被 `ObjectFactory::WeChatInstance()` 当成公众号服务器配置里的 Token 用来校验签名，**和微擎、FastAdmin 都无关，不能删也不能改**。
  - 生产上公众号的 AppID / AppSecret 来自 `load_config` 的 `wechat_appid` / `wechat_appsecret`，和 FastAdmin 里配的是同一套；仓库里 `config/wechat.php` 的 `official.app_secret` 和生产不一致，不是这条链路在用的。
- 因此上一条「停用服务器配置，改用公众平台原生自动回复」的建议**作废**：停用会让扫码登录、注册与上下级绑定、专属海报、TD/DY 全部失效。

## 2026-11-07 16:15 CST - 只读梳理 fa.nanyahui.com 公众号功能（准备淘汰 FastAdmin）

- 服务器：`nyh-prod`
- 操作人：`Claude`
- 原因：用户只需要公众号的回调、消息回复和菜单管理，想借这次 MySQL 到期淘汰 FastAdmin（只能跑 php 7.4）。
- 影响：无变更，只读。
- 回滚方式：无需回滚。

### 发现

- 公众号「南亚汇 在菲生活服务」（`gh_d93e814c8432`），回调地址是 `/addons/weixin/index/wechat`，走 FastAdmin 的 `weixin` 插件 3.0.6，代码没改过，消息是明文模式（`encode=0`）。
- 实际在用的功能只有：
  - 7 条回复规则：6 条半匹配关键词规则（批量、客服、支付宝、余额流量、新卡激活、退款），外加 `default`（客服二维码图片）。
  - 1 套菜单：3 个一级菜单、共 9 项，其中 click 类型的 key 也按关键词规则匹配，view 类型跳 `load.nanyahui.com`。
- 关注事件和菜单项 `myPoster` 都没有对应规则，最后都回落到 `default` 图片。扫码登录（`fa_user` 0 行）、模板消息都没在用；`fa_weixin_fans`（18216 行）只是粉丝同步数据，回调用不到。
- 同一个 AppID 还配在 `load.nanyahui.com`、`yysg`、`tiancheng`、`ax`、`test-agent` 的 `config/wechat.php` 里（网页授权 / JSSDK 等主动调用的 API），这些不依赖回调。
- php 7.4 上还有 7 个站点：`center`、`load.nanyahui.com/.cn`、`test-agent`、`vip.nanyahui.com/.cn`、`yysg`。淘汰 FastAdmin **并不能**让 php 7.4 下线。
- 回复规则和图片已经导出到本机 scratchpad，供在公众平台后台手工重建。

## 2026-11-07 16:00 CST - 全库逻辑导出留底 + konghai.me 迁到 PostgreSQL 18

- 服务器：`nyh-prod`、阿里云 RDS `rm-j6cb0v171f2al0h41`（MySQL）/ `pgm-j6cf5kaej216sx0z`（PG 18.0）
- 操作人：`Claude`（用户确认做「全库导出」和「konghai.me 迁 PG」；`fa.nanyahui.com` 另议）
- 原因：MySQL 实例 2026-11-08 00:00 CST 到期不续费。
- 影响：php-fpm-82 平滑 reload 一次（服务 `konghai.me`、`numbers.konghai.me`、`nyh-2025.konghai.me`、`127.0.0.1`），无中断；`konghai.me` 切库瞬间无感知。
- 备份：`/www/server/php/82/etc/php.ini.bak.20261107`、`/www/wwwroot/konghai.me/config.inc.php.bak.20261107`
- 回滚方式：
  - konghai.me：`cp -p config.inc.php.bak.20261107 config.inc.php`（仅在 MySQL 到期前有效；到期后需把 `/root/rds-final-dump-20261107/konghai_me_db.sql.gz` 导入别的 MySQL）。
  - php82 扩展：`cp php.ini.bak.20261107 php.ini` 后 `/etc/init.d/php-fpm-82 reload`。

### 1. 全库导出

- 宝塔 `database_servers` 里存的 root 密码已失效（`Access denied`），于是用阿里云 CLI 临时建 RDS 账号 `tmp_dump_20261107`，对全部 29 个库授 `ReadOnly`，导出后已 `DeleteAccount`。
- 导出脚本 `/root/rds-final-dump-20261107/dump.sh`：MariaDB 11.8 的 `mysqldump --skip-ssl --single-transaction --quick --routines --triggers --hex-blob --databases <db> | gzip`，逐库导出。注意 MariaDB 客户端**不认** `--set-gtid-purged`，连这台 RDS 也**必须**加 `--skip-ssl`。
- 结果：29 个库全部成功，原始约 11.8GB，压缩后 **961MB**，在 `/root/rds-final-dump-20261107/*.sql.gz`（600，root）；`gzip -t` 全部通过，每个文件结尾都有 `Dump completed`；校验和在 `SHA256SUMS`。
- 这份导出目前只在 nyh-prod 本机，尚未异地复制。

### 2. konghai.me（Typecho 1.3.0）迁 PG

1. PG 上用阿里云 CLI 建账号 `konghai_me_user`（Normal）和库 `konghai_me_db`（UTF8 / `en_US.utf8`），并授予 `DBOwner`。
2. php82 用源码 `/www/server/php/82/src/ext/pdo_pgsql` 加系统 `libpq-dev` 17 phpize 编译出 `pdo_pgsql.so`，放进 extension_dir，在 `/www/server/php/82/etc/php.ini` 末尾加一行 `extension`，然后 `/etc/init.d/php-fpm-82 reload`。注意 php82 CLI 读的是 `php-cli.ini`，验证 FPM 要用 `php -c /www/server/php/82/etc/php.ini -m`。
3. 迁移脚本 `/root/rds-final-dump-20261107/migrate_konghai_me.php`：先跑官方 `install/Pgsql.sql` 建表，再按 MySQL 实际列补齐——放宽 varchar（150→200，`metas.type` 16→32），加上 MySQL 独有的 `typecho_contents.views INT DEFAULT 0`；在单个事务里逐表复制，然后 `setval` 各 `*_seq` 到 max(id)。
4. 7 张表行数一致（comments 124 / contents 53 / metas 29 / options 68 / relationships 57 / users 1 / fields 0）。切换前又核对了一次 MySQL，没有新写入。
5. `config.inc.php` 改为 `Pdo_Pgsql`，host 用 `pgm-j6cf5kaej216sx0z.pg.cnhk.rds.aliyuncs.com:5432`，`charset=utf8`，去掉 `engine`。

### 验证

- 本机经 `--resolve` 访问 `/`、文章页、分类页、feed、搜索、`/admin/login.php`，全部 200，标题正确，页面里没有数据库错误。
- PG `pg_stat_activity` 里能看到 `konghai_me_user` 的连接；配置里已经没有 MySQL 地址。
- 其它 php82 站点 reload 后正常（`numbers.konghai.me` 首页 403 是历史上就有的）。

### 待办

- `fa.nanyahui.com`（公众号回调，用户说「非常重要」）仍连 MySQL，**00:00 前必须另行处理**。
- 后台写入（发文、评论）还没有实测，建议用户登录后台发一条草稿验证。

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

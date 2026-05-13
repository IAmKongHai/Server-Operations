---
title: 从本地通过 ssh + docker exec 操作容器化 SQL Server 的 shell/sqlcmd 陷阱
date: 2026-05-13
category: docs/solutions/best-practices
server: (适用所有服务器)
module: shell / ssh / docker exec / sqlcmd
problem_type: best_practice
component: tooling
severity: low
tags: [best-practice, sqlcmd, ssh, docker-exec, here-doc, shell-quoting, tmpfs, streaming-transfer, fish, zsh]
---

# 从本地通过 ssh + docker exec 操作容器化 SQL Server 的 shell/sqlcmd 陷阱

跨多层 shell 边界（本地 → ssh → docker exec → bash → sqlcmd）操作时积累的踩坑笔记。这些坑普遍适用，不绑具体服务器。

## 1. `$MSSQL_SA_PASSWORD` 在外层 shell 被静默吃掉

最高频、最隐蔽的坑。

```bash
# ❌ 静默失败：外层 ssh shell 把 $MSSQL_SA_PASSWORD 展开成空字符串
#    （因为登录到目标的 ssh 用户根本没有这个环境变量）
ssh host "docker exec -i c bash -c '/opt/mssql-tools/bin/sqlcmd -P \"$MSSQL_SA_PASSWORD\" ...'"

# ❌ 无引号 here-doc：外层 shell 同样会展开 $MSSQL_SA_PASSWORD
ssh host << OUTER
docker exec -i c bash -c '... -P "$MSSQL_SA_PASSWORD" ...'
OUTER

# ✅ 引号 here-doc：$ 原样传到远端，由容器内 shell 展开
ssh host << 'OUTER'
docker exec -i c bash << 'INNER'
/opt/mssql-tools/bin/sqlcmd -P "$MSSQL_SA_PASSWORD" -Q "SELECT @@VERSION"
INNER
OUTER

# ✅ 等价但更紧凑：单层 -c 但里面用单引号包裹整段，并用 \$ 转义
ssh host "docker exec -i c bash -c '... -P \"\$MSSQL_SA_PASSWORD\" ...'"
```

**为什么隐蔽**：错误密码 + `-Q` 模式下 sqlcmd 退出码会是非零，但 `Login failed for user 'sa'` 这种错误经常出现在 stderr 末尾、被 ssh tunnel 缓冲、或在外层管道里看不见，让你以为命令"跑完了但没输出"。

**调试技巧**：怀疑这个坑时，先单独跑一次能输出版本的探针：

```bash
ssh host "docker exec -i c bash -c '/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P \"\$MSSQL_SA_PASSWORD\" -Q \"SELECT @@VERSION\"'" 2>&1 | head -5
```

看到版本号就 OK；看到 `Login failed` 就是密码丢了。

## 2. `docker inspect` 看密码

每个 SQL Server 镜像/版本/uid 都可能不同，先确认：

```bash
# SA 密码
docker inspect <container> --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -iE 'PASS|SA'

# 容器内 mssql 用户的 uid（不同镜像不同！本次遇到 999 和 10001 两种）
docker exec <container> id mssql

# 挂载和 RW 状态（有些 backups 目录是 ro mount，写不进）
docker inspect <container> --format '{{range .Mounts}}{{.Source}} -> {{.Destination}} RW={{.RW}}{{println}}{{end}}'
```

## 3. SQL 单引号要四级转义（外 ssh + bash -c '...' + sqlcmd -Q "..." + SQL '...'）

```bash
# 目标 SQL：SELECT name FROM sys.databases WHERE name = N'foo'
# 实际写法：
ssh host "docker exec -i c bash -c '/opt/mssql-tools/bin/sqlcmd ... -Q \"SELECT name FROM sys.databases WHERE name = N'\''foo'\''\"'"
```

单引号转义层级：`'\''` 在 bash 单引号内表示一个字面单引号。每多一层 shell 包装，转义就再翻一倍。**超过两层就别这么写**，改用 here-doc：

```bash
ssh host << 'OUTER'
docker exec -i c bash << 'INNER'
/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" <<'SQL'
SELECT name FROM sys.databases WHERE name = N'foo';
SQL
INNER
OUTER
```

三层引号 here-doc 直接搞定，所见即所得。

## 4. sqlcmd 输出宽度被截断

`RESTORE HEADERONLY` / `FILELISTONLY` 输出列特别多（50+ 列），默认宽度会让一行被切到多行甚至丢失。

```bash
# -y N：变长列宽度上限
# -Y N：定长列宽度上限
# -W ：去尾空格（配合 awk/grep 使用方便）
# -h -1：不打印列头（脚本里取值方便）
sqlcmd -y 200 -Y 50 -W -Q "RESTORE HEADERONLY FROM DISK = '...'"
```

排查 `DatabaseVersion`、`LogicalName` 等关键列时，**先把宽度撑开**。

## 5. `/tmp` 是 tmpfs，5+ GB 文件不能往里塞

dev-cypresso 是 EC2 instance，`/tmp` 默认 tmpfs，本机配置 8 GB。许多云主机、容器宿主、ramdisk-as-tmp 的系统都是这样。

```bash
df -h /tmp
# Filesystem      Size  Used Avail Use% Mounted on
# tmpfs           7.8G  ...        ... /tmp        ← 危险！
```

如果 /tmp 是 tmpfs：

- 不能用 `rsync host:/tmp/big.file` 中转大文件
- 即使 `docker cp` 完了，如果忘删 /tmp 副本，内存被吃掉
- swap 会被频繁写入，机器变慢

### 流式传输绕过 tmpfs（推荐用于 5+ GB 文件）

```bash
# 本地 → 容器内文件（不落宿主磁盘）
cat local.bak | ssh host \
  "docker exec -i container bash -c 'cat > /var/opt/mssql/restore_tmp/local.bak'"
ssh host "docker exec container chown mssql:mssql /var/opt/mssql/restore_tmp/local.bak"

# 容器内文件 → 本地（同理反向）
ssh host "docker exec container cat /path/in/container/file.bak" > local_file.bak
```

实测 10 GB 文件这种方式约 35 分钟（取决于上行带宽），md5 校验一致。

### 反向流式传输的常见踩坑：fish/zsh 报错让任务误报 failed

```bash
# ❌ 这条写在 .sh 里 zsh 解释会报 "== not found"
ssh host "..." > local.bak
echo === done ===   # ← fish/zsh 都会试图解释 ===

# 实测后果：cat 部分已完整执行、文件已完整写入、md5 一致，
# 但整条命令 exit 1，任务通知报 "failed"。
```

**判断真假失败**：直接 `md5sum` 远端和本地文件，一致就是好的。不要看 exit code。

## 6. tmpfs 替代方案：流式 `docker cp` 走 stdin

不想用 docker exec 流式时，docker cp 也支持 stdin：

```bash
# 本地 → 容器（tar 格式，文件名要在 tar 头里）
tar -C $(dirname local.bak) -cf - $(basename local.bak) | \
  ssh host "docker cp - container:/var/opt/mssql/restore_tmp/"
```

但实践中 `cat | docker exec bash -c 'cat > file'` 更简单，少一层 tar。

## 7. RESTORE 路径必须是容器内能写的路径

容器化 SQL Server 经常把 backups 目录挂成 read-only：

```
bind /vol2/data/backups -> /var/opt/mssql/backups (RW=false, Mode=ro)
```

`BACKUP DATABASE ... TO DISK = '/var/opt/mssql/backups/x.bak'` 会报：

```
Cannot open backup device '...'. Operating system error 5 (Access is denied.).
```

但 mssql 用户对这个目录看起来是有权的（`ls -ld` 显示 `drwxrwx--x mssql mssql`）——别被误导，**问题不在 POSIX 权限，在 mount option 的 ro**。

解法：
- 备份/恢复用 mssql 自己拥有的可写路径，例如 `/var/opt/mssql/<custom_dir>/`
- 创建临时目录：`docker exec -u 0 c mkdir /var/opt/mssql/foo && docker exec -u 0 c chown mssql:mssql /var/opt/mssql/foo`

## 8. 等 `RESTORE` 真完成（不是 100%）

```sql
-- ❌ 这个 100% 不代表 RESTORE 完成
SELECT command, percent_complete FROM sys.dm_exec_requests WHERE command LIKE '%RESTORE%';
-- 经常会停在 percent_complete=100，但 state_desc 仍是 RESTORING
-- 因为容器内 mssql 没有 SeManageVolumePrivilege，LDF zero-init 必须实打实写零

-- ✅ 看 state_desc=ONLINE 才是真的完成
SELECT state_desc FROM sys.databases WHERE name = N'mydb';
```

正确的等待循环：

```bash
until ssh host "docker exec -i c bash -c '/opt/mssql-tools/bin/sqlcmd ... -h -1 -W -Q \"SET NOCOUNT ON; SELECT state_desc FROM sys.databases WHERE name=N'\''mydb'\''\"'" \
  2>&1 | grep -q '^ONLINE'; do
  sleep 30
done
```

`-h -1`（不输出列头）+ `-W`（去尾空格）让 grep `^ONLINE` 能精确匹配。

## 9. 通用排查清单

跨多层 shell 操作前先打这套探针，可以省大量调试时间：

```bash
# 1. 容器在跑、可 exec？
ssh host "docker exec c echo OK"

# 2. SA 能登陆、版本对得上？
ssh host "docker exec -i c bash -c '/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P \"\$MSSQL_SA_PASSWORD\" -Q \"SELECT @@VERSION\"'" 2>&1 | head -5

# 3. 容器内 mssql 的 uid？（别想当然）
ssh host "docker exec c id mssql"

# 4. 目标目录可写？
ssh host "docker exec c bash -c 'touch /var/opt/mssql/<target>/test && rm /var/opt/mssql/<target>/test && echo WRITE_OK'"

# 5. tmpfs 检查
ssh host "df -h /tmp /"
```

每条都过了再开始正式操作，能避免 80% 的"看起来跑了但其实没"的怪现象。

## 关键经验

1. **跨 ssh + docker exec + sqlcmd 时永远用引号 here-doc**，少踩 90% 的引号坑。
2. **怀疑 sqlcmd 静默失败，先跑 `SELECT @@VERSION` 探针**。
3. **大文件传输前先 `df -h /tmp` 看 tmpfs**。流式 `cat | ssh | docker exec` 是最稳的兜底方案。
4. **任务报 failed 不一定是真的失败**：流式传输尾巴上的 `echo === done ===` 会让 fish/zsh 报错让退出码非零，但数据已经写完。**用 md5 判定，不用 exit code**。
5. **RESTORE 完成的标志是 `state_desc=ONLINE`**，不是 `percent_complete=100`。
6. **每个 SQL Server 镜像的容器内 mssql uid 不一样**，操作 chown / 挂载新盘前先 `docker exec c id mssql`。

## 相关文档

- [[../dev-cypresso/database-issues/restore-bak-with-huge-log-via-temp-disk-2026-05-13]] —— 应用这些技巧的完整流程
- [[../nas/database-issues/mssql-shrink-bloated-transaction-log-2026-05-13]] —— SHRINKFILE 详细原理

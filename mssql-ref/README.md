# mssql-ref

PVE 上的 Ubuntu VM，用来运行 MAS 老系统的 MSSQL 参考数据库。该 VM 只用于重构期间读取、调试和对照旧系统数据，不作为生产数据库。

## 连接

```bash
ssh ubuntu@192.168.2.20
```

| 项目 | 值 |
| --- | --- |
| 服务器名 | `mssql-ref` |
| PVE 宿主 | `pve` / `192.168.2.10` |
| VMID | `110` |
| IP | `192.168.2.20/24` |
| SSH 用户 | `ubuntu` |
| 用途 | MAS 老系统 MSSQL 参考数据库 |
| SQL Server | `192.168.2.20:1433` |
| 环境属性 | 参考/测试数据库，不作为生产数据库 |

## 操作边界

- 只读查询、状态检查可以直接执行。
- 重启 VM、重启 `mssql-server`、改数据库 schema/data、恢复备份前，先备份当前状态并征得确认。
- 不在仓库记录 SQL Server 密码；凭据位置见 VM 内 `/root/mssql-secrets.env`。

## 相关资料

- PVE VM 详细配置、SQL Server 版本、数据库清单：[`../pve/README.md`](../pve/README.md)

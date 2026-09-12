# 菜苗苗 SIT 对照

以服务器 `/opt/cmm-sit` 为准。源文件在兄弟仓 `caimiaomiao` 的 `backend-cmm-api/deploy/sit/`。本目录只放不含密钥的对照副本。

入口：

- API `http://100.109.223.53:25880`（公网 `https://sit-api-cmm.nanyahui.cn`）
- 管理中台 `http://100.109.223.53:25881`（公网 `https://sit-admin-cmm.nanyahui.cn`）

回滚：对该目录 `docker compose stop`，不要 `down -v`，也不要 `--remove-orphans`。

# MAS C# Reference Smoke Test - 2026-05-16

## Environment

| 项目 | 值 |
| --- | --- |
| PVE host | `pve` / `192.168.2.10` |
| App VM | `mas-win` / VMID `120` / `192.168.2.21` |
| DB VM | `mssql-ref` / VMID `110` / `192.168.2.20` |
| API | `http://192.168.2.21:9020/` |
| Web | `http://192.168.2.21:9021/` |

## Results

| 检查项 | 结果 | 备注 |
| --- | --- | --- |
| VM state | PASS | `mas-win` running |
| Windows Server Core | PASS | Windows Server 2022 Standard Evaluation |
| QEMU guest agent | PASS | PVE guest ping OK |
| IIS sites | PASS | `MAS-API` / `MAS-WEB` started |
| AppPools | PASS | `MAS-API` / `MAS-WEB` started |
| SQL connectivity from Windows VM | PASS | `medicalassistance=419 tables`、`authprovidermasweb=9 tables`、`maswebkit=66 tables` |
| Web login page | PASS | `GET /` on `9021` returned HTTP 200 |
| API root | PASS | `GET /` on `9020` returned HTTP 403 directory listing denied; acceptable for API root |
| Login with test account | PASS | `POST /user-signin` returned HTTP 200 and JSON `status=200`, `error=false` |
| Post-login page | PASS | Cookie-authenticated `GET /` returned HTTP 200 and login-after marker |
| Preprod environment flags | PASS | NAS parity: `MAS-WEB env=client-prod`、`MAS-API prodEnv=true`、`uatEnv=false` |
| Static resource cache | PASS | NAS parity: `clientCache UseMaxAge` / `7.00:00:00` |
| Final snapshot | PASS | `mas-csharp-preprod-ready` created |

## Fixes Applied During Smoke

- Replaced old SQL passwords in VM deployment `Web.config` files with the `mas_ref_reader` password from `mssql-ref`.
- Synced OAuth client settings in the deployment copy from `authprovidermasweb.dbo.oauth_clients` without recording secret values in docs.
- Promoted `mas_ref_reader` to `db_owner` in `medicalassistance`、`authprovidermasweb`、`maswebkit` for comprehensive CRUD testing in this reference environment.
- Re-ran login smoke after `db_owner` promotion: `POST /user-signin` still returned HTTP 200 and JSON `status=200`, `error=false`.
- Compared the PVE deployment against the earlier NAS Docker Windows deployment and switched environment flags from UAT/local-reference to preprod/client-prod.
- Re-ran login smoke after the preprod switch: `POST /user-signin` returned HTTP 200 and JSON `status=200`, `error=false`; authenticated home page returned HTTP 200.

## Notes

- The app is intended only for LAN reference during the Go + React rewrite.
- `mas_ref_reader` is no longer read-only despite its historical name; it has `db_owner` in the three reference databases.
- SMTP and external production callbacks remain disabled/localized in the VM deployment copy.
- PVE emitted thin-pool overcommit warnings while creating snapshots. Keep `mas-csharp-preprod-ready` as the useful rollback point and clean older snapshots when no longer needed.

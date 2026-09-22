# CYP-2600 五份备份 VERIFYONLY 与十行模块实测

2026-09-22 15:05–15:15 +08。目标是 `ihc-db-uat` / `10.100.0.4:1433` / SQL Server `14.0.3550.4` / TCP。客户端地址 `10.61.0.14`。没有 `RESTORE DATABASE`，没有业务 DML，没有 GRANT / DENY，没有把口令写入虚拟机或本文。

原始结果在本机 `Server/_backups/cyp2600-inventory/20260922T070502Z/`（gitignore，目录 `0700`）。模块正文、口令、明文和密文都不在该目录。

## 备份

身份：`cyp2600_admin`，`ORIGINAL_LOGIN` 与登录名一致，`sysadmin=1`，catalog `master`。语句模板是 `RESTORE VERIFYONLY FROM DISK = N'<path>' WITH FILE = <position>, CHECKSUM`，模板 SHA-256 `b994aa62c0c1fce2e2e7c916721c6329a4ec12918cf7d7a7dd99051e9b039969`。五份都是 2026-09-22 的 position 1、`type=D`、`is_copy_only=1`、`has_backup_checksums=1`、`is_damaged=0`。顺序由小到大。通过 5/5。这不是恢复演练。

| catalog | backup_set_id | 耗时 | 结果 |
|---|---:|---:|---|
| insularsalesportal_preprod | 27438 | 1.632s | PASS |
| authprovidermasuat | 27441 | 1.777s | PASS |
| masprepaid_preprod | 27439 | 2.248s | PASS |
| maswebkit_preprod | 27440 | 15.636s | PASS |
| medicalassistance_preprod | 27442 | 101.576s | PASS |

路径均为 `F:\icare2bak\<catalog>_20260922_cyp2600.bak`。开始 `2026-09-22T07:07:46Z`，结束 `2026-09-22T07:09:52Z`。

## 模块

管理员连接只读元数据。十个对象的 `definition_sha256` 都与 `module-evidence.json` 一致，`execute_as_principal_id` 都是 null（CALLER）。`sys.dm_sql_referenced_entities` 与 `sys.sql_expression_dependencies` 仍是 0 行；空依赖不能当成无依赖。结论来自与 hash 匹配的正文标志：没有 `sp_executesql`、没有 `EXEC(` / `EXECUTE(`、没有点名另外四个业务库。打开过程含口令字面量，本文不记录该字面量。

调用使用各受限 login 的新 TCP 连接。合成记号只在会话内比较布尔结果。`NULL` 输入没有当作通过。

| ID | login / catalog / 对象 | permission_probe | actual_call | 依赖 | 结果 |
|---|---|---|---|---|---|
| R009 | ecom_runtime_prod / medicalassistance_preprod / decodercontains | PASS，EXECUTE=1，sysadmin=0 | PASS，往返相等，结果非 NULL、非空 | 静态、无密钥、无跨库 | 建议可签收 |
| R060 | sup_runtime_prod / medicalassistance_preprod / sp_opensymmetric | PASS，EXECUTE=1 | FAIL，15151，之后 `sys.openkeys` 为空 | 正文会打开密钥 Encrypt | 保持 pending |
| R061 | sup_runtime_prod / medicalassistance_preprod / sp_closesymmetric | PASS，EXECUTE=1 | FAIL，15315 | 正文会关闭密钥 | 保持 pending。关闭失败是因为没有打开 |
| R062 | sup_runtime_prod / medicalassistance_preprod / Decrypt | PASS，EXECUTE=1 | FAIL，Encrypt 返回 NULL，往返不相等 | 静态 DECRYPTBYKEY，依赖同一会话已打开的密钥 | 保持 pending |
| R063 | sup_runtime_prod / medicalassistance_preprod / Encrypt | PASS，EXECUTE=1 | FAIL，同上一次调用 | 静态 ENCRYPTBYKEY / KEY_GUID('Encrypt') | 保持 pending |
| R064 | sup_runtime_prod / medicalassistance_preprod / decodercontains | PASS，EXECUTE=1 | PASS，往返相等 | 与 R009 同一 hash，无密钥 | 建议可签收。同一次会话里打开密钥已经失败，本函数不依赖该失败 |
| R065 | sup_runtime_prod / insularsalesportal_preprod / decoder | PASS，EXECUTE=1 | PASS，varchar(15) 往返相等 | 静态、无密钥、无跨库。该库另有密钥 Encrypt，本函数未使用 | 建议可签收 |
| R094 | public_hr_runtime_prod / maswebkit_preprod / sp_opensymmetric | PASS，EXECUTE=1 | FAIL，15151 | 正文会打开密钥 Encrypt。hash 与主库不同 | 保持 pending |
| R095 | public_hr_runtime_prod / maswebkit_preprod / sp_closesymmetric | PASS，EXECUTE=1 | FAIL，15315 | 正文会关闭密钥 | 保持 pending |
| R096 | public_hr_runtime_prod / maswebkit_preprod / Decrypt | PASS，EXECUTE=1 | FAIL。会话内 ENCRYPTBYKEY 夹具为 NULL，Decrypt 结果为空 | 静态 DECRYPTBYKEY。HR 没有 Encrypt / decodercontains 的 EXECUTE，未补授权 | 保持 pending |

`decodercontains(NULL, 1)` 的“结果是否为 NULL”为 0。这只说明空输入不是本次通过依据。

ecom 对 `sp_opensymmetric`、`sp_closesymmetric`、`Encrypt` 的 `OBJECT_ID` 为 NULL、EXECUTE=0。管理员能看到这些对象，所以这是调用方看不见，不是对象缺失。三个调用方对密钥 `Encrypt` / `EncryptCompany` 的 CONTROL 都是 0。

主库密钥权限只有 `insurer_connector_reader` 和 `telemed_db_writer` 的 `VIEW DEFINITION`。WebKit 与 SalesPortal 上这两把密钥没有任何 database permission 行。七个新 user 都不在其中。15151 与“调用方找不到密钥”一致。

建议、未执行：给 `sup_runtime_prod`（主库）和 `public_hr_runtime_prod`（WebKit）补对称密钥 `Encrypt` 的 `VIEW DEFINITION`，与主库已有服务账号一致，不给 CONTROL，也不给 `EncryptCompany`。WebKit 目前没有任何密钥授权，这会是该库第一条。补权前不能把 R060–R063、R094–R096 签收。`permission-matrix.json` 的十行状态仍是 `module_verified_dependencies_pending`。

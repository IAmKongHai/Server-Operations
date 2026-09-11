---
title: VTSI japitech.com 证书链缺 R1v1 中间证导致订单状态不返回
date: 2026-09-11
category: docs/solutions/nyh-prod/integration-issues
server: nyh-prod
module: nyh-prod / vtsi-smart
problem_type: integration_issue
component: background_job
symptoms:
  - vtsi_smart_check 不再回写订单状态，中心任务一直 status=1
  - stderr 只有 Exception: Failed to get valid SessionIdData，stdout 为空
  - 业务日志出现 SSLCertVerificationError: unable to get local issuer certificate，对端 japitech.com
root_cause: third_party_ssl_chain
resolution_type: documentation_update
severity: high
tags: [vtsi, vtsi-smart, japitech, ssl-cert, soap, supervisor, nyh-prod]
---

# VTSI japitech.com 证书链缺 R1v1 中间证导致订单状态不返回

## Problem

`vtsi_smart_check`（Supervisor 程序，查 VTSI 订单状态并回写南亚汇中心）从 2026-09-11 21:05 CST 起不再返回状态。表面错误是 `Failed to get valid SessionIdData`，真正失败点是拉 SOAP WSDL / `CreateSession` 时校验证书链失败。同一对端 `japitech.com` 上的 `vtsi-dito` / `vtsi-globe` 一起挂。

本条记录的是只读排查结论。对端证书链修好之前，本机重启 Supervisor **不能**恢复。

## Symptoms

- `vtsi_smart_check.out.log` 长期为空；`vtsi_smart_check.err.log` 反复 `Exception: Failed to get valid SessionIdData`
- 有时间戳的业务日志在 `logs/查询反馈独立进程_run_time.log*`：最后一次成功 session 21:04:24，第一次 SSL 失败 21:05:25
- `curl https://japitech.com/partners/soap/index.php?wsdl` 报 `SSL certificate problem: unable to get local issuer certificate`（curl 60 / openssl verify 20）；`curl -k` HTTP 200
- 中心 `InExecutingTasks` 仍 200，Smart 侧卡住 5 笔 `status=1`、`api_result=None`（order `1428147` `1428149` `1428150` `1428151` `1428152`）

## What Didn't Work

- 只看 Supervisor 配的 `.err.log` / `.out.log`：stderr 是 `getSessionId` 的包装异常，stdout 不用；根因在 `查询反馈独立进程_run_time.log` 的 `开启会话错误` / `An error occurred`
- 23:32 `supervisorctl` 全量重启：进程会变成 RUNNING，但 `SoapWeb.__init__` 建 zeep Client 失败时不设 `self.client`，之后变成 `'SoapWeb' object has no attribute 'client'`，30 次重试后仍返回 `{}`
- 本机 `ca-certificates`（20250419）和 venv `certifi` 都不是当天变更；叶子证书 `notBefore=2026-09-04`，故障窗口对齐的是对端开始送错中间证

## Root Cause

查单：`VtsiApi.Result` → `getSessionId` → `SoapWeb` zeep Client，WSDL `https://japitech.com/partners/soap/index.php?wsdl`。

对端送出的链：

故障刚发生时（2026-09-11 21:05）：

| 位置 | subject | issuer |
| --- | --- | --- |
| 叶子 | `CN=*.japitech.com` | `GoDaddy TLS Intermediate CA DV - R1v1` |
| 中间（错） | `Go Daddy Secure Certificate Authority - G2` | `Go Daddy Root Certificate Authority - G2` |
| 再往上 | Go Daddy Root G2 / Class 2 | 与叶子无关 |

2026-09-12 00:07 复测（japitech 让再试、用户已重启）叶子没变，链改成了：

| 位置 | subject | issuer |
| --- | --- | --- |
| 叶子 | `CN=*.japitech.com` | `GoDaddy TLS Intermediate CA DV - R1v1` |
| 下一张 | `GoDaddy TLS Root CA - R1` | `Go Daddy Root Certificate Authority - G2`（交叉签） |
| 再下一张 | `Go Daddy Root Certificate Authority - G2` | 自签 |

**始终缺** 签发叶子的中间证 `GoDaddy TLS Intermediate CA DV - R1v1`。校验器从叶子找不到 issuer，Python `requests`/`zeep` 仍拒绝握手（verify 20/21）。SOAP 服务本身还在（`-k` 200）。重启后 `SoapWeb` 建 Client 失败，错误变成 `'SoapWeb' object has no attribute 'client'`。

`common/soap_web.py` 捕获建连异常后只打日志，不重试、不设 `self.client`，所以全量重启后错误形态从 SSL 变成缺属性。

## Solution

正确修复在 japitech / VTSI：HTTPS 必须带上与叶子 issuer 一致的 `GoDaddy TLS Intermediate CA DV - R1v1`（官方 DER：`http://certificates.godaddy.com/repository/gd_tls_issuing_dv-r1v1.crt`），夹在叶子和 `GoDaddy TLS Root CA - R1` 之间。只放新根的交叉签、不放这张中间证，本机仍然校不过。不要关 SSL 校验。

链恢复后的验证：

```bash
curl -sS -o /dev/null -w '%{http_code} ssl=%{ssl_verify_result}\n' \
  --max-time 15 'https://japitech.com/partners/soap/index.php?wsdl'
# 期望 http=200 ssl=0

echo | openssl s_client -connect japitech.com:443 -servername japitech.com -showcerts 2>/dev/null \
  | openssl x509 -noout -issuer
# 叶子 issuer 仍是 R1v1 时，链里必须出现同名中间证

grep '新 session 获取成功' /www/wwwroot/python/vtsi-smart/logs/查询反馈独立进程_run_time.log | tail
```

不必为恢复而重启 `vtsi_smart_check`：进程还在，下一轮 `getSessionId` 会再试。23:32 那种全量重启之后若仍无 `self.client`，等对端修好再单独 `supervisorctl restart vtsi_smart_check`（以及 dito/globe 对应程序）。

卡住的 `status=1` 任务会重新进入轮询。若 VTSI 侧从未成功 `TOPUP`，回写会失败或对不上，需要对照后再人工关单。

## Prevention

- 查 VTSI 订单状态先看 `查询反馈独立进程_run_time.log`，不要只看 Supervisor stdout/stderr
- 出现 `Failed to get valid SessionIdData` 先 `curl` / `openssl s_client` 对端 WSDL，区分本机 CA、对端链、账号/IP 未授权（resultCode 5/6）
- 不要对 japitech SOAP 关 SSL 校验当修复
- 不要用 `supervisorctl restart all` 试这类第三方证书问题，会误伤其它队列

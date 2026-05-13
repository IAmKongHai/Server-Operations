---
title: 服务器重启后 nginx 启动失败 —— upstream 域名解析不到
date: 2026-05-13
server: dev-cypresso
category: runtime-errors
tags:
  - nginx
  - systemd
  - dns
  - boot-order
  - proxy_pass
severity: high
status: resolved
---

## 现象

- 服务器（AWS EC2，dev-cypresso）做了系统升级并重启，开机后 https://mas-icare.cypress.sg/ 打不开
- 容器都正常运行，但 443/80 没有进程在监听
- `systemctl is-active nginx` 返回 `failed`

## 根因

`/etc/nginx/conf.d/mas-icare.cypress.sg.conf` 里写的是：

```nginx
location /api/ {
  proxy_pass https://api-icare.cypress.sg/api/;
}
```

这种**直接把域名写死在 `proxy_pass` 里**的写法，nginx 在启动时（执行 `nginx -t` / 进程启动）就会**立刻**解析该域名。如果此时 DNS 尚未就绪，nginx 直接报 `[emerg] host not found in upstream` 并拒绝启动。

systemd 日志：

```
nginx[1987]: nginx: [emerg] host not found in upstream "api-icare.cypress.sg"
            in /etc/nginx/conf.d/mas-icare.cypress.sg.conf:5
systemd[1]: nginx.service: Failed with result 'exit-code'.
```

nginx 默认的 unit 文件**没有 `Restart=`**，于是这一次失败就永久 failed，不会自愈。

开机时序问题：虽然 unit 写了 `After=network-online.target nss-lookup.target`，但 `nss-lookup.target` 在很多系统上只表示本地 NSS 配置就绪、并不保证外网 DNS 真的能用，所以仍然可能比 DNS 早。

## 修复（双保险）

### 1. 改 nginx 配置：用变量形式的 upstream + resolver

让 nginx 启动时**不再强制解析 DNS**，运行时按需解析；即使解析失败也只影响该 location，不会拖垮整个 nginx。

`/etc/nginx/conf.d/mas-icare.cypress.sg.conf` 关键部分：

```nginx
server {
  server_name mas-icare.cypress.sg;

  resolver 1.1.1.1 8.8.8.8 valid=300s ipv6=off;
  resolver_timeout 5s;

  location /api/ {
    set $upstream_api "api-icare.cypress.sg";
    rewrite ^/api/(.*)$ /api/$1 break;     # 变量 proxy_pass 不会自动改写 URI，需手动 rewrite
    proxy_pass https://$upstream_api;
    proxy_ssl_server_name on;              # 转发 HTTPS 时必须发 SNI，否则上游可能拒
    proxy_ssl_name $upstream_api;
    proxy_set_header Host $upstream_api;
    # ...其余 header 保持不变
  }
}
```

要点：
- `proxy_pass` 后带变量 → nginx 启动时不解析 DNS
- `resolver` 必须显式声明（变量形式才会用到它）
- `proxy_ssl_server_name on` + `proxy_ssl_name` 确保转给上游的 TLS 握手有正确 SNI
- 加 `rewrite` 显式重写路径，避免变量形式下 URI 被改坏

### 2. 改 systemd unit：让 nginx 失败自愈

用 drop-in 文件，不动 vendor unit：

```ini
# /etc/systemd/system/nginx.service.d/override.conf
[Unit]
StartLimitBurst=10
StartLimitIntervalSec=300

[Service]
Restart=on-failure
RestartSec=10s
```

注意 `StartLimitBurst` / `StartLimitIntervalSec` 在新版 systemd 里必须放在 `[Unit]` 段，放 `[Service]` 不报错但不生效（用 `systemctl show nginx.service -p StartLimitIntervalUSec` 验证）。

应用：

```bash
sudo systemctl daemon-reload
```

## 验证

```bash
# 配置生效
systemctl show nginx.service -p Restart -p RestartUSec -p StartLimitIntervalUSec -p StartLimitBurst
# => Restart=on-failure / RestartUSec=10s / StartLimitIntervalUSec=5min / StartLimitBurst=10

# 站点恢复
curl -sS -o /dev/null -w "%{http_code}\n" https://mas-icare.cypress.sg/      # 200
curl -sS -o /dev/null -w "%{http_code}\n" https://mas-icare.cypress.sg/api/  # 404（上游本身就是 404，链路通）
```

## 经验

- nginx 配置里**任何用域名表示的 upstream** 都应该用变量 + resolver 写，而不是直接写域名
- 任何关键服务的 systemd unit 都应该有 `Restart=on-failure`（vendor 默认往往没有）
- `nss-lookup.target` 不等于"DNS 可用"，不能光靠它解决开机顺序问题
- 备份原配置：`/etc/nginx/conf.d/mas-icare.cypress.sg.conf.bak.20260513`

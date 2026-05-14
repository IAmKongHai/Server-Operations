---
title: xiao-linux 安装 SQL Server 2017 + FTS 容器（对齐 dev-cypresso）
date: 2026-05-14
category: docs/solutions/xiao-linux/workflow-issues
server: xiao-linux
module: xiao-linux / sqlserver
problem_type: workflow_issue
component: tooling
severity: low
tags:
  - mssql
  - sqlserver-2017
  - docker
  - full-text-search
  - cn-network
---

## 目标

在 `xiao-linux` 上跑一个 SQL Server 容器，**版本与 `dev-cypresso` 一字不差**（`14.0.3520.4` + FTS），作为开发测试库。

为什么要"一字不差"：业务 schema、FTS catalog、SQL 兼容性级别在不同 minor build 间可能微调，开发测试机用同一 build 能避免"在测试通过、生产挂掉"或反过来。

## 关键发现：网络

xiao-linux 在境内，连境外的连通性：

```bash
$ curl -sS -o /dev/null -w "%{http_code} %{time_total}s\n" --max-time 8 \
    https://mcr.microsoft.com/ \
    https://packages.microsoft.com/ \
    https://registry-1.docker.io/
mcr.microsoft.com        : 200  0.88s   ✓
packages.microsoft.com   : 200  0.33s   ✓
registry-1.docker.io     : 000  超时    ✗
```

**结论**：SQL Server 容器需要的两个域名都直连可用，**完全不需要代理**。Docker Hub 不通是另一回事，今天不解决。

## 步骤

### 1. 装 Docker（清华镜像源）

`download.docker.com` 也是境外站点（同样不通），所以走清华镜像：

```bash
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg \
  | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] \
https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu $(lsb_release -cs) stable
EOF

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
```

得到：Docker CE `29.4.3` + Compose `v5.1.3`。

### 2. 准备 stack 目录

`/opt/stacks/sqlserver/`：

```
/opt/stacks/sqlserver/
├── docker-compose.yml
├── .env                  # chmod 600，含 SQLSERVER_SA_PASSWORD
├── .gitignore            # 排除 .env
└── mssql-fts/
    └── Dockerfile        # 与 dev-cypresso 一字不差
```

`mssql-fts/Dockerfile`：

```dockerfile
FROM mcr.microsoft.com/mssql/server:2017-latest
USER root
RUN printf '%s\n' 'deb [arch=amd64,armhf,arm64] https://packages.microsoft.com/ubuntu/18.04/mssql-server-2017 bionic main' > /etc/apt/sources.list.d/mssql-server-2017.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends mssql-server=14.0.3520.4-1 mssql-server-fts=14.0.3520.4-1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

`docker-compose.yml`（dev-cypresso 上是同一份 infra compose 的一段，这里抽出来独立跑）：

```yaml
services:
  sqlserver:
    build:
      context: ./mssql-fts
    image: shared-sqlserver-fts:2017-cyp327
    container_name: shared-sqlserver
    restart: unless-stopped
    mem_limit: 4g
    environment:
      ACCEPT_EULA: "Y"
      MSSQL_SA_PASSWORD: ${SQLSERVER_SA_PASSWORD:?需在 .env 中设置 SQLSERVER_SA_PASSWORD}
      MSSQL_PID: Developer
    ports:
      - "127.0.0.1:1433:1433"
    volumes:
      - sqlserver_data:/var/opt/mssql

volumes:
  sqlserver_data:
```

### 3. 启动并验证

```bash
cd /opt/stacks/sqlserver
docker compose up -d --build
# build ~6 分钟（基础镜像 ~430 MB + apt 装 FTS 包 ~450 MB）

# 等待就绪并查版本
docker exec shared-sqlserver /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P "$SQLSERVER_SA_PASSWORD" \
  -Q "SELECT @@VERSION"
```

输出（与 dev-cypresso 对比一致）：

```
Microsoft SQL Server 2017 (RTM-CU31-GDR) (KB5077471) - 14.0.3520.4 (X64)
    Feb 13 2026 16:31:53
    Copyright (C) 2017 Microsoft Corporation
    Developer Edition (64-bit) on Linux (Ubuntu 18.04.6 LTS)
```

`ProductVersion=14.0.3520.4`、`Edition=Developer Edition (64-bit)`、`IsFullTextInstalled=1`。

## 设计决策

- **没装代理 / 走 mac-mini 转发**：先实测连通性，确认能直拉就不绕道，避免引入 systemd drop-in、`HTTP_PROXY` 环境变量、单点依赖 mac-mini 等复杂度
- **`restart: unless-stopped`**：xiao-linux 是测试机；如改作生产再改成 `always`（参见 AGENTS.md 关于 nas 容器策略的规定）
- **`mem_limit: 4g`**：和 dev-cypresso 一致
- **端口仅 `127.0.0.1`**：外部连接走 SSH 隧道 `ssh -L 1433:127.0.0.1:1433 xiao-linux`，不暴露 1433 到 Tailscale 网络（最小权限原则）
- **`.env` 文件 + `.gitignore`**：密码留服务器本机，仓库只在 `dev-cypresso/secrets.local.md`（也是 `.gitignore` 排除）里有一份
- **没用 docker named network**：单容器场景没必要；将来如要加同栈服务（如 redis），再补 `networks` 段

## 回滚

```bash
cd /opt/stacks/sqlserver
docker compose down -v          # -v 同时删卷，数据全清；保留数据则去掉 -v
docker image rm shared-sqlserver-fts:2017-cyp327 mcr.microsoft.com/mssql/server:2017-latest
rm -rf /opt/stacks/sqlserver
```

卸载 docker：

```bash
apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
rm -rf /var/lib/docker /var/lib/containerd
rm /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
```

## 相关

- [dev-cypresso README](../../../../dev-cypresso/README.md) — 原版 SQL Server 容器的来源
- [xiao-linux README](../../../../xiao-linux/README.md)
- [xiao-linux 初始化记录](initial-setup-2026-05-14.md)

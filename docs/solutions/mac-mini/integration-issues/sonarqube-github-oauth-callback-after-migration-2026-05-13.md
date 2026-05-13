---
title: SonarQube 迁移到新 host 后 GitHub OAuth 登录失效（serverBaseURL + GitHub App callback URL 未同步）
date: 2026-05-13
category: docs/solutions/mac-mini/integration-issues
server: mac-mini
module: mac-mini / SonarQube + GitHub App
problem_type: integration_issue
component: tooling
severity: medium
symptoms:
  - 团队成员在 http://mac-mini:9000 点 "Log in with GitHub" 后被跳到旧 host 的回调地址，登录中断
  - 旧 host (sonar.cypresso.ai) 在 dev-cypresso 上 sonarqube 容器停止后已不可达
  - 本地登录（用户名/密码）仍正常工作，仅 OAuth 链路失效
root_cause: config_error
resolution_type: configuration_change
tags: [sonarqube, github-oauth, github-app, mac-mini, migration, post-migration-task]
---

# SonarQube 迁移到新 host 后 GitHub OAuth 登录失效

## Problem

2026-05-13 把 SonarQube 从 `https://sonar.cypresso.ai`（dev-cypresso + nginx 反代）迁到 `http://mac-mini:9000`（mac-mini tailscale 内网）后，团队成员从新 host 用 "Log in with GitHub" 登录时被跳到旧 host 的 callback URL，登录卡住。

## Root Cause

GitHub OAuth 回调链有两端配置都依赖 host 字符串，**迁移时都没自动跟着改**：

1. **SonarQube 端**：`sonar.core.serverBaseURL` 仍指向 `https://sonar.cypresso.ai/`
   - SonarQube 用这个值拼回调 URL：`{serverBaseURL}/oauth2/callback/github`
   - 用户点 "Log in with GitHub" 时被发送 `redirect_uri=https://sonar.cypresso.ai/oauth2/callback/github`
   - GitHub 授权通过后把用户重定向回这个 URL，但旧 host 已不可达
2. **GitHub App 端**：App ID `3241671` 的 Authorization callback URL 仍只有 `https://sonar.cypresso.ai/oauth2/callback/github`
   - 即使 SonarQube 改了 serverBaseURL，如果 GitHub App 那边没添加新 callback URL，GitHub 会以 "redirect_uri 不在 allowlist" 拒绝授权

数据库现状（用于排查）：

```sql
SELECT prop_key, text_value
FROM properties
WHERE prop_key LIKE '%github%' OR prop_key = 'sonar.core.serverBaseURL';

-- 关键行：
--   sonar.core.serverBaseURL                | https://sonar.cypresso.ai/   ← 旧值
--   sonar.auth.github.enabled               | true
--   sonar.auth.github.appId                 | 3241671                       ← GitHub App，不是 OAuth App
--   sonar.auth.github.organizations         | cypressoai
```

`sonar.auth.github` 系列里**没有** `callbackUrl` 字段——这个由 `serverBaseURL` 派生，不能单独配。

## Resolution（两端都要改）

### 1. SonarQube 端：改 serverBaseURL

UI：以 admin 登录 → **Administration → Configuration → General → Server base URL** → 改为：

```
http://mac-mini:9000/
```

Save。**不需要重启 sonarqube**——SonarQube 的 system settings 实时生效。

> 改完后 SonarQube 拼出的回调 URL 变成 `http://mac-mini:9000/oauth2/callback/github`。

### 2. GitHub App 端：加新 callback URL

GitHub 网页：
- 组织安装：`https://github.com/organizations/cypressoai/settings/apps`
- 个人安装：`https://github.com/settings/apps`

找到 App ID **3241671**（对应 client id `Iv23liHhhN7vCUBgTiCO`）→ Edit → **Callback URL** → 加入：

```
http://mac-mini:9000/oauth2/callback/github
```

> Callback URL 字段支持多个 URL（换行分隔）。**建议把旧的 `https://sonar.cypresso.ai/oauth2/callback/github` 暂时也保留**——万一回滚需要时不用再改。等彻底废弃 dev-cypresso 上的 SonarQube 部署再删旧 URL。

Save。

### 3. 验证

打开 `http://mac-mini:9000` → 点 "Log in with GitHub" → GitHub 授权 → 跳回 `http://mac-mini:9000` 并已登录。

## Lessons

- **任何"迁主机"操作都要同步排查 OAuth 回调链**。涉及 OAuth / OIDC 的应用普遍存在以下"host 字符串依赖"，迁移时一定要清点：
  - 服务端的 base URL / canonical URL 配置（如 SonarQube `sonar.core.serverBaseURL`、Discourse `force_https`、Mattermost `SiteURL`）
  - OAuth Provider 端的 Authorization callback URL 白名单（GitHub App、GitLab Application、Google OAuth Client ID）
  - 反代层的 Host header rewrite（如果走 nginx）
- **GitHub App vs OAuth App 行为不同**：本次配的是 GitHub App（看 `sonar.auth.github.appId` + RSA `privateKey` 即可判定），相比 OAuth App 安全模型更严，callback URL 白名单是硬限制。迁移前查清楚是哪种。
- **`xxx.secured` properties 字段名误导**：DB 里 `clientSecret.secured`、`privateKey.secured` 看上去像加密的，实际是**明文**——只是 UI 显示时打码。`sonar_db` 本身的访问控制才是真正的安全边界。任何能读到 sonar 库的人都拿到了 GitHub App 私钥。
- **可重用的迁移 checklist 应该把这一条写进**：`docs/runbooks/sonarqube-upgrade.md` 和未来任何"换 host" 类操作的 runbook 里，都要明确列出"OAuth 回调链同步"作为必经验证项。

## Related

- 迁移交接文档：[`docs/solutions/mac-mini/sonarqube-migrated-from-dev-cypresso-2026-05-13.md`](../sonarqube-migrated-from-dev-cypresso-2026-05-13.md)
- 升级 runbook（未来升级 SonarQube 时也涉及 host）：[`docs/runbooks/sonarqube-upgrade.md`](../../../runbooks/sonarqube-upgrade.md)

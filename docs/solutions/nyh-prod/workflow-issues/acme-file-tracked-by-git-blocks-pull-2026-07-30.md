---
title: 被 git 跟踪的 ACME 验证文件让生产站点 git pull 长期失败，gitignore 对已跟踪文件无效
date: 2026-07-30
category: docs/solutions/nyh-prod/workflow-issues
server: nyh-prod
module: nyh-prod / load.nanyahui.com 代码部署
problem_type: workflow_issue
component: development_workflow
severity: medium
symptoms:
  - "git pull 报 error: cannot pull with rebase: You have unstaged changes."
  - "git status 显示 ` D public/.well-known/acme-challenge/<token>`，且该删除不是人为改动"
  - ".gitignore 里明明已经写了 public/.well-known/，但删除变更依旧每次出现"
  - "站点根目录 .well-known/ 长期挂着未跟踪状态（??），忽略规则从未生效过"
root_cause: incomplete_setup
resolution_type: workflow_improvement
applies_when:
  - "服务器上的站点目录本身就是 git 工作区，同时又跑 Let's Encrypt / ACME 自动续签"
  - "git status 出现 D 但 .gitignore 看起来已经覆盖了该路径"
tags: [git, gitignore, acme, lets-encrypt, ssl-cert, baota, deploy, pull-rebase]
---

# 被 git 跟踪的 ACME 验证文件让生产站点 git pull 长期失败

## Context

`nyh-prod` 上的 `/www/wwwroot/load.nanyahui.com` 既是 Nginx 站点根目录，也是
`nyhAgent` 仓库的 git 工作区。部署方式就是在这个目录直接 `git pull`。

这台机器同时跑 Let's Encrypt 自动续签，HTTP-01 验证会往站点里写一次性 token 文件，
验证完再清掉。于是「证书续签」和「代码部署」共用了同一个目录，两套自动化互相踩脚：

```
$ git pull
error: cannot pull with rebase: You have unstaged changes.
error: Please commit or stash them.

$ git status --porcelain
 D public/.well-known/acme-challenge/C-T2aLYKg52DrfdkV-ojqpfQsxC0xXt0bfyNX-2_CAE
?? .well-known/
?? _pc_frontend_backup_20260526_161925.tar.gz
?? application/middleware.php.bak.20260526_143413
```

迷惑点在于：`.gitignore` 里**早就有** `public/.well-known/` 这一行，注释还写明了
「为了避免以后频繁写入导致 git pull 失败」。规则在，问题照旧。

## Guidance

### 核心判据：先查是否被跟踪，而不是反复补忽略规则

**`.gitignore` 只对「未被跟踪」的文件生效。文件一旦进过某个提交，忽略规则对它完全无效。**

所以 `git status` 里出现 `D`（已跟踪文件被删除）且 `.gitignore` 明明覆盖了该路径时，
不要再去改忽略规则 —— 先确认这个文件是不是历史上被误提交过：

```bash
# 是否被跟踪？有输出就是被跟踪了，忽略规则救不了它
git ls-files public/.well-known/

# 是哪个提交带进来的
git log --oneline -- public/.well-known/
```

本例查出该 token 文件是在仓库初始化提交 `e9777584` 时被一起 `git add .` 进去的。

### 修复：取消跟踪，让已有的忽略规则真正生效

在**本地开发仓库**做，不要在生产上改：

```bash
# --cached 只动索引，磁盘文件保留（证书续签流程不受影响）
git rm -r --cached public/.well-known/
```

同时补全忽略路径。宝塔的 webroot 布局有两种，站点根目录和 `public/` 下都会被写入，
原来只忽略了后者：

```gitignore
# 自动化证书续签（Let's Encrypt / ACME）生成的一次性验证文件。
# 两处路径都会被写：宝塔按站点根目录或 public/ 作为 webroot 都出现过,所以一起忽略。
/.well-known/
/public/.well-known/
```

提交推送后，生产端只负责 `pull`，不在生产产生任何提交（否则生产分支领先远端，
以后每次 pull 都变成 merge）。

### 生产端解阻塞：恢复删除，而不是 stash

生产工作区那条 `D` 挡着 pull。**恢复**它让工作区干净即可：

```bash
git checkout -- public/.well-known/acme-challenge/<token>
git pull --ff-only origin main
```

不用 `git stash`，也不用在生产 commit —— 拉下来的新提交本身就会把该文件从版本控制里
移除，净效果一致，而且生产端保持纯粹的 fast-forward。

### 加忽略规则前先确认不会误伤

同一批清理里还要忽略服务器上的临时备份产物（`*.tar.gz`、`*.bak`、`*.bak.*`）。
加这类宽泛规则前，先确认仓库里没有需要入库的同类文件：

```bash
git ls-files | grep -E '\.tar\.gz$|\.bak'   # 无输出才安全
```

改完用 `git check-ignore` 逐条验证规则真的命中。`--no-index` 很关键 —— 它让你能对
「本地不存在或尚未跟踪」的路径做规则模拟，不必真去生产上造文件：

```bash
git check-ignore --no-index -v public/.well-known/acme-challenge/9_siw...
git check-ignore --no-index -v .well-known/acme-challenge/YOjd5...
```

## Why This Matters

三层原因叠加才让这个问题「长期存在又看起来无解」：

1. **gitignore 语义**：对已跟踪文件无效。只看 `.gitignore` 有没有写，永远查不出根因，
   这也是之前那条规则加了却没用的原因。
2. **ACME 的清理行为**：验证文件是一次性的，续签完成后会被删除。所以症状**周期性复发**
   而不是一直存在，容易被当成偶发问题放过去。
3. **`pull.rebase=true` 放大后果**：这个站点配了 rebase 式 pull，而 rebase 要求工作区
   **完全干净**。普通 merge 式 pull 对「本地删了、上游也删了」这种情况通常能容忍，
   rebase 直接拒绝执行 —— 部署被彻底卡死，而不只是提示一句脏状态。

第 3 点值得单独记：同样的脏工作区，`pull.rebase` 开与不开的后果差别很大。排查 pull
失败时，先看一眼 `git config --get pull.rebase`。

## When to Apply

- 服务器站点目录本身是 git 工作区，同时又跑 ACME/certbot 自动续签
- `git status` 出现 `D` 或 `??`，但 `.gitignore` 看起来已经覆盖了该路径
- 部署用的 `git pull` 报 `cannot pull with rebase: You have unstaged changes.`
- 准备往 `.gitignore` 加宽泛通配规则（`*.tar.gz`、`*.bak` 等）之前

## Examples

排查到修复的完整命令序列：

```bash
# 1. 定位：是被跟踪，不是忽略规则没写
git ls-files public/.well-known/
# → public/.well-known/acme-challenge/C-T2aLY...   （有输出 = 被跟踪）
git log --oneline -- public/.well-known/
# → e9777584 初始化代码仓库                        （误提交源头）

# 2. 确认放大因素
git config --get pull.rebase
# → true                                          （rebase 要求工作区干净）

# 3. 本地仓库修复
git rm -r --cached public/.well-known/
# 编辑 .gitignore：/.well-known/ + /public/.well-known/ + *.tar.gz + *.bak*
git ls-files | grep -E '\.tar\.gz$|\.bak'         # 空 → 新规则不会误伤
git check-ignore --no-index -v <每个目标路径>      # 逐条验证命中
git commit && git push

# 4. 生产端解阻塞并更新
git checkout -- public/.well-known/acme-challenge/C-T2aLY...
git pull --ff-only origin main                     # fast-forward，无 merge 提交

# 5. 验证
git status --porcelain                             # 空
git rev-list --left-right --count HEAD...origin/main   # 0  0
git ls-files | grep well-known                     # 无结果
ls .well-known/acme-challenge/ public/.well-known/acme-challenge/  # 目录与验证文件完好
```

最后一条验证不能省：修复的是版本控制状态，**证书续签能力必须完好无损**。

## Related

- `docs/operations/nyh-prod.md` — 2026-07-30 15:05 CST 本次操作时间线（含回滚方式）
- `docs/solutions/nyh-prod/integration-issues/baota-ssl-acme-challenge-routing-fix-2026-05-19.md`
  — 同一台机器上 ACME HTTP-01 验证的另一类问题：Nginx 把 `.well-known` 请求路由错了导致
  续签失败。两篇的共同点是 acme-challenge 目录同时被证书流程和站点配置/版本控制争用。

# 本机已安装 CLI 工具清单

本清单记录当前 macOS 本机已安装且 Agent 可直接调用的 CLI 工具，避免重复摸索或误用网页抓取。

## 凭据与环境变量约定

- 敏感环境变量统一存放在 `~/.config/secrets.env`（权限 `600`，不入 Git），由 `~/.zshrc` 自动 `source`。
- 当前已注入的变量名：`SONAR_TOKEN`、`CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID`。
- 非交互式 shell 若未加载 `~/.zshrc`，执行相关命令前可先 `source ~/.config/secrets.env`。
- 注意：不要在文档、日志或提交记录中输出任何明文 Token、密钥或 AK/SK。

---

## 1. 云厂商与基础设施（已配凭据优先）

- **Cloudflare CLI (`cf` / `cloudflare`)**：全局 npm 包，使用 `CLOUDFLARE_API_TOKEN`（权限 `Zone:Read` + `DNS:Edit`，覆盖 `All zones`）与 `CLOUDFLARE_ACCOUNT_ID`。常用命令：
  - 查域名 / Zone ID：`cf zones list`
  - 查解析记录：`cf dns records list -z <域名或ZoneID>`
  - 新增解析前先加 `--dry-run` 预演（例如 `cf dns records create -z <域名或ZoneID> --body '{"type":"A","name":"sub","content":"1.2.3.4","proxied":false}' --dry-run`）；修改或删除已有生产域名解析记录前必须先征得用户确认。
- **`cloudflared`**：Cloudflare Tunnel 客户端（Homebrew）。
- **`aliyun`**：阿里云 CLI，已配置 profile `default`（默认、`cn-hongkong`）与 `new-hk`（`cn-hongkong`）。
- **`aws` / `aws-vault`**：AWS CLI 与凭据管理，已配置 profile `default`、`bb1`、`konghai`。
- **`az`**：Azure CLI，已登录账号（注意：mac-mini CI runner 仍各自走独立配置与 OIDC）。
- **`gcloud` / `gsutil` / `bq`**：Google Cloud CLI（Homebrew cask `gcloud-cli`），已登录 `konghai007@gmail.com`；当前未设置默认 project，执行项目级命令时需指定 `--project <PROJECT_ID>`（可先 `gcloud projects list` 查看可用项目）。
- **`coscli`**：腾讯云 COS 对象存储 CLI（`~/.local/bin/coscli`，配置文件 `~/.cos.yaml`）。
- **`terraform`**：HashiCorp 官方 tap，用于基础设施即代码（IaC）。
- **`docker` / `kubectl` / `tailscale`**：本地位于 `/usr/local/bin/`（容器、Kubernetes、Tailscale 组网状态查询）。

---

## 2. 代码托管、工单、文档与可观测性

- **`gh`**：GitHub CLI，已登录 `IAmKongHai`（keyring 凭据，含 `repo` / `workflow` / `admin:org` 等权限）。
- **`moo`**：Moo Ticket 工单 CLI（`~/.local/bin/moo`）。凡提到 `https://t.moospark.com/` 的工单链接（如 `https://t.moospark.com/tickets/ICARE-15`），一律用 `moo-ticket-cli` skill（`moo` 命令）查询/评论/流转，不要用 WebFetch 或浏览器抓页面。
- **SonarQube (`curl` + `$SONAR_TOKEN`)**：服务器地址 `http://mac-mini:9000`，可直接查询：

  ```bash
  curl -s -u "$SONAR_TOKEN:" "http://mac-mini:9000/api/issues/search?componentKeys=<projectKey>&pullRequest=<PR号>&resolved=false"
  curl -s -u "$SONAR_TOKEN:" "http://mac-mini:9000/api/qualitygates/project_status?projectKey=<projectKey>&pullRequest=<PR号>"
  ```

- **`jira`**：Jira CLI（配置文件 `~/.config/.jira/.config.yml`）。
- **`notion-cli`**：Notion CLI（`~/go/bin/notion-cli`，凭据 `~/.config/notion-cli/token.json`）。
- **`pup`**：Datadog CLI（`datadog-labs/pack/pup`，会话 `~/.config/pup/sessions.json`）。
- **`workspace-cli`**：Google Workspace CLI（`~/.local/bin/workspace-cli`，`uv` 安装）。
- **Git / CI 辅助**：`actionlint`（GitHub Actions workflow 静态检查）、`lazygit`、`git-filter-repo`。

---

## 3. 浏览器自动化与 AI Agent 工具

- **浏览器自动化**：
  - `ego-browser`（`~/.local/bin/ego-browser`）：**首选**，可复用用户已登录网站与个人上下文（配合 `ego-browser` skill 使用）。
  - `agent-browser`（npm 全局）：备选无头/沙箱浏览器自动化 CLI。
- **AI Agent / 协作 CLI**：`agy`、`claude`、`codex`、`gemini`、`cursor-agent`、`grok`、`paseo`、`pi`、`multica`。

---

## 4. 移动端与跨端构建/调试

- **React Native / Expo**：`eas`（`eas-cli`）
- **iOS**：`fastlane`、`pod`（CocoaPods）、`xcodegen`、`xcrun`、`ios-deploy`、`ideviceinstaller`
- **Android**：`adb`、`bundletool`
- **E2E UI 测试**：`maestro`（`~/.maestro/bin/maestro`）

---

## 5. 语言运行时、包管理与代码质量

- **JS / TS**：`node`（`fnm` 管理）、`npm`、`pnpm`、`bun` / `bunx`、`typescript-language-server`
- **Go**：`go`、`gopls`、`golangci-lint`、`air`、`swag`、`migrate`、`dupl`、`orchestrion`
- **Python**：`uv` / `uvx`、`pyenv`、`pipx`、`poetry`、`pyright`、`bench`（frappe-bench）
- **Rust / PHP / Java / Lua**：`rustup` / `cargo` / `rust-analyzer`、`php`、`openjdk@17`、`lua`

---

## 6. 数据库、搜索与常用效率工具

- **数据库客户端**：`mysql`（`mysql-client`）、`sqlcmd`（MSSQL）、`redis-cli`（ServBay）
- **代码与文本搜索**：`rg`（ripgrep）、`fd`、`sg`（ast-grep）、`jq`、`bat`、`tokei`、`tree`、`fzf`
- **媒体与文档处理**：`ffmpeg`、`magick`（ImageMagick）、`pandoc`、`qpdf`、`poppler`（`pdftoppm` / `pdftotext`）、`resvg`、`silicon`
- **同步、网络与压缩**：`rsync`、`wget`、`sshpass`、`openvpn`、`7z`（`p7zip` / `sevenzip`）、`chezmoi`

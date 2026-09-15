# 我的 Mac 终端插件与工具清单（分享版）

整理日期：2026-09-16。环境：macOS 26.6.2，Apple Silicon（arm64），默认 Shell 为 `/bin/zsh`（5.9）。

这套终端配置的核心是：**Zsh + Oh My Zsh + Powerlevel10k + 自动建议 + 语法高亮 + fzf + zoxide + lsd + Nerd Font**。

以下根据本机配置、安装目录和版本信息整理。“已启用”指启动配置中已写入加载项、对应文件或命令存在；本次未重新启动交互式 Shell 验证每个功能，也未修改终端环境。终端应用的安装情况不代表日常使用频率。

## 1. Shell 框架、主题和插件

| 名称 | 类型 | 用来做什么 | 本机状态 |
| --- | --- | --- | --- |
| Zsh | Shell | 解释执行命令，提供补全、历史记录等基础能力 | 默认登录 Shell，5.9 |
| Oh My Zsh | 配置框架 | 集中加载主题、插件和常用 Shell 配置 | 已启用，位于 `~/.oh-my-zsh` |
| Powerlevel10k（p10k） | 提示符主题 | 美化命令提示符，展示目录、Git 状态等信息 | 已启用；存在 `~/.p10k.zsh`，配置了 instant prompt |
| `git` | Oh My Zsh 内置插件 | 提供 Git 命令别名，例如 `gst`、`gco` | 已启用 |
| `zsh-autosuggestions` | Zsh 插件 | 输入时根据历史命令显示建议 | 已启用，自定义插件目录安装 |
| `zsh-syntax-highlighting` | Zsh 插件 | 输入时给命令、参数等添加语法颜色 | 已启用，自定义插件目录安装 |

当前 `plugins=(...)` 中实际启用的插件只有上面 **3 个**。Oh My Zsh 自带的其他插件目录不等于全部启用。

核心配置摘录如下，仅用于说明组合方式，并非完整配置文件：

```zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source "$ZSH/oh-my-zsh.sh"
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
```

## 2. 已接入 Zsh 的效率工具

这些是独立命令行工具，通过初始化配置接入终端。

| 工具 | 本机版本 | 作用 | 当前配置 |
| --- | --- | --- | --- |
| `fzf` | 0.72.0 | 模糊搜索文件、目录、命令历史 | 通过 `fzf --zsh` 加载补全与快捷键 |
| `fd` | 10.4.2 | 按名称查找文件和目录 | 作为 fzf 默认文件列表来源 |
| `zoxide` | 0.9.9 | 按使用记录快速跳转目录 | 已执行 `zoxide init zsh` 初始化配置，提供 `z` 等命令 |
| `lsd` | 1.2.0 | 带颜色和图标的文件列表 | `lsd`、`ll` 都被配置为执行 `lsd -l`；命令位于 `~/.cargo/bin/lsd` |

当前 fzf、zoxide 和列表命令配置：

```zsh
export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

alias lsd='lsd -l'
alias ll='lsd -l'
```

### 常用操作速查

| 操作 | 效果 |
| --- | --- |
| 输入命令后按右方向键 | 接受自动建议（默认绑定） |
| `Ctrl+R` | 用 fzf 搜索命令历史 |
| `Ctrl+T` | 用 fzf 选文件并插入当前命令；本机文件来源是上述 fd 配置 |
| `Alt+C` | 用 fzf 选择目录并跳转；macOS 终端需要将 Option 配置为 Alt 才方便使用 |
| `z 目录关键词` | 跳转到匹配的常用目录 |
| `ll` | 显示带图标的详细文件列表 |
| `gst` | 执行 `git status` |
| `gco 分支名` | 执行 `git checkout 分支名` |
| `p10k configure` | 交互式调整 Powerlevel10k 外观 |

## 3. 已安装的其他终端工具

这一节列出终端日常操作相关工具，不展开所有开发语言、云平台 CLI 和 Homebrew 依赖库。版本取自本机 Homebrew 安装记录，不代表最新版或每个终端窗口实际命中的版本。

| 工具 | 本机安装版本 | 用途 / 使用入口 |
| --- | --- | --- |
| `bat` | 0.26.1 | 带语法高亮的文件查看：`bat 文件名` |
| `ripgrep` | 15.1.0 | 搜索文件内容：`rg 关键词` |
| `lazygit` | 0.60.0 | 终端内的 Git 操作界面：`lazygit` |
| `yazi` | 26.1.22 | 终端文件管理器：`yazi`；本机有 `yazi.toml` 和 `keymap.toml` |
| `bottom` | 0.12.3 | 查看 CPU、内存和进程等资源：`btm` |
| `macmon` | 0.7.2 | Apple Silicon 系统监控 |
| `tree` | 2.1.1_1 | 树状展示目录结构 |
| `jq` | 1.8.1 | 格式化和处理 JSON |
| `gh` | 2.100.0 | GitHub 命令行工具 |
| `chezmoi` | 2.70.2 | 管理和同步个人配置文件 |
| `terminal-notifier` | 2.0.0 | 从命令行发送 macOS 通知 |
| `vhs` | 0.11.0 | 录制、生成终端演示 |
| `silicon` | 0.5.3 | 生成代码截图 |
| `Starship` | 1.25.1 | 另一款提示符主题；已安装且有配置文件，但当前 Zsh 未加载，当前主题是 p10k |
| `Nushell` | 0.108.0 | 另一款 Shell；已安装，默认 Shell 仍为 Zsh |

## 4. 开发环境与命令补全

| 项目 | 当前状态 |
| --- | --- |
| `fnm` 1.38.1 | Node.js 版本管理；Zsh 配置了 `fnm env --use-on-cd`，切换目录时可按项目版本配置切换 Node.js |
| `pyenv` 2.6.26 | Python 版本管理；Zsh 配置了 `pyenv init -` |
| Bun 补全 | Zsh 配置了加载 `~/.bun/_bun` |
| Docker CLI 补全 | Zsh 将 `~/.docker/completions` 加入 `fpath`，并调用 `compinit` |
| clauth 补全 | Zsh 配置了加载 `~/.clauth/completions/clauth.zsh` |
| Grok 补全 | Zsh 将 `~/.grok/completions/zsh` 加入 `fpath` |

另外，配置中还有 Volta、Cargo、ServBay、Android SDK、Java 等开发环境路径。这些属于具体开发环境设置；朋友复用终端外观和效率工具时，可以根据自己的开发需求另行配置。

## 5. 终端应用与字体

### 已安装的终端应用

应用版本读取自各 `.app` 的 `Info.plist`。

| 应用 | 本机版本 | 已核实的外观或集成配置 |
| --- | --- | --- |
| iTerm2 | 3.7.1 | 保存的 Profile 使用 `JetBrainsMonoNFM-Regular`，字号 15 |
| Ghostty | 1.3.1 | JetBrainsMono Nerd Font Mono，字号 15；深色 Catppuccin Mocha、浅色 TokyoNight Day；透明度 0.95 |
| kitty | 0.48.2 | JetBrainsMono Nerd Font，字号 16；中文回退 Noto Sans CJK SC；顶部 Powerline 标签栏；Option 作为 Alt |
| Alacritty | 0.17.0 | 已安装 |
| Otty | 1.4.1 | 存在用户配置，主题字段为 Paper；Bash 中有条件式 Shell Integration 加载配置 |

本机还安装了 `iTermBrowserPlugin.app`，这里只确认应用文件存在，未验证其在 iTerm2 内的启用状态。

### 字体

本机安装了多套 Nerd Fonts，其中与现有终端配置直接相关的是：

- **JetBrainsMono Nerd Font / Mono**：iTerm2、Ghostty、kitty 配置中使用的字体，提供终端图标所需字形。
- **Noto Sans CJK SC**：kitty 的中文回退字体。
- **Meslo LG Nerd Font**：已安装；本次检查的上述应用配置未将它设为当前字体。

另外安装了 Hack、Iosevka、Mononoki、Ubuntu、Noto、Lilex 等 Nerd Font 家族；复用这套配置无需安装全部字体。

## 6. 复用时需要知道的事

- 框架、主题、插件、独立工具和终端应用需要分别安装；仅复制 `plugins=(...)` 不会自动安装插件。
- 示例摘录用于理解当前组合，未包含完整的 p10k instant prompt、字体和终端应用配置。
- 当前配置文件中有项目路径、服务环境变量和私人设置，分享本清单即可，不要直接转发完整 `~/.zshrc`。
- 本机保留了 Fish 配置目录，但未找到 `config.fish`、`fish_plugins`，当前 PATH 也未找到 `fish`，因此没有把 Fish 插件列为已安装项。

### 本次核对依据

- Shell：用户账户默认 Shell、`~/.zshrc`、`~/.zprofile`、`~/.zshenv`、`~/.bashrc`、`~/.bash_profile`。
- 插件：`~/.oh-my-zsh/plugins/git/`、`~/.oh-my-zsh/custom/plugins/`、`~/.oh-my-zsh/custom/themes/`、`~/.p10k.zsh`。
- 工具：Homebrew 安装记录、命令路径、`lsd --version`。
- 外观：iTerm2 偏好文件、`~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`、`~/.config/kitty/kitty.conf`、`~/.config/otty/config.toml`、`~/Library/Fonts/`。

清单不包含密码、令牌、服务器地址、个人项目路径或命令历史。

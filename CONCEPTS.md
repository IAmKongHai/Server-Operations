# Concepts

Shared domain vocabulary for this project - entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## mac-mini iCare CI

### mac-mini-sonar runner
A named pool of four GitHub Actions self-hosted runner service instances on `mac-mini` used by iCare CI jobs such as SonarQube analysis and frontend tests.

Each runner instance owns its own service environment, work folder, temporary directory, and local tool-cache slot. A fix to PATH, work folder depth, or local tool availability is not complete until all four service instances have been updated and restarted.

### runner slot
One physical member of the `mac-mini-sonar runner` pool, identified by its runner number and its corresponding short work folder.

Slot-local caches are independent: a Scanner CLI cache hit on one slot does not prove another slot is warm. Cache verification for this pool needs either a hit log per slot or a confirmed `.complete` marker in each slot's tool cache.

## 代理服务器流量监控

### VPS Traffic Monitor
A planned standalone Docker service on `mac-mini` for monitoring proxy VPS traffic on `tizi` and `rao-tizi`.

It reads existing `vnstat` data over SSH, calculates billing-cycle usage, shows an internal Web UI, and sends Telegram notifications when traffic or collection-failure thresholds are reached.

### billing reset day
The day of month when a VPS provider resets a server's traffic allowance.

For proxy traffic monitoring, this reset day defines the accounting cycle; calendar-month `vnstat -m` totals are not treated as authoritative when the provider's billing cycle starts on a different day.

## Tailscale

### Exit Node
Tailscale 节点角色：被选中后，客户端（如手机）的默认上网流量经该节点转发并由该节点 SNAT 出公网，源 IP 为该节点公网地址。

与「仅加入 Tailnet 互访 `100.x`」不同；与代理面板（3x-ui / S-UI）的入站也不同。生产机做 Exit 时应 `--accept-dns=false`、`--accept-routes=false`，且服务器自身不选用其他 Exit。

*Avoid:* 把 Exit Node 与 subnet router（宣告内网网段）混为一谈。

## 代理节点（tizi 族）

### 扩容代理节点
只承载代理数据面与管理面板、不接 litellm/Nginx 业务反代的 VPS。公网通常只暴露 SSH 与代理端口（多为 443）；面板只经 Tailscale 访问。

*Avoid:* 把备用 litellm 入口机与纯代理节点混为一谈（例如 `rao-tizi` 兼业务入口时角色不同）。

### 入站（代理）
代理服务端上的一条「门」：监听地址/端口、协议与传输（如 VLESS+REALITY）、伪装目标等。一门可挂多个客户端。S-UI 称入站；3x-ui 侧栏「入站」同义。

### 客户端（代理用户）
使用某条入站的身份与额度：UUID/密钥、Flow、流量与过期。必须关联至少一条入站才有可用连接串。S-UI「用户」与 3x-ui「客户端」对应。

### 分享地址（share address）
写入客户端分享链接 `@` 之后、端口之前的主机名或 IP。应使用对外域名；若落成公网 IP 或 Tailscale IP，客户端仍可能连通但运维成本高且易误发。

### REALITY Flow
VLESS + REALITY 场景下客户端流控取值。需要 vision 时必须显式配置（常见为 `xtls-rprx-vision`）；面板默认「无」会导致有链接却无法正常代理。

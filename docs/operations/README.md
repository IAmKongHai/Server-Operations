# docs/operations/

按服务器维护的运维操作时间线。

这里记录“做过什么变更、什么时候做、为什么做、怎么回滚”。它和 `docs/solutions/` 的分工不同：

- `docs/operations/`：持续追加日常操作记录，例如停容器、改 restart policy、迁移服务、调整磁盘、临时扩容。
- `docs/solutions/`：沉淀可复用的故障复盘、解决方案、最佳实践。

## 路径约定

```text
docs/operations/<server>.md
```

例：

```text
docs/operations/dev-cypresso.md
docs/operations/nyh-prod.md
```

## 记录格式

每次操作追加一个二级标题，时间使用本地时区 `Asia/Shanghai`：

```markdown
## YYYY-MM-DD HH:mm CST - 简短标题

- 服务器：`<server>`
- 操作人：`Codex` / `<name>`
- 原因：...
- 影响：...
- 回滚：...
- 变更：
  - ...
- 验证：
  - ...
- 后续：
  - ...
```

## 记录原则

- 按时间倒序追加，最新操作放最上面。
- 记录“为什么”，不要只记录命令。
- 涉及停服务、重启、删除、数据库、防火墙等操作时，必须记录影响和回滚方式。
- 不写明文密码、token、私钥、宝塔 entrance 路径等敏感信息。
- 如果一次操作暴露出可复用经验，再另写 `docs/solutions/` 文档，并在操作记录里链接过去。

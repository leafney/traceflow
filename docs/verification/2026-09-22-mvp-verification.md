# Traceflow MVP 验证记录

日期：2026-09-22

## 自动验证

- `swift test`：18 项测试全部通过。
- `scripts/build-app.sh`：发布构建成功，生成 `dist/Traceflow.app`。
- `codesign --verify --deep --strict`：本机临时签名验证通过。
- `plutil -lint`：应用 Info.plist 验证通过。
- `scripts/e2e-local.sh`：App、成品转发器、Unix Socket、状态机、会话 JSON 闭环通过。
- `scripts/e2e-codex-cli.sh`：真实 Codex CLI、官方 Hooks、成品转发器、App 与会话存储闭环通过。
- 阶段 0 PoC 验证真实 `SessionStart`、`UserPromptSubmit`、`Stop`、`SessionEnd` 字段。

## 实测修正

`Stop` 配置为同步 Hook。原因：官方说明会话结束时取消未完成的后台 Hook；真实短生命周期 `codex exec` 中，异步 `Stop` 确实可能在写入前被取消。转发器只进行快速本机发送，同步执行不会引入长阻塞。

## 桌面端边界

本机存在 `/Applications/ChatGPT.app`，并与 CLI 使用用户级 Codex 配置层。代码与配置没有 CLI 专用分支。设置页安装的是用户级 `~/.codex/hooks.json`，因此桌面 Codex 会话可使用同一套定义。

桌面端需要用户在应用界面中执行一次真实会话，才能人工确认 HUD 的动态显示与 `/hooks` 信任。该交互不能由无人值守脚本安全代替。若实际桌面会话未触发 Hook，应按 PRD 停止双端交付认定并调查客户端版本或配置层差异。

## 本机运行

```bash
scripts/build-app.sh
open dist/Traceflow.app
```

打开菜单栏设置，点击“安装/修复 Hooks”，随后在 Codex 中运行 `/hooks` 完成信任。

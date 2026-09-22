# Traceflow

Traceflow 是 macOS 14+ 本机菜单栏应用，通过 Codex Hooks 展示 CLI 与桌面客户端会话状态。

## 构建与运行

```bash
swift test
scripts/build-app.sh
open dist/Traceflow.app
```

首次运行后，从菜单栏打开“设置”，点击“安装/修复 Hooks”。然后在 Codex 中执行 `/hooks`，审核并信任 Traceflow 定义。

## 状态

- 红灯：等待权限审批
- 黄灯：任务执行中
- 绿灯：一轮任务完成
- 三灯熄灭：待机

HUD 可拖动到任意显示器；位置、会话列表与是否参与轮播会保存到本机。对话摘要只保存在内存，不写入日志或会话文件。

## 开发验证

```bash
swift test
scripts/e2e-local.sh
scripts/poc/run-cli-poc.sh
```

详细规范见 [`docs/plan/2026-09-21-traceflow-macos-mvp.md`](docs/plan/2026-09-21-traceflow-macos-mvp.md)。

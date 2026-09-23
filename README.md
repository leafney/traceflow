# Traceflow

Traceflow 是 macOS 14+ 本机菜单栏应用，通过 Codex Hooks 展示 CLI 与桌面客户端会话状态。

## 构建与运行

```bash
swift test
scripts/build-app.sh
open dist/Traceflow.app
```

## 一键安装

在项目根目录执行：

```bash
scripts/install-app.sh
```

脚本会构建并安装到 `/Applications/Traceflow.app`，必要时请求管理员密码。安装完成后只打开一次，不设置开机自动启动。Traceflow 是仅菜单栏应用，运行时不显示 Dock 图标；退出后可在 Finder 的“应用程序”中双击 Traceflow，或通过 Spotlight 搜索 `Traceflow` 重新打开。也可在终端执行 `open /Applications/Traceflow.app`。

重复运行脚本会更新 App 包；已有 Hooks、设置、会话和日志不会被删除。应用程序本体位于 `/Applications`，转发器和运行数据仍保存在用户目录。

首次运行后，从菜单栏打开“设置”，点击“安装/修复 Hooks”。然后在 Codex 中执行 `/hooks`，审核并信任 Traceflow 定义；点击“测试转发通道”和“同步 Codex 会话”确认连接并导入已有会话。

## 状态

- 红灯：等待权限审批
- 黄灯：一轮任务完成，等待下一步输入
- 绿灯：任务执行中
- 三灯熄灭：待机

HUD 可拖动到任意显示器；位置、会话列表与是否参与轮播会保存到本机。对话摘要只保存在内存，不写入日志或会话文件。

## 开发验证

```bash
swift test
scripts/e2e-local.sh
scripts/poc/run-cli-poc.sh
```

详细规范见 [`docs/plan/2026-09-21-traceflow-macos-mvp.md`](docs/plan/2026-09-21-traceflow-macos-mvp.md)。

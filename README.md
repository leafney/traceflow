# Traceflow

Traceflow 是 macOS 14+ 本机菜单栏应用，通过 Codex Hooks 展示 CLI 与桌面客户端会话状态。

## 应用图标

应用使用深蓝同心多环图标，每个环代表一个会话，红黄绿灯位呼应状态提示；菜单栏使用同一结构的单色简化图标，自动适配深浅色。它们是固定品牌图形，不表示实时会话数量或状态。

可编辑母版为 `packaging/TraceflowIcon.svg` 和 `packaging/TraceflowMenuIcon.svg`。在 macOS 使用系统 Swift、AppKit 与 iconutil 重新生成：

```bash
scripts/generate-app-icon.sh
scripts/build-app.sh
```

生成器同时输出母版与 `packaging/Traceflow.icns`，参数由 `scripts/generate-app-icon.swift` 统一维护；修改设计时需同步菜单栏绘制模块。生成后的三个资源纳入版本控制，普通构建直接复制图标包，不重新生成。设计规范见 [`docs/plan/2026-10-01-concentric-session-icon.md`](docs/plan/2026-10-01-concentric-session-icon.md)。

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

## 标准与精简显示

从菜单栏“HUD 显示模式”或设置“常规”切换标准／精简模式，两处同步，重启保留；首次默认标准模式。

精简模式只显示一个 14 点实心菱形和三盏状态灯。横向为 144×40 点，竖向为 40×144 点，支持现有四种布局方向。菱形颜色代表会话，灯色代表状态；没有会话参与显示时使用灰色菱形和三盏暗灯。钉住后继续穿透鼠标，未钉住时仍可拖动。

所有会话会自动分配并保存颜色，旧会话首次升级时补色。自动分配避开全部已保存会话的已有颜色，优先拉开差异；相近颜色仍可能难以辨认。手动选色允许重复。

设置置顶区在会话行最左侧显示同色菱形，会话区放在参与开关与标题之间。点击菱形打开系统颜色选择器，选色立即保存；关闭面板保留已经保存的变化。项目名和标题在设置中查看，精简 HUD 不显示标题提示。

“图标区域”和“标题颜色”仅标准模式生效，切回标准模式会恢复原值；精简模式仍可调整背景透明度、光晕与布局。

开发规格：[`docs/plan/2026-10-06-compact-session-markers.md`](docs/plan/2026-10-06-compact-session-markers.md)。

## 开发验证

```bash
swift test
swift test --filter AutoEnableSessionIntegrationTests
scripts/e2e-local.sh
scripts/poc/run-cli-poc.sh
```

会话自动启用的集成测试使用独立临时目录、独立偏好设置和模拟会话服务，通过真实发现入口与本地套接字验证；不会修改个人会话或 Hooks 配置。测试需要 macOS 桌面环境及系统 Python，结束后恢复环境变量并清理临时数据。

“自动启用新会话”只控制后续自动发现或 Hook 新增项，手动同步历史项仍默认关闭。启用的待机会话不进入 HUD 轮播，收到活动事件后按现有调度展示。

详细规范见 [`docs/plan/2026-09-21-traceflow-macos-mvp.md`](docs/plan/2026-09-21-traceflow-macos-mvp.md)。

## 会话标题编辑

点击置顶区或会话区的标题，编辑本地显示名称。单行最多 100 个字符，支持保存、取消及恢复默认；HUD 保留项目名。同步和 Hook 不覆盖自定义标题，改名不会启用会话或重置轮播。保存失败时保留原标题和草稿。

相关业务验证：`swift test --filter SessionTitleEditingTests`。

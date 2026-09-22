# Traceflow 应用安装与重新打开产品需求文档

Related discussion: [`docs/discuss/2026-09-22-app-installer.md`](../discuss/2026-09-22-app-installer.md)

状态：待批准
目标版本：MVP 0.1 修复版

## Problem Statement

Traceflow 当前只能从仓库的构建产物目录运行，并未安装到 macOS 的“应用程序”目录。由于它是仅菜单栏应用，运行时本来就没有 Dock 图标；用户退出后又无法在“应用程序”中找到它，因此缺少可靠的重新打开入口。

## Solution

提供一个可直接执行的一键安装脚本。脚本构建当前源码，将完整 App 安装到 `/Applications/Traceflow.app`，注册到 macOS Launch Services，并自动启动。Traceflow 继续保持仅菜单栏、无 Dock 图标，但可从 Finder“应用程序”、Spotlight 和启动台重新打开。

## User Stories

1. 作为用户，我希望执行一个脚本即可构建并安装 Traceflow，从而不需要手工复制 App 包。
2. 作为用户，我希望 Traceflow 安装在系统“应用程序”目录中，从而退出后能再次找到它。
3. 作为用户，我希望通过 Finder“应用程序”重新打开 Traceflow，从而不依赖项目仓库。
4. 作为用户，我希望通过 Spotlight 搜索并打开 Traceflow，从而快速恢复菜单栏应用。
5. 作为用户，我希望 Traceflow 运行时仍不显示 Dock 图标，从而保持轻量菜单栏工具的体验。
6. 作为用户，我希望重复运行安装脚本能够升级现有安装，从而不必先手动卸载旧版本。
7. 作为用户，我希望安装更新不会删除 Hooks、设置、会话和日志，从而保留已有使用状态。
8. 作为用户，我希望安装完成后 Traceflow 自动启动，从而立即确认安装成功。
9. 作为用户，我希望安装失败时看到明确错误，从而知道是构建失败还是没有系统应用目录写权限。

## Implementation Decisions

- 保持 `LSUIElement=true` 和 accessory 激活策略，不增加 Dock 图标。
- 新增独立的一键安装脚本，复用现有发布构建脚本生成 App 包。
- 默认安装目标固定为 `/Applications/Traceflow.app`，不把运行数据放入 App 包。
- 安装前若 Traceflow 正在运行，先请求现有实例正常退出，避免替换正在运行的可执行文件。
- 先将新 App 复制到目标目录旁的临时路径，验证包结构后再替换正式安装，减少半安装状态。
- 若当前用户无权写入 `/Applications`，脚本明确请求管理员权限；不静默改装到其他目录。
- 更新安装只替换 App 包，不删除 `~/.codex/hooks.json`、Application Support、UserDefaults 或日志目录。
- 安装完成后刷新 Launch Services 注册，并通过系统 `open` 命令启动已安装的 App。
- 构建产物保持开发者本机临时签名；正式签名、公证和 DMG 仍不在 MVP 范围内。
- 在 README 中补充安装、重新打开和“无 Dock 图标是预期行为”的说明。

## Testing Decisions

- 测试外部行为，不依赖脚本内部命令排列。
- 对安装脚本执行 shell 语法检查。
- 在隔离临时目标目录验证首次安装、重复安装及 App 包关键文件存在。
- 验证正式发布构建仍能成功签名并通过 `plutil` 检查。
- 验证安装后的 Bundle 保持 `LSUIElement=true`。
- 对真实 `/Applications` 的最终安装作为手动验收，避免自动测试覆盖用户现有安装。
- 继续运行现有 Swift 单元测试和本地事件端到端测试，确认安装功能没有破坏应用逻辑。

## Out of Scope

- 在 Dock 中显示 Traceflow。
- 开机自动启动。
- Mac App Store、Developer ID 正式签名、公证、DMG 和自动更新。
- 将 Hooks、设置、会话或日志迁入 `/Applications/Traceflow.app`。
- 制作新的品牌应用图标；未提供图标资产时使用 macOS 默认应用图标。
- 自动卸载用户数据。

## Further Notes

- “仅菜单栏应用”和“能否在应用程序目录找到”是两个独立概念。前者由 `LSUIElement` 控制，后者取决于 App 是否真正安装并被系统注册。
- 安装后退出 Traceflow，可打开 Finder 的“应用程序”目录并双击 Traceflow，或使用 Spotlight 搜索 `Traceflow`。

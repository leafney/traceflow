# Traceflow 应用安装与重新打开讨论纪要

## 原始需求

用户希望获得一个安装脚本，用来直接安装当前 Traceflow 程序。同时用户发现程序退出后无法在“应用程序”中找到图标，也无法方便地再次打开。

## 问答记录

### 问题 1

是否保持“仅菜单栏、无 Dock 图标”，由安装脚本将应用安装到 `/Applications/Traceflow.app`，以后通过 Finder 或 Spotlight 重新打开；还是改为运行时显示 Dock 图标？

推荐答案：保持仅菜单栏模式。Traceflow 是常驻状态 HUD，运行时无需占用 Dock；安装后仍应像普通应用一样出现在“应用程序”、Spotlight 和启动台中。

用户回答：保持仅菜单栏、无 Dock 图标。当前真正的问题是程序退出后无法在“应用程序”中找到并重新打开。

### 问题 2

安装完成后是否立即打开一次 Traceflow？这与设置开机自动启动不同。

推荐答案：安装完成后立即打开一次，方便确认安装成功；不设置任何开机自动启动项。

用户回答：确认。并特别补充，一键安装脚本不需要设置开机自动启动。

## 代码与现状核验

- `Info.plist` 已通过 `LSUIElement=true` 将 Traceflow 设置为仅菜单栏应用。
- App 启动时使用 accessory 激活策略，不显示 Dock 图标，这是预期行为。
- 当前构建产物只位于仓库的 `dist/Traceflow.app`。
- 当前系统中不存在 `/Applications/Traceflow.app`，因此退出后无法从“应用程序”重新打开。
- `LSUIElement` 只影响运行时 Dock 和应用切换器展示，不会阻止已安装的 App 出现在 Finder“应用程序”目录或 Spotlight 中。

## 最终共同理解

1. Traceflow 继续保持仅菜单栏运行，不增加 Dock 图标。
2. 新增一键安装脚本，将当前版本构建并安装到 `/Applications/Traceflow.app`。
3. 安装完成后向 macOS Launch Services 注册应用，并仅在本次安装结束时打开一次 Traceflow；不设置开机自动启动。
4. 退出后用户可以从 Finder“应用程序”、Spotlight 或启动台重新打开 Traceflow。
5. 重复执行安装脚本应安全更新现有安装，不影响用户的 Hooks、设置、会话和日志。
6. 应用运行数据继续保存在 Application Support 等用户目录，不写入 App 包。

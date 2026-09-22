# 权限确认后状态切换讨论纪要

## 原始需求

当 Codex 出现权限选择时，Traceflow HUD 正确显示红灯快闪。用户完成选择并确认后，Codex 已继续执行，但 HUD 仍保持红灯，直至工具执行完成才转为其他状态。用户要求检查是否缺少状态监控或通知，并优化该体验。

历史文档仅作参考；本纪要与后续 PRD 的确认结论优先。

## 已核实的事实

1. 既有状态机已经将 `PermissionRequest` 映射为 `attention`（红灯）、`PostToolUse` 映射为 `running`（黄灯）、`Stop` 映射为 `completed`（绿灯）。
2. 已安装的用户级 Hooks 配置包含 `PostToolUse`，日志中也已经出现过 `PermissionRequest → PostToolUse → Stop` 的正确链路。因此不是状态机遗漏 `PostToolUse` 或安装器遗漏该 Hook。
3. `PostToolUse` 的官方语义是工具产生输出之后，不能表示“用户刚刚完成权限选择”。故工具运行时间较长时，红灯会错误延续。
4. `/statusline` 与 `/title` 中的 `run-state`（`Ready`、`Working`、`Thinking`）是 Codex CLI 自身界面的展示字段，不包含在现有 Hook stdin JSON 或 Traceflow 使用的 `thread/list` 数据中，不能作为 Traceflow 的直接数据源。
5. 官方 Hooks 支持 `PreToolUse`。它表示工具执行前，是本次唯一可在 `PostToolUse` 之前进入 Traceflow 的候选信号。

## 逐项问答

### 1. 本次是否在 HUD 中新增状态文字

**问题：** 是否在项目名／对话摘要旁显示“工作中”“等待确认”等文字？

**建议：** 本次不增加。HUD 标题区应继续优先用于项目名和对话摘要；红、黄、绿灯已承担状态展示。先仅修复状态灯的时机，避免压缩标题空间或引入横纵布局改动。

**用户回答：** 不添加状态文字显示。

### 2. 新增 Hook 后的信任操作

**问题：** 新增 `PreToolUse` 后，Codex 会将其识别为新 Hook。是否接受用户手动再次执行 `/hooks` 并信任？

**建议：** 接受。这是 Codex 正常的 Hook 安全机制，不应由 Traceflow 自动绕过或模拟授权。

**用户回答：** 确认。程序实现后，用户会手动重新安装程序、点击“安装／修复 Hooks”、执行 `/hooks`，并自行完成授权；不需要自动安装、自动授权或旧配置兼容处理。

### 3. `PreToolUse` 的状态机规则与异常边界

**问题：** 是否将 `PreToolUse` 正式加入状态机，并在它到达时把会话改为黄灯？若某个 Codex 场景确认后仍不发送此事件，是否使用超时猜测或 UI 读取兜底？

**建议：** 正式加入 `PreToolUse → running`。若其发生在权限请求之前，后到达的 `PermissionRequest` 仍会覆盖为红灯；若其发生在用户确认之后，会立即把红灯切换为黄灯。若实际环境没有该事件，不使用猜测性超时、键盘监听、终端标题解析或桌面 UI 自动化兜底。

**用户回答：** 确认。

## 最终共同理解

本次仅扩展 Traceflow 的事件链路：安装器在用户级 Hooks 配置中安装 `PreToolUse`，转发器按既有协议转发，状态机将其视为 `running`。HUD 不新增文字、尺寸或布局；黄色呼吸灯即表示工具正在执行。用户将手动完成重装、Hooks 安装和 Codex 信任。

`PreToolUse` 不是权限确认结果本身，也不能改变权限决策；它只作为工具开始前的运行信号。必须保留 `PermissionRequest → attention`、`PostToolUse → running`、`Stop → completed` 等既有映射与乱序保护。不能以延时推断、监听 Enter、读取 `/statusline`、读取终端标题、读取 Codex 桌面 UI 或申请辅助功能权限作为本次替代实现。

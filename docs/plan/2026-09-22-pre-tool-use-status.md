# Traceflow：权限确认后的即时运行状态

Related discussion: [docs/discuss/2026-09-22-pre-tool-use-status.md](../discuss/2026-09-22-pre-tool-use-status.md)

## 实现者必读

本 PRD 的唯一目标是缩短“用户确认 Codex 权限后，HUD 仍红灯快闪”的错误展示时间。实现者必须完整阅读本文，不能只修改 UI 动画，也不能用计时器猜测状态。

本项目的状态来源仍然是 Codex Hooks。`/statusline` 和 `/title` 的 `run-state` 文本不是可读取的数据接口，严禁将它们作为数据源。HUD 不新增状态文字；不修改横向／纵向布局、尺寸、标题排版、灯尺寸、灯动画参数、轮播策略或完成超时规则。

## Problem Statement

用户在 Codex 的权限选择界面中确认某项操作后，Codex 已开始继续工作，但 Traceflow 直到工具结束才收到 `PostToolUse`。因此 HUD 持续显示红灯快闪，错误表达“等待用户操作”，造成明显滞后和误导。

## Solution

将官方 `PreToolUse` Hook 纳入 Traceflow 的既有用户级 Hooks 安装配置和状态机。该事件到达时，当前会话立即进入 `running`，HUD 自动显示现有黄灯呼吸效果。保留现有 `PermissionRequest` 红灯和 `PostToolUse` 黄灯映射。

状态链路如下：

```text
UserPromptSubmit   -> running   -> 黄灯
PermissionRequest  -> attention -> 红灯（等待用户确认）
PreToolUse         -> running   -> 黄灯（工具即将执行）
PostToolUse        -> running   -> 黄灯（工具已返回，Codex 继续处理）
Stop               -> completed -> 绿灯
Interrupt/SessionEnd -> idle    -> 三灯暗色
```

注意：`PreToolUse` 不是权限批准结果，Traceflow 不解释其权限含义、不拦截工具、不修改工具输入，也不向 Codex 返回任何 Hook 决策。它只是在收到事件时更新本地 HUD 状态。

## User Stories

1. 作为正在使用 Codex 的用户，我希望出现权限请求时 HUD 立即显示红灯，从而知道需要我处理。
2. 作为已确认权限请求的用户，我希望工具开始执行时 HUD 尽快由红灯变为黄灯，从而不被错误提示为仍在等待确认。
3. 作为等待长时间工具执行的用户，我希望 HUD 在工具执行期间保持黄灯，而不是红灯，从而准确知道 Codex 正在工作。
4. 作为使用普通无需审批工具的用户，我希望其 `PreToolUse` 仍使会话处于黄灯工作状态，从而与现有 `UserPromptSubmit` 状态一致。
5. 作为有多个会话的用户，我希望原有红灯抢占和黄绿轮播规则继续生效，从而不会因本次修复改变会话优先级。
6. 作为已有自定义 Codex Hooks 的用户，我希望“安装／修复 Hooks”只维护 Traceflow 自己的处理器，从而不删除其他 Hook 配置。
7. 作为重装新版本的用户，我愿意手动运行“安装／修复 Hooks”并在 Codex `/hooks` 中重新信任，从而让新增 Hook 生效。
8. 作为隐私敏感用户，我不希望 Traceflow 监听键盘、抓取终端内容、读取 Codex UI 或申请辅助功能权限。
9. 作为查看 HUD 的用户，我不希望本次新增“工作中”等文字或挤压项目名／对话摘要。
10. 作为遇到不支持 `PreToolUse` 的 Codex 版本的用户，我希望 HUD 保持既有、可解释的 Hooks 行为，而不是被超时猜测为黄灯。

## Implementation Decisions

### 1. 新增唯一事件枚举值

在共享 Hook 事件枚举中增加原始值严格为 `"PreToolUse"` 的 `preToolUse` 成员。

- 不改 JSON schema 版本；现有转发器对 `hook_event_name` 的解码会自然支持该值。
- 不新增 HookPayload 字段，不读取工具命令、工具输入、用户按键、终端文本或 UI 内容。
- 现有未知事件仍必须解码失败并被安全忽略，不能因为新增一个事件放宽全部事件校验。

### 2. 状态机必须将 `PreToolUse` 映射为 `running`

状态机处理 `PreToolUse` 时，必须与现有 `UserPromptSubmit` 和 `PostToolUse` 使用相同状态更新：

1. 设置 `state = running`。
2. 清除 `completedAt`，以防新工具调用错误保留上一轮绿色完成时间。
3. 保留现有事件去重、schema 校验、按 `captured_uptime_ns` 拒绝旧事件、项目元数据更新和日志流程。
4. 不为 `PreToolUse` 添加单独的临时状态、倒计时、轮询任务或持久化字段。

必须支持以下顺序，不能假定官方客户端的精确 Hook 时序：

| 实际到达顺序 | 必须得到的最终状态 | 原因 |
| --- | --- | --- |
| `PermissionRequest`，随后 `PreToolUse` | `running` | 工具开始前的信号解除红灯，HUD 转黄灯。 |
| `PreToolUse`，随后 `PermissionRequest` | `attention` | 后到的权限请求表示 Codex 正在等待用户，必须覆盖为红灯。 |
| `UserPromptSubmit`，随后 `PreToolUse` | `running` | 已经工作中，不应产生错误完成或待机状态。 |
| `PreToolUse`，随后 `PostToolUse` | `running` | 工具返回后 Codex 本轮仍在处理，保持黄灯。 |
| `PreToolUse`，随后 `Stop` | `completed` | 本轮完成，切绿灯。 |
| 较早 `PreToolUse` 在 Socket 中晚到 | 保持较新的状态 | 必须由现有时间戳乱序保护拒绝旧事件。 |

### 3. 安装器必须安装 `PreToolUse`

Traceflow 的必需 Hook 事件集合增加 `PreToolUse`。点击设置页的“安装／修复 Hooks”后，用户级 `~/.codex/hooks.json` 中必须出现一条属于 Traceflow 的 `PreToolUse` 处理器。

该处理器的要求与 `UserPromptSubmit`、`PermissionRequest`、`PostToolUse` 相同：

```json
{
  "hooks": [
    {
      "type": "command",
      "command": "'<Traceflow 已安装转发器绝对路径>'",
      "timeout": 3,
      "async": true
    }
  ]
}
```

具体限制：

- `PreToolUse` 不设置 `matcher`，以覆盖所有支持的本地工具；不得只匹配 `Bash`。
- `timeout` 必须为数字 `3`，`async` 必须为布尔值 `true`。
- 处理器命令必须复用已有、经 shell 转义的 Traceflow 已安装转发器绝对路径；不得指向开发目录、App 包内临时文件或新建脚本。
- 重复点击安装／修复后，一个事件下只能保留一条 Traceflow 处理器；其他应用的 Hook 组和处理器必须原样保留。
- 配置检查必须将缺失、命令不一致、`timeout` 非 3 或 `async` 不为 true 的 `PreToolUse` 判定为“配置不完整”。
- 移除 Hooks 时也必须移除 Traceflow 的 `PreToolUse` 处理器，行为与其他 Traceflow 事件一致。
- 不实现自动点击安装、自动打开 Codex、自动运行 `/hooks`、自动信任，或对用户旧配置做迁移／兼容分支。用户将手工重新安装应用、执行安装／修复并完成信任。

### 4. HUD 与轮播必须复用现有 `running` 行为

不得为了本次需求增加 HUD 的新视图状态。状态机变为 `running` 后，已有 UI 和调度器必须自然执行以下行为：

- 当前会话的黄灯成为唯一激活灯，使用既有黄灯呼吸／光晕效果。
- 红灯不再持续闪烁。
- 活跃且已勾选参与 HUD 的会话仍按既有轮播与优先级调度；如果该会话当前显示，灯立即更新。
- 不添加 `Ready`、`Working`、`Thinking`、`等待确认` 或任何其他可见状态文字。
- 不解析 `/statusline`、`/title`、终端窗口标题、终端屏幕内容或 Codex 桌面客户端 UI。

### 5. 日志与故障定位

既有被接受事件日志必须自然记录新增事件，例如：

```text
event=PreToolUse state=attention->running project="示例项目" session_id="会话标识" title="项目名 · 对话摘要"
```

不得记录工具命令、工具输入、用户选择内容、提示词全文、终端文本或桌面 UI 内容。若用户反馈确认后仍是红灯，首先检查同一 `session_id` 附近是否存在该 `PreToolUse` 日志；不要用定时器悄悄覆盖红灯。

## Testing Decisions

只新增与本次事件和配置变更相关的核心业务测试；不为 HUD 动画或 SwiftUI 布局写截图测试。

### 自动测试

1. **事件编解码测试**：`hook_event_name: "PreToolUse"` 必须成功解码为 `preToolUse`，并可以重新编码为完全相同的字符串。
2. **状态机测试**：从 `attention` 应用 `PreToolUse` 后，断言接受事件、旧状态为 `attention`、新状态为 `running`、`stateChanged == true`、`completedAt == nil`。
3. **顺序测试**：应用 `PreToolUse` 后再应用较新的 `PermissionRequest`，最终必须为 `attention`；应用 `PermissionRequest` 后再应用较新的 `PreToolUse`，最终必须为 `running`。
4. **乱序测试**：会话已处理较新事件时，携带更小 `captured_uptime_ns` 的 `PreToolUse` 必须被拒绝，状态不得被覆盖。
5. **安装器测试**：全新配置安装后，全部 Traceflow 事件（含 `PreToolUse`）各有一条合格处理器；其中 `PreToolUse` 处理器必须无 `matcher`、`timeout == 3`、`async == true`。
6. **安装器幂等测试**：已有 Traceflow `PreToolUse` 处理器时再次安装，最终仍仅有一条；同一配置文件中的非 Traceflow 处理器不得丢失。
7. **安装器检查测试**：删除或篡改 `PreToolUse` 的任一必需属性后，`inspect()` 必须报告配置不完整；移除后该事件的 Traceflow 处理器必须不存在。
8. **日志格式测试**：应用 `PreToolUse` 后的日志字符串必须以 `event=PreToolUse state=attention->running` 开始，并保留项目、会话和标题字段的既有转义规则。

### 人工验收

实现完成后，由用户手动执行：

1. 重装 Traceflow。
2. 打开设置页，点击“安装／修复 Hooks”。
3. 在 Codex 执行 `/hooks`，信任新增的 Traceflow Hook。
4. 让 Codex 执行一个会弹出权限选择且实际工具执行时间足够观察的操作。
5. 观察：弹窗出现时 HUD 是红灯快闪；选择并确认后，在工具执行完成前 HUD 已切成黄灯呼吸；本轮结束后切为绿灯。
6. 查看 Traceflow 日志：同一会话必须依次可看到 `PermissionRequest`、`PreToolUse`、`PostToolUse`（如工具支持）和 `Stop`；每行均有 `project`、`session_id`、`title`。
7. 如第 5 步仍持续红灯，保留日志，不添加任何超时兜底；用日志确认是否缺少 `PreToolUse`，再单独讨论。

## Out of Scope

- HUD 中新增任何状态文字、标签、状态栏、标题后缀或布局调整。
- 读取、解析或镜像 `/statusline`、`/title`、`run-state`、终端标题或终端输出。
- 读取 Codex 桌面客户端 UI、屏幕内容或键盘输入；申请 macOS 辅助功能权限。
- 根据时间推测“用户已经确认”，或在红灯上设置自动降级到黄灯的计时器。
- 自动安装 Traceflow、自动点击安装／修复 Hooks、自动执行 `/hooks`、自动信任 Hook。
- 修改 Hook 权限决策、自动批准或拒绝用户操作。
- 新增数据库、网络服务、App Server 常驻订阅、会话持久化字段或协议版本。
- 调整 HUD 灯径、间距、光晕、呼吸周期、纵向标题、位置、透明毛玻璃或轮播规则。

## Further Notes

1. `PreToolUse` 只能改善支持该 Hook 的 Codex 本地工具路径。若实际客户端在确认后不发该事件，Traceflow 必须保持诚实的既有 Hook 状态，不能伪造“工作中”。
2. 这是一项状态源扩展，不是 UI 重设计。最小改动应集中在共享事件枚举、状态机、Hooks 安装／检查和相关测试。
3. 既有 `PostToolUse → running` 不能删除：它仍用于工具返回后的工作态维持，也兼容未产生或未及时观察到 `PreToolUse` 的路径。

# Codex 选项题提交后的红灯状态诊断

Related discussion: [docs/discuss/2026-09-23-codex-choice-state-diagnostics.md](../discuss/2026-09-23-codex-choice-state-diagnostics.md)

> 状态：待用户批准。本文件是本轮诊断功能的完整实现规范；旧文档仅供背景参考。不得把本 PRD 当作“选项题红灯滞留已修复”的验收依据。

## 实现者先读

1. **只做诊断，不改行为。** 红／黄／绿映射、状态机转移、轮播 6／4／2 秒、红灯快闪、完成态 10 分钟超时均保持原样。不要靠定时器、回复文本猜测、读取终端或 Codex 会话 JSONL 来修灯。
2. 先读现有 `Sources/TraceflowNotify/main.swift`、`Sources/TraceflowCore/Models.swift`、`Sources/TraceflowCore/UnixSocket.swift`、`Sources/TraceflowCore/RotatingLogger.swift`、`Sources/TraceflowApp/AppModel.swift`、`Sources/TraceflowCore/SessionStateMachine.swift` 及对应测试，再编码。这里列出的路径是当前代码定位，不要求移动文件。
3. 官方 Hooks 文档把 `PermissionRequest` 定义为工具审批，不保证 Codex 提出的普通选项题也发此事件；`PreToolUse` 亦不保证覆盖所有工具路径。不要在测试或文案中把这些未经实测的时序写成事实。
4. 当前项目只在 Codex CLI 终端窗口测试此问题。用户手工安装新版、安装／修复 Hooks、执行 `/hooks` 授权和人工复现；程序不得自动做这些操作。

## Problem Statement

在 Codex CLI 的选项题场景中，用户选择并回车后，Codex 可能已经继续处理，但 Traceflow HUD 仍保持红灯快闪。现有日志主要记录被接受的状态变化；转发器静默忽略 Socket 发送错误，应用对拒绝事件仅记录原因。这些信息不足以区分 Codex 没有发 Hook、转发器未能送达、应用解码失败、状态机拒绝事件，或事件已接受但 HUD 调度没有切换。`PreToolUse` 是否出现也不能靠目测判断。

## Solution

增加常开的、隐私受限的端到端事件诊断日志。每次 Hook 调用由转发器生成事件标识，记录收到的事件及发送结果；应用接收端使用同一标识记录接收、解码和状态机接受／拒绝的结果。保留既有状态变化和轮播日志，使人工复现时能按时间、事件标识和会话标识还原事实。本阶段不修改灯色判断，真实复现后再据证据制定修复。

## User Stories

1. 作为用户，我希望选项题问题复现后能从日志看到同一会话发生了什么，从而不依赖目测猜测。
2. 作为用户，我希望知道 Hook 是否到达转发器，从而识别 Codex 未触发 Hook 的情况。
3. 作为用户，我希望知道转发器是否成功发送事件，从而识别本地通信故障。
4. 作为用户，我希望知道应用是否收到并解码事件，从而区分传输和解析问题。
5. 作为用户，我希望知道状态机为何接受或拒绝事件，从而定位乱序、重复、版本或忽略规则。
6. 作为用户，我希望能够关联同一 Hook 调用在转发器和应用两侧的记录，从而还原完整链路。
7. 作为用户，我希望诊断默认常开，从而随机发生的问题不会因为忘记打开诊断而丢失证据。
8. 作为用户，我希望诊断不记录选项内容、提示词、工具参数和对话正文，从而避免额外泄露敏感信息。
9. 作为用户，我希望日志继续遵守已有容量限制，从而长期运行不无限占用磁盘。
10. 作为用户，我希望本次诊断改动不擅自改变红黄绿灯行为，从而不会产生新的误报。
11. 作为开发者，我希望将会话历史仅作为事后对照，从而避免把非实时、跨进程不可靠的数据误当成实时状态源。
12. 作为开发者，我希望在一次未复现的问题测试后仍保留诊断能力，从而在下一次复现时能取得证据。

## Implementation Decisions

### 1. 诊断范围与关联字段

- 使用现有 `HookEnvelope.eventID` 作为**一次转发器进程调用**的关联键。转发器启动并读完标准输入后立即生成一次 UUID；有效输入用同一个 UUID 构建封包，转发器和应用诊断行都必须写出它。无效输入也写本地 UUID，但不会伪称应用收到了该事件。不要给每一条诊断行重新生成 ID。
- 成功解码的事件记录固定字段：`event_id`、`event`（原始 Hook 事件枚举名）、`session_id`、`turn_id`（缺失用 `none`）、`tool_name`（缺失用 `none`）、`tool_use_id`（缺失用 `none`）。`tool_name` 与 `tool_use_id` 仅从 Hook JSON 的同名顶层字段读取；给共享 `HookPayload` 增加两个可选字段及正确的 snake_case 编解码键，现有调用方和健康检查构造方式必须继续编译；不改变 `HookEnvelope.schemaVersion` 或状态机转移。不要解析工具参数来合成工具名或调用 ID。
- 日志已有 ISO-8601 时间戳。转发器日志另记录封包的 `captured_uptime_ns` 和 `forwarded_at`；应用成功解码后记录该封包的同两项，并为接收瞬间另记 `received_at`。状态机处理完成时记录处理瞬间的 `applied_at`。这样跨进程异步写日志时，可按事件时间分析，不把物理行顺序误当真实发生顺序。
- 对无效输入／无法解码的 Hook，记录通用错误类别和输入字节数，不输出原始输入，也不猜测会话信息；对于无法解码的应用封包，记录通用错误类别和字节数。
- 诊断仅包含固定枚举类状态、错误类别和上述安全元数据。不要写入 `cwd`、项目路径、`prompt`、选项文字、工具名以外的工具内容、命令、工具参数、终端内容或整个 JSON。
- 任何来自 Hook 的字符串字段必须按现有日志规则转义控制字符、引号和换行，防止注入多条物理日志。每个外部标识字段最多输出 **128 个 Unicode 标量**；超长时保留前 128 个并追加可见的截断标记。相同字段在两侧使用同一格式；事件关联主要依赖本地生成的未截断 `event_id`。
- 新诊断行禁止增加标题或提示词。现有 `stateTransition` 日志仍会输出既有的项目和显示标题，本 PRD 不改动或清除该历史行为；“不记录提示词”特指**新增诊断字段不读取或输出原文**。

#### 日志行契约

以下是必须有的字段和样例语义，字段顺序可按现有日志习惯调整，但字段名、阶段值和 `none` 占位符必须保持一致，便于检索：

| 阶段 | 必填结果 | 含义 |
| --- | --- | --- |
| `stage=forwarder.input_rejected` | `reason=empty_input|oversize_input|invalid_json|invalid_payload`、`bytes`、`event_id` | 标准输入无法构建有效 `HookPayload`；JSON 语法正确但缺必填字段或事件名不受支持时用 `invalid_payload`，无 `session_id` 等猜测字段。 |
| `stage=forwarder.received` | 六个关联字段、捕获时间 | 已成功解码输入并构建封包，尚不代表发送成功。 |
| `stage=forwarder.sent` | `event_id`、`result=write_completed` | Unix Socket 的完整封包写入调用已返回；**不代表应用已接收或已处理**。 |
| `stage=forwarder.send_failed` | `event_id`、`operation`、`errno` 或固定错误类别 | 编码／连接／写入失败；不输出系统错误描述中的路径或输入内容。 |
| `stage=app.received` | 六个关联字段、捕获与接收时间 | 应用已收到并成功解码封包，尚不代表状态机接受。 |
| `stage=app.decode_failed` | `reason=invalid_envelope`、`bytes` | Socket 有数据，但无法解码 `HookEnvelope`；不得反向猜测其 `event_id`。 |
| `stage=app.socket_drop` | `reason=read_error|empty_input|oversize_input`、`bytes` | Socket 在回调前丢弃数据；不得猜测 `event_id`。 |
| `stage=app.accepted` | 六个关联字段、`old_state`、`new_state`、`state_changed=true|false`、处理时间 | 状态机已接受；即使新旧状态相同也必须记录。 |
| `stage=app.rejected` | 六个关联字段、`reason`、处理时间 | 状态机拒绝，原因严格使用 `unsupportedSchema`、`duplicate`、`outOfOrder`、`ignoredCompaction` 之一。 |
| `stage=app.internal_handled` | `event_id`、`reason=health_check` | 已识别并处理健康检查事件；不应误写成 Codex 会话状态机接受。 |
| `stage=app.internal_ignored` | `event_id`、`reason=internal_source|unmatched_health_check` | 内部来源或不匹配的健康检查被排除；不应误写成 Codex 会话状态机拒绝。 |

不增加 `stage=app.displayed`，因为本轮不修改 HUD 调度。若 `app.accepted` 后颜色仍不对，结合现有 `stateTransition` 和 `carousel=switch` 日志判断下一步。

### 2. 转发器阶段

- 保持现有 Hook 响应：**有效输入完成处理后向标准输出输出一行 `{}` 并以 0 退出**；无效或过大输入保持当前“安全忽略、以 0 退出”的行为。诊断失败不得阻断 Codex 工作流程，不得向标准输出／标准错误泄露输入内容。尤其不能把日志文案写入标准输出，因为 Codex 可能把它解释为 Hook 结果。
- 读取标准输入后按顺序执行：检查空输入／1 MiB 上限 → 解码 `HookPayload` → 构建 `HookEnvelope` → 写 `forwarder.received` → 编码封包并调用现有 `UnixSocketClient.send` → 写 `forwarder.sent` 或 `forwarder.send_failed` → 同步冲刷诊断日志 → 按既有协议返回。转发器不能继续用 `try?` 静默吞掉编码和发送失败。
- 无效输入、超出大小限制、无法编码和 Socket 连接／写入失败要能区分。先用 JSON 语法解析结果区分 `invalid_json` 与 `invalid_payload`，不能把未知事件名静默归为已接受。无效输入不生成虚假的“已发送”记录。
- `UnixSocketClient.send` 正常返回时只可称 `write_completed`；它没有等待服务器确认，不能记作 `delivered`。把现有 `UnixSocketError` 的操作名和数值 errno 格式化为安全字段；路径过长／消息过大用固定错误类别，其他意外错误用固定 `unknown`，不把 `localizedDescription` 原样写进日志。
- 转发器是短生命周期进程，返回 Codex 前必须确保该次诊断记录完成落盘或完成可验证的同步提交。若继续复用 `RotatingLogger` 的异步 `log()`，每条调用后的最终 `flush()` 是必需步骤；不能把唯一失败证据留在进程即将退出的异步队列里。
- 不新增 Hook 类型、不更改 Hooks 安装配置和信任流程。

### 3. 应用接收及状态机阶段

- 在 `UnixSocketServer` 的回调入口记录解码成功的 `app.received` 或失败的 `app.decode_failed`，在切到主线程调用状态机**之前**记录接收时间。成功解码后使用封包中的 `event_id` 关联转发器记录；成功健康检查记为 `app.internal_handled`，不匹配的健康检查和内部 Hook 来源记为 `app.internal_ignored`，不得给它们造一个真实会话的 `app.accepted`。
- 若 Socket 服务端在交给回调前因读取错误、空封包或超过 1 MiB 而丢弃数据，应增加一条不含原始数据的 `stage=app.socket_drop reason=read_error|empty_input|oversize_input`，仅记录可安全取得的字节数。这不需要解析或猜测 `event_id`。
- 在 `AppModel.apply` 调用 `SessionStateMachine.apply` 后立即写 `app.accepted` 或 `app.rejected`。接受日志必须包含事件名、会话、可选轮次／工具关联字段、旧／新运行状态及 `stateChanged`；拒绝日志必须包含 `EventApplyResult.rejection` 的枚举名。原有状态变化、会话持久化、健康状态刷新及 HUD 调度代码和顺序应保持原样，不能因为日志失败而提前返回。
- 诊断应区分“状态机接受但状态未变”和“状态机拒绝”；不能仅看颜色有没有变化来判断事件是否送达。
- 如同一事件被应用接收并接受，但 HUD 未随之变化，保留现有轮播日志作为后续分析依据；本阶段不重写调度器。

### 4. 日志存储与并发

- 沿用设置页“打开日志目录”和“清除日志”入口，诊断日志写入现有 `traceflow.log`／`.1`～`.4`，纳入同一清除操作。保持**总共最多 5 个日志文件，每个不超过 10 MiB**；不得另建一套无限增长的转发器日志。轮转必须按文件大小而非日期。
- 转发器与应用会同时写日志。现有 `RotatingLogger` 的进程内 `DispatchQueue` 不足以保证跨进程安全；在日志目录内使用固定的 `traceflow.log.lock` 锁文件，所有进程对**追加、轮转、清除**都持有同一把独占 `flock` 锁。操作顺序是：进程内队列排队 → 取得跨进程锁 → 重新读取当前文件大小 → 必要时轮转 → 打开当前日志并追加**完整单行** → 关闭句柄 → 释放锁。不得在锁外保留可被轮转替换的文件句柄。
- 清除日志也必须取得同一把锁，删除 `traceflow.log` 和 `.1`～`.4` 后释放锁；**不要删除锁文件**，否则另一个进程可能继续锁着旧 inode，失去互斥。锁文件不是日志文件，不计入 5 个日志文件；现有日志测试若断言目录内容，需要改为只统计 `traceflow.log` 及轮转文件，不要求锁文件消失。
- 日志目录权限维持私有，锁文件和新建日志文件使用 `0600`；操作不应放宽现有权限。每行使用带毫秒的 UTC ISO-8601 时间戳，并把时间戳、换行符都算入文件大小。确保单条安全格式化后的诊断行小于 10 MiB；若格式化行异常过长，截断可控字段而不是生成超限日志文件。
- `flock` 获取失败、写入失败或轮转失败时，必须释放已持有资源并安全降级，不阻断 Hook；不能静默写出截断的半行或伪造 `sent`／`accepted`。当前应用自身仍可按既有方式运行。
- 日志写入失败应安全降级，不影响 Hook 正常返回；若无法记录该次诊断，不能伪造成功记录。

### 5. 人工复现与分析

- 仅针对已测试的 Codex CLI 终端窗口。用户先手工安装新版 Traceflow，再在设置中手工安装／修复 Hooks，并在 Codex CLI 的 `/hooks` 中手工信任。人工复现时记录选项题出现、用户提交、Codex 继续处理及 HUD 颜色变化的近似时刻，并从日志按 `session_id`、`event_id`、`turn_id` 关联时间线。
- 按以下顺序判断，不跳步：① 选项出现前红灯是否已亮、由哪条事件点亮；② 选项题期间是否看到提问类 `tool_name` 的 `PreToolUse`，且是否有 `tool_use_id`；③ 用户提交后是否出现同一 `tool_use_id` 的 `PostToolUse` 或其他后续 Hook；④ 每个事件是否经过 `forwarder.received` → `forwarder.sent` → `app.received` → `app.accepted`；⑤ 若接受后 HUD 仍红，查看最后的 `stateTransition` 和 `carousel=switch`。不能仅因缺少 `PreToolUse` 就断言 Hook 配置错误；官方承认有些工具路径不走普通工具 Hook。
- 优先区分五种结果：没有转发器记录；转发器收到但发送失败；发送成功但应用未收到／解码失败；应用收到但拒绝；应用接受而 HUD 仍红。**没有转发器记录只能表述为“本次未观察到此 Hook”；不能仅凭这一点断言 Codex 没发，也要排除未信任、版本、配置或日志本身写入失败。** 每种结果对应不同后续修复，不在本 PRD 中预设其中一种为事实。
- Codex 会话历史可作为人工事后对照，不能直接推导 Hook 必然发生，也不接入实时灯色。选项题出现前红灯是否已亮保持“待复现”。
- 若人工测试没有复现，保留诊断功能并记录测试未复现，不修改颜色映射。

## Testing Decisions

- 自动测试关注可观察结果：日志是否包含必要关联字段和阶段、敏感字段是否缺席、错误与拒绝原因是否正确、并发写入后是否保留完整物理行与轮转上限。不测试私有方法或特定内部队列实现。
- **结构与格式：** `HookPayload` 在缺少 `tool_name`／`tool_use_id` 时仍能解码、旧测试仍通过；字段存在时能往返编解码。诊断格式覆盖换行、引号、控制字符和超过 128 个 Unicode 标量的标识；物理上只能得到一行，且不得包含测试输入中的提示词、选项文本或工具参数。既有包含标题的状态转换日志不属于这项隐私断言。
- **转发器：** 有效输入与运行中的测试 Unix Socket 通信，断言标准输出只含既有 `{}`、退出码为 0，日志中 `forwarder.received`／`forwarder.sent` 使用同一 `event_id`。Socket 不存在或连接失败时仍以 0 退出、仍按既有协议输出、日志包含 `send_failed` 而不是 `sent`。空输入、无效 JSON、超过 1 MiB 输入分别记录对应原因，不把输入原文写入日志。可提取纯业务转发函数供 `TraceflowCoreTests` 测试，或做可控进程级集成测试；**不得只测格式化器而漏测真实 `traceflow-notify` 的冲刷行为**。
- **应用处理：** 验证成功解码后 `event_id` 与转发器一致；状态机接受且状态变化、接受但状态未变、重复、乱序、schema 不支持、compact 忽略、内部来源、健康检查成功／不匹配、封包解码失败各产生正确阶段与原因。状态机转移结果必须与改动前一致。若现有 Core 测试无法直接调用 `AppModel`，提取纯日志格式／事件分类逻辑测试，并用手工端到端 Socket 烟测补足 AppModel 接线，不要为测试重构整个 UI。
- **并发与轮转：** 用两个独立进程同时写同一测试目录，验证每条已报告成功的记录恰有一条完整物理行，没有交叉拼接；在测试用小文件上限下触发轮转，统计最多 5 个日志文件且每个不越界；并发清除后锁文件仍存在，之后写入仍互斥。不要把线程并发测试冒充跨进程测试。参考既有 `RotatingLoggerTests`、`UnixSocketTests`、`SessionStateMachineTests`。
- **自动命令：** 每个主要改动完成后运行相关 `swift test --filter ...`；全部完成后运行 `swift test`、`swift build`、`git diff --check`。人工验收用 Codex CLI 选项题，不把“一次没有复现”当作故障已修复。

## 分阶段编码清单

以下顺序是实现顺序，不得先修改状态机来“修复”观察到的红灯：

### 阶段一：安全日志基础

1. 在现有日志组件上实现跨进程文件锁、追加／轮转／清除的同锁保护，以及短生命周期进程可调用的同步冲刷。保持 `log()`、`flush()`、`clear()` 的既有对外语义。
2. 在共享核心模块提供一个集中格式化诊断行的纯函数／小类型，统一字段引用、转义、截断、错误类别。不要在转发器与应用各复制一套字符串拼接规则。
3. 更新日志单元测试与跨进程并发测试。确认 `traceflow.log.lock` 不被“清除日志”按钮删除。
4. 验证本阶段相关测试通过；若本项目执行时要求阶段提交，提交信息必须符合 `type(scope): 简体中文描述`。

### 阶段二：转发器入口和传输结果

1. 在共享载荷结构增加可选 `tool_name`、`tool_use_id`；字段缺失不报错，状态机不使用它们判灯。
2. 让转发器对每次调用生成一个 `event_id`，按契约记录输入无效／有效、发送完成／失败；保留现有 Unix Socket 路径、数据封包版本、标准输出和退出码。
3. 转发器退出前冲刷日志。用真实短进程测试证明失败日志不会因异步队列丢失。
4. 验证本阶段相关测试通过；不自动修改用户的 Hooks 配置。

### 阶段三：应用接收和处理结果

1. Socket 回调成功解码时记录 `app.received`，失败时记录 `app.decode_failed`，捕捉实际接收时间。
2. 在现有健康检查／内部来源分支记录内部处理或忽略；在现有状态机调用后记录 `app.accepted` 或 `app.rejected`。不得因为新增诊断行改变是否保存会话、更新 UI、调度轮播的既有条件。
3. 验证同一个有效事件的 `event_id` 能在转发器与应用日志中被检索到；运行相关测试和端到端 Socket 烟测。

### 阶段四：总体验证与交付

1. 运行完整 `swift test`、`swift build` 和 `git diff --check`；检查真实日志中无提示词全文、选项文字、工具参数或跨行注入。
2. 交付时明确告诉用户：这是诊断版，不是红灯滞留行为修复版；安装新版后的 Hooks 修复、`/hooks` 信任和真实选项题复现仍由用户手工完成。
3. 用户复现后再依据本 PRD 的五类结果分析下一步；如无法复现，记录“待复现”，不要宣称问题解决。

## 验收判定表

| 场景 | 必须观察到 | 禁止出现 |
| --- | --- | --- |
| 有效 Hook，应用运行且接受 | 同一 `event_id` 的 `forwarder.received`、`forwarder.sent`、`app.received`、`app.accepted`；状态机原有灯色不变 | 提示词或工具参数进入新增诊断行 |
| 有效 Hook，应用未启动 | `forwarder.received` 和 `forwarder.send_failed`；Codex Hook 正常返回 | `forwarder.sent`、假造的 `app.received` |
| 无效或超大输入 | 准确的 `forwarder.input_rejected`；无原始输入 | `forwarder.sent`、进程崩溃 |
| 重复或乱序事件 | `app.received` 后 `app.rejected`，带明确原因；会话状态不变 | 误记 `app.accepted` 或错误变色 |
| 有效但不改变状态的事件 | `app.accepted state_changed=false` | 把它归入拒绝或用颜色未变推断丢事件 |
| 多进程并发／轮转／清除 | 单行完整、每文件不超限、日志最多 5 个、锁文件仍可继续同步 | 交叉拼接、半行、丢失已报告成功的写入 |

验收表中的“已报告成功”仅针对日志组件明确成功返回的写入；若磁盘或权限故障导致日志写入失败，应安全降级，不能凭缺失记录推断 Codex 没发 Hook。

## Out of Scope

- 修改红黄绿映射、`PreToolUse`／`PermissionRequest` 等事件的状态机含义、HUD 动画或轮播优先级。
- 将普通本轮完成后的等待回复改为红灯，或将红灯改成快闪 10 秒后常亮；现有 6／4／2 秒轮播规则保持不变。
- 增加猜测性的超时变色、监听键盘、读取终端屏幕、使用辅助功能权限、解析 `/statusline` 或 `/title`。
- 自动安装／修复 Hooks、自动授权或改变现有 Codex 用户配置。
- 将 Codex 会话历史或独立 App Server 的状态直接作为实时状态源。
- 立即修复未被日志证实的选项题时序问题；行为修复需在捕获真实复现后另行确定。

## Further Notes

- 已确认的测试范围只有 Codex CLI；不要把其他客户端的行为当成已验证事实。
- 当前状态机中 `PermissionRequest` 表示需关注，`PreToolUse`／`PostToolUse` 表示运行中，但尚无证据说明 Codex CLI 选项题一定按该链路发 Hook。诊断目的正是确定实际链路。
- 既有日志中只有状态变化和简略拒绝原因，因此先增强可观测性是本轮唯一交付目标。

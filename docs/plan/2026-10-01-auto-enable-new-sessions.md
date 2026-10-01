Related discussion: [docs/discuss/2026-10-01-auto-enable-new-sessions.md](../discuss/2026-10-01-auto-enable-new-sessions.md)

# 新发现会话自动启用

日期：2026-10-01
状态：用户已批准，全部四阶段已完成。

执行授权更新：用户要求连续完成所有阶段；每阶段运行对应验证并提交 Git，提交后立即继续。此授权覆盖下文逐文件等待确认及不自动提交的旧流程要求。功能规则不变。

执行要求：本文包含具体编码指引，供编码模型逐项执行。不得仅完成界面后宣布完成。本文中的代码片段是局部修改示例，不是完整文件；必须保留文件中未涉及的现有代码。

## 问题

新发现的会话目前全部默认关闭。希望新会话直接参与 HUD 的用户，需要不断进入设置页逐条启用。用户需要一个可保存的选项，同时保留现有手动选择方式。

## 方案

在“置顶区”标题右侧新增“自动启用新会话”开关。默认关闭，立即保存，重启后恢复。开启时，自动发现和 Hook 首次新增的会话自动参与 HUD；关闭时保持当前行为。

切换开关只改变后续新增项的初始状态，不修改当前会话集合。手动同步历史会话始终默认关闭。

## 用户故事

1. 作为用户，我希望在置顶区标题右侧直接设置自动启用，从而减少重复手动操作。
2. 作为用户，我希望开关默认关闭，从而升级应用后保持现有行为。
3. 作为用户，我希望选择跨重启保留，从而无需重复设置。
4. 作为开启开关的用户，我希望自动发现的新会话直接参与 HUD。
5. 作为开启开关的用户，我希望 Hook 首次发现的新会话直接参与 HUD。
6. 作为关闭开关的用户，我希望新会话仍被发现并显示，便于手动选择。
7. 作为手动关闭过会话的用户，我希望后续活动和重复发现不会覆盖我的选择。
8. 作为用户，我希望关闭总开关后已启用项继续参与 HUD。
9. 作为同步历史会话的用户，我希望历史新增项仍默认关闭，避免大量历史项进入轮播。
10. 作为用户，我希望两个区域的同一会话保持状态一致，并沿用现有轮播行为。

## 实现决策

### 开关界面与偏好

- 将置顶区改为自定义分区标题：左侧标题，右侧标签和原生 switch；保持现有行开关样式。
- 空列表、读取中、读取失败时均显示此开关。
- 开关可访问性名称为“自动启用新会话”；辅助说明明确“仅自动启用此后新发现的会话，手动同步历史会话除外”。
- 使用独立 UserDefaults 布尔键 `autoEnableNewSessions`；缺少键时为 false。
- AppModel 提供可观察的偏好属性，写入后立即保存。此属性不触发会话批量修改、额外同步或 HUD 可见性修改。
- 偏好与会话数据分开保存；现有会话持久化格式不变。

### 新增判断与来源

“新增”定义为处理输入时，该会话 ID 尚不存在于当前本地会话集合。不得以是否位于置顶区、状态是否待机、最近活动时间或是否已经关闭作为新增判断。

| 输入 | 总开关关闭 | 总开关开启 |
| --- | --- | --- |
| 自动发现首次新增 | 不参与 HUD | 参与 HUD |
| Hook 首次新增 | 不参与 HUD | 参与 HUD |
| 手动同步首次新增 | 不参与 HUD | 不参与 HUD |
| 已有会话的任意更新 | 保留原状态 | 保留原状态 |
| 恢复本地保存记录 | 保留原状态 | 保留原状态 |

- 自动发现和手动同步继续共享导入链路，但必须显式传入新增项的初始启用策略。不得把导入器或会话数据模型的全局默认值改为启用。
- Hook 工厂支持显式初始参与 HUD 值，默认仍为 false；仅创建新状态机时读取偏好并传入。
- 导入器新增 `includeNewSessionsInHUD: Bool = false` 参数，已有项分支保留原状态。避免为此引入新存储层或大型策略框架。
- 自动发现请求返回并实际合并时读取当前偏好；请求期间切换开关，以合并时的设置为准。Hook 以实际处理时的设置为准。
- 自动发现与 Hook 先后遇到相同 ID 时，第一个成功新增的入口决定初始状态；后一个入口仅更新，不重置用户选择。
- 手动同步创建的关闭项随后收到 Hook 或再次自动发现时，仍按已有项处理。
- 删除、清空、来源过滤及响应失效机制保持现有行为。删除后若按现有规则允许重新导入，因本地已无此 ID，按本次新增来源和当前开关处理；不额外新增永久历史 ID 表。

### HUD 与置顶区

- 在新增记录发布和调度器更新前设置初始参与状态，避免先发布关闭记录再批量补开。
- 使用现有刷新、持久化、状态变更和调度路径，让启用的新项进入 HUD 候选集合。
- “加入 HUD”表示参与现有调度；不保证每次新增都立即抢占当前展示，也不改变红黄绿优先级。
- 没有其他启用项时，按照现有调度显示新启用项；HUD 原本隐藏时保持隐藏。
- 置顶区仍按最近 10 分钟活动时间筛选；超过窗口后移出置顶区不等于关闭 HUD 参与状态。
- 自动发现仍仅在设置页可见时轮询；开关不增加后台扫描。Hook 沿用现有监听方式。
- 会话状态与启用状态分离；自动启用不得伪造运行状态。

## 实施阶段

1. **偏好接入**：增加可观察布尔偏好，读取默认关闭值并立即保存；确认后继续。
2. **新增策略接入**：调整导入器、Hook 工厂及应用合并入口，区分自动与手动来源，保留已有项状态。按主要文件逐个改动并等待用户确认。
3. **界面接入**：置顶区标题右侧增加开关、标签与辅助说明；主要文件改动后等待确认。
4. **验证**：补充必要业务边界测试，执行构建和现有测试，手动检查布局及 HUD 联动。记录结果。

实现前完整阅读本 PRD；若需改变已确认规则，先更新 PRD 并取得用户批准。

## 具体编码指引

### 0. 阅读与执行约束

仓库根目录通过 `git rev-parse --show-toplevel` 获取，以下路径均相对仓库根目录。实施前查看 `git status --short`，不要覆盖用户已有改动。

按下表执行。每完成一个主要源码文件的改动，报告改动及检查结果，然后等待用户确认再改下一个主要源码文件。测试在业务代码修改后补充，不采用先写测试的流程。主要源码文件包括下表四个不同的源码文件；AppModel 分两次改动，每次也需等待确认。

| 顺序 | 文件 | 必须完成的改动 |
| --- | --- | --- |
| 1 | `Sources/TraceflowApp/AppModel.swift` | 添加并初始化偏好属性，仅处理设置保存 |
| 2 | `Sources/TraceflowCore/CodexAppServerClient.swift` | 修改 CodexThreadImporter 的参数及新增分支 |
| 3 | `Sources/TraceflowCore/HookSessionFactory.swift` | 增加新记录的初始参与 HUD 参数 |
| 4 | `Sources/TraceflowApp/AppModel.swift` | 在自动导入与新 Hook 状态机两个入口传入策略 |
| 5 | `Sources/TraceflowApp/SettingsView.swift` | 替换置顶区标题，添加总开关 |
| 6 | `Tests/TraceflowCoreTests/CodexAppServerClientTests.swift` | 补充新增与已有记录混合导入等边界测试 |
| 7 | `Tests/TraceflowCoreTests/HookSessionFactoryTests.swift` | 补充显式启用与后续事件保留选择的测试 |

无需新增生产代码文件。不要把偏好放进 HUDPreferences；这是会话新增策略，不是 HUD 外观设置。不要修改 PersistedSession 的默认值、会话存储格式、RecentSessionSelector、SessionDiscoveryCoordinator 或 CarouselScheduler。

### 1. AppModel：偏好属性与初始化

在已有 `@Published` 设置属性附近添加：

```swift
@Published var autoEnableNewSessions: Bool {
    didSet {
        defaults.set(autoEnableNewSessions, forKey: "autoEnableNewSessions")
    }
}
```

在 `init(defaults:)` 中，`self.defaults = defaults` 之后、`restoreSessions()` 之前初始化：

```swift
autoEnableNewSessions = defaults.bool(forKey: "autoEnableNewSessions")
```

UserDefaults 缺少该键时 `bool(forKey:)` 返回 false，无需迁移、无需把默认 false 写进磁盘。必须使用注入的 `defaults`，不得在上述读写中改用 `UserDefaults.standard`，否则会破坏调用方的隔离设置。

`didSet` 只保存布尔值。禁止遍历 machines、调用 setIncluded、setProjectIncluded、refreshSessions、syncCodexSessions，禁止强制显示 HUD。切换总开关时当前 `sessions`、`recentSessions`、`displayedSession` 的业务内容应保持原状。

### 2. CodexThreadImporter：只改新增分支

在 `Sources/TraceflowCore/CodexAppServerClient.swift` 找到 `public enum CodexThreadImporter` 的 `merge`。签名改为：

```swift
public static func merge(
    _ threads: [CodexThreadSummary],
    into existingSessions: [PersistedSession],
    nextRotationIndex: Int,
    includeNewSessionsInHUD: Bool = false
) -> CodexThreadImportResult
```

函数体保留现有结构：

- `if var existing = sessionsByID[thread.id]` 为已有记录分支，不添加对 `existing.isIncludedInHUD` 的赋值。
- 仅在 `else` 构造新 PersistedSession 时，把 `isIncludedInHUD: false` 替换为 `isIncludedInHUD: includeNewSessionsInHUD`。
- 项目元数据、活动时间、设置排序时间、rotationIndex、addedCount、updatedCount、来源过滤不变。
- 默认参数 false 保证未修改的现有调用继续编译，并保持默认关闭。
- 同一批次重复出现同 ID 时，第一条创建后后续条目走已有分支，不新增第二条记录，也不重置选择。

此函数不访问 UserDefaults，也不判断自动或手动请求；调用方负责计算传入值。

### 3. HookSessionFactory：显式初始状态

`makePersistedSession` 的签名改为：

```swift
public static func makePersistedSession(
    sessionID: String,
    cwd: String?,
    now: Date,
    rotationIndex: Int,
    isIncludedInHUD: Bool = false
) -> PersistedSession
```

只把返回的 PersistedSession 中 `isIncludedInHUD: false` 改为 `isIncludedInHUD: isIncludedInHUD`。其他字段保持原样，特别是 lastActivityAt 和 settingsListSortAt 使用发现时间的逻辑。工厂不读取偏好、不创建调度器、不修改运行状态。

### 4. AppModel：两个入口接线

#### 4.1 自动发现与手动同步

在 `mergeCodexThreads(_:isManual:)` 中、调用导入器前计算：

```swift
let includeNewSessionsInHUD = !isManual && autoEnableNewSessions
let result = CodexThreadImporter.merge(
    threads,
    into: current,
    nextRotationIndex: nextRotationIndex,
    includeNewSessionsInHUD: includeNewSessionsInHUD
)
```

含义：手动请求不论总开关如何，传入 false；自动请求采用合并时的偏好。不得在 startDiscovery 中缓存开关值，也不得向后台读取线程传递偏好快照。

保留 `completeDiscovery` 中的现有调用：

```swift
mergeCodexThreads(allowed, isManual: request == .manual)
```

保留合并函数中已有状态机分支的 `merged.isIncludedInHUD = live.isIncludedInHUD`，保留运行状态及 lastActivityAt 合并方式。新增状态机直接使用导入器输出，不再二次重置参与状态。

末尾继续按现有顺序执行 machines 赋值、rotationIndex 更新、refreshSessions、persistSessions 及手动同步结果文案。不要在结果返回后对全部 records 执行启用，不要逐条调用 setIncluded。

#### 4.2 Hook 新会话

在 `makeMachine(for:)` 调用工厂时追加参数：

```swift
let persisted = HookSessionFactory.makePersistedSession(
    sessionID: envelope.payload.sessionID,
    cwd: envelope.payload.cwd,
    now: now,
    rotationIndex: nextRotationIndex,
    isIncludedInHUD: autoEnableNewSessions
)
```

保留 `apply(_:)` 中现有选择：

```swift
var machine = machines[id] ?? makeMachine(for: envelope)
```

`??` 的右侧仅在没有已有记录时执行。因此已有关闭项收到 Hook 后不会读取偏好来重新启用。禁止把 makeMachine 移到这条语句之前无条件调用，也禁止在 machine.apply 后赋值 isIncludedInHUD。

保留健康检查、内部来源过滤、删除抑制、事件拒绝处理。保留 publishSessions、调度器成员更新、reportStateChange、persistSessions 及显示决策的现有调用顺序和参数。不能为了自动启用修改 processNewlyIncluded 或抢占规则。

### 5. SettingsView：标题右侧总开关

只替换当前 `Section("置顶区") { ... }` 的声明形式，内部内容完整保留。采用以下结构：

```swift
Section {
    // 保留现有空态、加载提示、错误提示和 ForEach 内容。
} header: {
    HStack {
        Text("置顶区")
        Spacer(minLength: 8)
        Toggle("自动启用新会话", isOn: $model.autoEnableNewSessions)
            .toggleStyle(.switch)
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel("自动启用新会话")
            .help("仅自动启用此后新发现的会话，手动同步历史会话除外")
    }
}
```

- 代码中的注释不是替代原有内容的占位实现。空态、加载、错误、ForEach 必须全部留在 Section 内容中。
- 这里的总开关控制偏好；行内“参与 HUD”开关仍调用 `model.setIncluded`，两者不能绑定到同一个值。
- 保持总开关文字可见，不添加 labelsHidden；不用图标代替文字。
- 不把总开关放入某条会话行，不重复为每个项目增加总开关。
- 不给总开关添加 `!model.sessionDataHealth.allowsSaving` 禁用条件：它保存 UserDefaults，独立于会话文件。原有单项开关及发现链路的数据健康保护仍保留。
- 在当前最小窗口宽度 680 下检查标签和开关可见、无截断，位置在标题行右侧；空态也显示。若原生分区标题样式导致开关不可用或布局异常，先报告现象，再提出最小布局修正，不擅自改整个设置页。

### 6. 三个必须理解的示例

**示例一：开启不是批量启用。** A 已存在且关闭 → 开启总开关 → A 仍关闭 → 首次发现 B → B 开启 → A 再次收到 Hook → A 仍关闭。

**示例二：关闭不是批量关闭。** 总开关开启时新增 B，B 已启用 → 关闭总开关 → B 仍启用 → 后续新增 C → C 关闭。

**示例三：手动导入后不再算新增。** 总开关开启 → 手动同步新增 D → D 关闭 → 自动发现 D 或收到 D 的 Hook → D 仍关闭；用户可通过行内开关手动开启 D。

## 测试实施明细

只新增以下核心业务边界测试，不为简单偏好属性或界面结构新增单元测试。不要为了测试 private 方法改为 public，不要添加生产测试入口或修改 AppModel 初始化以接入本轮无关的存储重构。

### 导入器测试

在 `Tests/TraceflowCoreTests/CodexAppServerClientTests.swift` 的现有导入测试附近添加：

1. **开启策略下混合导入**：已有 A=false、B=true，输入 A/B 的更新和新的 C，传入 true。按 ID 查找结果，断言 A=false、B=true、C=true；A/B 原 rotationIndex 与已有 settingsListSortAt 不变，C 使用 nextRotationIndex，计数正确。不要依赖字典遍历顺序。
2. **关闭策略下混合导入**：同样 A/B/C，显式传入 false，断言 A=false、B=true、C=false。保留原有“不传参数则新增关闭”测试。
3. **先手动导入再自动发现**：第一次 merge 传 false 创建 D；第二次 merge 将第一次结果作为 existingSessions，传 true 并更新 D，断言 D 仍 false，addedCount=0、updatedCount=1。此测试验证记录保留，不代表验证了 AppModel 的来源接线；接线还需手动验收。
4. **同批次重复 ID**：空已有集合，输入两个相同 ID 的条目，传 true，结果只有一条且启用，addedCount=1，nextRotationIndex 只增长一次。
5. **开启策略仍过滤内部来源**：官方 cli 项和 subAgentReview 项一起导入并传 true，只有官方项新增并启用。

### Hook 工厂与状态机测试

在 `Tests/TraceflowCoreTests/HookSessionFactoryTests.swift` 添加：

1. 显式传 true 创建记录，断言启用、projectName、lastActivityAt、settingsListSortAt、rotationIndex 均符合输入。
2. 保留原有不传参数默认关闭测试；新增显式 false 的业务保留行为可与后续事件测试合并，避免机械重复。
3. 对 false/true 两种初始参与值分别创建状态机，再提交一个可接受的 userPromptSubmit 事件，断言事件被接受、lastUpdatedAt 更新，而 isIncludedInHUD 与发现排序时间保持不变。

测试只访问临时数据或纯内存对象。不要向用户真实会话目录写测试记录，不要清空用户数据，也不要启动真实 Codex 服务作为单元测试的依赖。

### 手动验收操作

使用独立测试数据环境或用户明确允许使用的会话；不要通过清空全部真实记录制造测试场景。

1. 打开设置页，确认标题行总开关与行内开关清楚区分，空态/加载态仍可见。
2. 用已知关闭的旧会话 A 验证：开启总开关后 A 不变，关闭再开启总开关也不变。
3. 开启总开关，创建新的正常会话 B，让 Hook 首次发现它；置顶区显示 B 且行内开关开启。检查会话区同一 B 也是开启，HUD 按现有规则参与展示。
4. 关闭总开关，确认 B 不被关闭。创建新会话 C，确认 C 默认关闭，再用行内开关手动开启 C。
5. 对已手动关闭的 A 产生新活动，确认不会自动开启。
6. 开启总开关后执行手动同步，选取本地此前不存在的历史 D，确认默认关闭；后续 D 产生 Hook 活动仍关闭。
7. 自动发现入口必须单独验证：选择符合最近 10 分钟条件、此前本地不存在且尚未由 Hook 导入的会话，打开或保持设置页等待读取。开启总开关时新增开启，关闭时新增关闭。若无法隔离 Hook 入口，应记录此项未验证，不得用 Hook 验证替代。
8. 请求途中切换开关：确认结果合并时采用最新值。若真实服务返回太快不能复现，记录代码接线检查通过、运行时未验证，不伪称已测。
9. 退出并重启应用，确认总开关保存，已有参与状态保存；HUD 隐藏时切换总开关或新增会话不强制显示 HUD。
10. 查看加载失败时开关仍可用；若没有安全方式触发失败，记录未验证，不修改真实服务配置制造故障。

无需为验证时间窗口或调度行为新增定时等待；沿用现有测试覆盖，并在需要手动等待的场景记录结果。任何失败应先定位是否来自本次改动，不借机重写无关模块。

### 命令与交付结果

在仓库根目录依次执行：

```sh
swift build
swift test
git diff --check
git status --short
```

出现编译或测试失败时先修复本次改动造成的问题；环境限制、已有失败或桌面测试跳过要如实报告。当前阶段只扩充文档，以上命令属于后续实施验证，不能把文档检查称为代码测试通过。

交付时必须列出：修改文件、实现的两个自动入口、手动入口为何保持关闭、命令执行结果、手动验收通过项与未验证项。不要自动提交或发布；需要提交时遵守用户的提交格式要求。

### 完成前逐项检查

- [x] 偏好属性的键名在读取与写入两处完全一致，默认 false。
- [x] 总开关切换只保存偏好，不批量修改已有项。
- [x] 导入器的新参数默认 false，且只用于新记录分支。
- [x] AppModel 导入参数严格等于 `!isManual && autoEnableNewSessions`。
- [x] Hook 工厂参数默认 false，AppModel 仅在新状态机创建时传入偏好。
- [x] 已有项合并和 Hook 更新都保留原参与值。
- [x] 不改变来源过滤、删除抑制、状态机与轮播算法。
- [x] 初始参与值在 publishSessions/refreshSessions 前已经确定。
- [x] 开关放在置顶区标题右侧，标签可见，行内开关保留。
- [x] 两类自动入口与手动同步入口分别检查，不能只测 Hook。
- [x] 必要边界测试完成，构建、测试、格式检查结果明确。
- [x] 没有编辑会话数据模型、存储格式或无关设置模块。

## 测试决策与验收

不采用 TDD。不编写镜像实现的测试或 SwiftUI 私有层级测试；新增测试聚焦导入来源、新旧记录边界和状态保留。沿用现有 Hook 工厂、会话导入器以及应用发现链路测试方式。

| 验证场景 | 预期 |
| --- | --- |
| 首次启动或升级，没有偏好键 | 总开关关闭，原有选择保持 |
| 开启后重启 | 总开关仍开启，原有选择保持 |
| 总开关关闭，自动发现或 Hook 新增 | 新项关闭，满足时间条件时正常显示在置顶区 |
| 总开关开启，自动发现新增 | 新项启用，进入 HUD 候选集合 |
| 总开关开启，Hook 新增 | 新项启用，保留事件产生的实际状态 |
| 开启后手动同步历史项 | 新增历史项关闭 |
| 开启总开关，已有关闭项再次活动 | 保持关闭 |
| 已有启用项重复导入或恢复 | 保持启用 |
| 关闭总开关 | 所有已有项的参与状态不变 |
| 请求发出后切换总开关，再返回新项 | 采用合并时的开关值 |
| 自动发现与 Hook 先后处理同一 ID | 无重复项，已有项选择不被覆盖 |
| 手动同步关闭项随后收到 Hook | 保持关闭 |
| 新项启用且没有其他候选 | 现有调度选择新项；隐藏 HUD 不被强制打开 |
| 会话超过 10 分钟活动窗口 | 移出置顶区，参与 HUD 状态不变 |
| 空列表、加载、读取失败 | 总开关始终可见，布局无挤压 |

实施时执行 `swift build` 和 `swift test`。偏好保存、分区标题布局及 HUD 实际表现以手动检查验证；已有发现协调、来源过滤和调度测试应继续通过。

## 范围外

- 批量启用置顶区已有项或全部历史项。
- 重新启用用户手动关闭的会话。
- 后台持续扫描、改变发现间隔或最近活动窗口。
- 改变 HUD 可见性、灯色语义、轮播优先级和展示时长。
- 新增数据库、会话格式迁移或永久删除历史表。

## 补充说明

本 PRD 对历史规范中“所有新发现会话默认关闭”的规则新增可选例外，仅适用于已确认的两个自动入口。默认关闭及手动同步行为继续保留。本轮只写本地文档，不发布外部议题，不提交实现代码。


## 实施与验证记录（2026-10-01）

用户批准后另行授权连续实施、每阶段验证后提交；该授权覆盖本文早先逐文件等待确认及不自动提交的要求。

| 阶段 | 实现及验证 | 提交 |
| --- | --- | --- |
| 一：偏好 | AppModel 新增默认关闭的偏好，使用注入的 UserDefaults 保存；swift build 通过 | 7557921 |
| 二：新增策略 | 自动导入按合并时偏好决定，手动导入强制 false；Hook 新状态机读取偏好，已有项保留选择；17 项相关测试通过 | 4eaae8d |
| 三：界面 | 标题右侧原生开关，保留可见标签及可访问性说明；swift build 通过；680 点宽度深浅色空态截图无截断 | d22fca3 |
| 四：边界及验收 | 新增 6 个测试方法，其中循环覆盖开关两态；17 项导入/Hook 测试通过；完整 180 项测试通过，零失败、零跳过；git diff --check 通过 | 见本记录所在提交 |

### 隔离应用入口验证

使用临时 XCTest 验收驱动，调用未改动可见性的实际 AppModel 方法。临时 TRACEFLOW_HOME 指向独立目录；独立 UserDefaults suite 保存测试偏好。自动发现使用临时模拟 Codex 服务，经现有 zsh、JSON-RPC 与线程列表解析流程返回记录；Hook 通过实际 Unix socket 向监听器发送事件。未写入用户真实会话目录。验收驱动不纳入长期测试，不新增生产测试接口。

以下验证全部通过：

- 总开关初始为关闭；关闭时自动新增为关闭，开启时自动新增为开启。
- 自动新增进入 recentSessions，已有关闭项不被开启。
- Hook 新增项开启并进入实际 HUD 调度输出；关闭总开关后的 Hook 新增项保持关闭。
- 手动关闭的 Hook 会话后续事件不重新开启；关闭总开关不影响之前开启的自动项。
- 手动同步新增项保持关闭，后续 Hook 仍关闭。
- 自动请求处于等待响应时切换总开关，最终合并采用最新值。
- 模拟读取失败后仍可修改并保存偏好。
- 创建新 AppModel 恢复时，总开关及已有项选择均恢复。
- 验证过程中 HUD 可见设置为 false，发现和事件处理未将其打开。

### 视觉检查与实际验证边界

以 NSHostingView 加载真实 SettingsView，在 680 点宽度分别捕获浅色关闭态和深色开启态。已查看截图，开关位于置顶区标题右侧，标签完整，空态正常显示。开关绑定切换由模型属性驱动验证，没有模拟鼠标点击或执行 VoiceOver 操作。

模拟服务验证覆盖实际应用发现入口，但未与用户真实 Codex 服务执行新会话端到端检查；实际退出进程后重启未单独执行，已验证保存后新建模型恢复。加载态和失败态标题持续存在由视图结构及失败状态运行验证确认，未额外截图。时间窗口移出及调度优先级沿用未改动的现有模块，并由完整测试套件覆盖。

初次沙箱构建因编译缓存写入权限失败，随后按权限流程在沙箱外构建成功。临时集成驱动最初异步调用缺少 await、模拟时间戳误用小数，修正验收驱动后通过；生产代码没有因此修改。

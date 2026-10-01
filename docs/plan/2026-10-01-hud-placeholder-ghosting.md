# 保留标题动画的默认名称重影修复规划

Related discussion: [docs/discuss/2026-10-01-hud-placeholder-ghosting.md](../discuss/2026-10-01-hud-placeholder-ghosting.md)

状态：已批准，正在实施。用户授权每阶段验证、提交后立即继续；本轮不安装或部署。

## Problem Statement

实际 HUD 截图中，当前会话标题已经出现，其底部仍可见默认名称 `Traceflow` 的字形。用户重新安装后问题仍在。先前移除项目前缀及修改过渡身份的修复未得到用户实际画面确认。

取消标题动画不是用户接受的方案。修复必须保留原有动画，且不能再以离屏图像或取消动画后的测试通过，证明生产透明浮窗的问题已解决。

## Solution

将静态默认名称与会话动画标题分为互斥分支。只有会话标题进入会话切换的动画容器；跨无会话与有会话边界时立即结束旧分支，避免默认名称成为退出动画保留的视图。

会话之间继续播放原有动画。使用生产 HUDPanelController、透明 NSPanel、背景材质和真实 Hook 入口复现并验收。如果视图已无默认名称而最终窗口仍有残留，再定位标题区域的原生重绘与合成问题。

## User Stories

1. 作为查看会话的用户，我希望会话出现后不再看到默认名称压在标题下方。
2. 作为使用轮播的用户，我希望原来的滑入、滑出和淡入淡出继续正常工作。
3. 作为没有活跃会话的用户，我希望默认名称正常恢复。
4. 作为编辑标题的用户，我希望长标题变短时没有旧文字残留。
5. 作为使用横向或竖向 HUD 的用户，我希望所有布局都遵循同一标题规则。
6. 作为安装应用的用户，我希望修复结果以实际安装包和真实窗口验证，而不是仅验证标题字符串。

## 已确认事实与待验证原因

| 内容 | 证据与结论 |
| --- | --- |
| 当前标题来源 | 已提交的 HUD 读取 `sessionListTitle`，不主动拼接项目名；不能继续把截图残留解释为项目前缀字符串 |
| 默认名称 | 无会话时为 `Traceflow`；截图底部存在相似字形，但单帧截图不足以证明具体图层来源 |
| 标题过渡 | 原默认名称与会话共用 ZStack、身份切换和合成分组，存在需要验证的退出视图生命周期边界 |
| 初始会话 | 调度器从默认状态进入初始会话通常 `animated:false`，因此不能直接宣称所有重影都由正在进行的退出动画造成 |
| 原生窗口 | 生产窗口透明，背景材质与 NSHostingView 为兄弟视图，普通不透明测试窗口不等价 |
| 安装与进程 | 上轮检查中安装包与 dist 一致且只有一个实例，不应默认要求用户反复安装或认定旧版本 |
| 哈希比对 | 原始 release 可执行文件与签名后的包可能不同；不得用签名前后哈希不同单独证明运行版本错误 |
| 实际根因 | 退出视图未释放、图层缓存、画面重绘或其他合成来源均未最终复现确认 |

## Implementation Decisions

### 1. 行为与动画契约

| 切换类型 | 最终文字 | 动画处理 |
| --- | --- | --- |
| 无会话 → 会话 A | A 的会话标题 | 默认分支立即移除；保持调度器原初始展示决定，不人为增加或取消会话轮播动画 |
| 会话 A → 会话 B | B 的会话标题 | 保留原有方向位移及透明度过渡；结束后退出 A 被清除 |
| 会话 A → 无会话 | `Traceflow` | 清理会话分支，恢复静态默认分支；不保留旧会话与默认名称叠加 |
| 同一会话修改标题 | 最新会话标题 | 沿用原不轮播处理，更新同一会话文字，不产生额外旧标题层 |
| 仅状态、颜色、光晕设置变化 | 当前标题 | 不创建新的标题切换，不重置标题身份 |

有会话时文字优先级沿用 `sessionListTitle`：自定义标题、现有默认会话标题来源、最后“未命名会话”。不得回退到 `projectName`，也不能把 `displayTitle` 重新接入 HUD。其他页面和日志的项目拼接语义不在本次改动范围内。

原始动画参考提交 `69338bf` 的 `titleTransition` 与 `titleAnimation`：

- 横向：新标题从下方进入，旧标题向上退出，均结合透明度变化。
- 竖向：新标题从左侧进入，旧标题向右侧退出，均结合透明度变化。
- 滑动最长0.20秒，采用原 easeOut。
- 减少动态效果时保留原 `.opacity` 淡入淡出，0.15秒。
- 非动画决策保持即时更新。
- 先前 `be11766` 将 removal 改为 identity，不作为“原本正常动画”的最终参照；本次须恢复原退出效果，而不只是恢复新标题进入动画。

允许真实会话 A/B 在短暂过渡期间同时存在以完成原动画；禁止默认名称作为轮播的旧会话参加过渡。动画结束后只能留下当前内容。

### 2. 默认与会话分支拆分

建议提取共用的标题区域组件，横竖布局共用以下语义：

```text
固定尺寸标题区域
    若有 displayedSession
        会话动画容器
            只渲染 sessionListTitle
            以真实会话身份区分当前与退出标题
    否则
        静态 Traceflow 占位视图
```

- 默认名称不得作为 `sessionID ?? "placeholder"` 的一种会话标题放进同一动画 ZStack。
- 默认分支与会话分支跨界无父级淡入淡出；禁止把整个标题区域的动画全部禁用来代替边界控制。
- 会话动画只绑定会话展示变化，不让灯光 TimelineView 的更新启动标题过渡。
- 如需标题身份类型，使用明确的枚举或真实会话 ID，不用可能与合法 ID 相撞的字符串哨兵。
- 同一会话标题编辑不通过随机 UUID 重建所有视图。
- 固定标题区域尺寸、截断、字体、颜色与灯光布局均保持现有实现。

### 3. 退出内容的生命周期

优先使用正确的分支与 SwiftUI 过渡生命周期，而不是另建全局标题定时器。

若复现证明 SwiftUI 退出层在快速打断时无法清理，再局限于标题组件管理“当前内容、退出内容、切换标识”：

- 只有真实会话之间的已授权动画可以生成退出内容；默认名称永远不能进入退出内容。
- 每次切换具有版本标识；旧动画完成回调不能删除或覆盖新标题。
- 进入默认分支时立刻清理退出会话内容，取消旧切换的完成处理。
- 最大过渡时间沿用0.20秒；若最新标题迅速到达，旧退出层不能无限堆积。
- 不改变轮播调度、会话状态、保护时间和调度器的 visibleFrom 语义。

以上是备选升级方案，仅在最小分支修复不足时采用。不得在未复现时同时加入多个猜测性补丁。

### 4. 原生重绘的条件处理

只有满足“显示内容已正确、旧默认视图已移除、真实屏幕仍有残留”时，才进入重绘修复：

1. 检查 NSHostingView 及标题子层的透明绘制与脏区域更新。
2. 观察标题变化后是否重绘旧文字占用的完整区域，而不仅重绘新文字覆盖的区域。
3. 如需失效处理，局限于标题区域或对应原生承载视图；保留背景材质与动画帧更新。
4. 竖向自绘 NSView 另行验证旧字形擦除，不能把横向 SwiftUI Text 的结论直接套用。

禁止用以下手段“掩盖”重影：取消动画、增加不透明色块、降低背景透明度、每次刷新重建整个窗口、无限调用 needsDisplay、改变灯效。

## 分阶段修改清单

### 阶段零：恢复正确基线与建立复现

当前未提交试验涉及：

- `Sources/TraceflowApp/HUDView.swift`：取消动画的修改。
- `Tests/TraceflowAppTests/HUDTitleRenderingTests.swift`：普通 NSHostingView 原位重绘测试。
- `dist/Traceflow.app`：已由未提交的无动画试验构建覆盖。

实施开始时先审阅这些差异。撤回应用中的无动画试验，仅撤回自身相关变更；不得全仓库 reset。现有会话标题来源修复保留。

临时普通窗口测试可改造为生产窗口回归，不将其通过结果当作原问题复现证据。完成修复后重新生成 dist；本轮规划不执行这些操作。

用隔离配置、临时 TRACEFLOW_HOME、真实 Hook 入口及 HUDPanelController 创建测试窗口，避免改变用户真实会话、Socket与设置。先运行保留动画的现有基线并记录能否复现。

### 阶段一：拆分默认分支与会话动画容器

主要修改 `Sources/TraceflowApp/HUDView.swift` 的横向、竖向标题区域，必要时提取标题区域组件。保持 `displayedTitle` 会话来源规则，恢复完整原动画契约，显式控制默认分支移除。

运行标题定向验证、核心标题过渡测试与构建。必须包括保留动画的真实窗口验证，不能只看字符串输出。

### 阶段二：快速切换与必要的原生清理

补齐默认→会话、会话→默认、A→B、标题长→短与过渡打断。仅在上一阶段仍复现时选择生命周期备选方案或条件原生重绘修复；修改前记录失败证据。

主要涉及 `Tests/TraceflowAppTests/HUDTitleRenderingTests.swift`；实际证据指向原生承载时才允许修改 `HUDPanel.swift` 或 `VerticalMixedTitleView.swift`。

全量验证通过后提交。未出现的缓存问题不增加预防性绘制补丁。

### 阶段三：构建产物与实际验收记录

重新构建 release应用包，验证签名与打包内容，记录对应 Git 提交。避免仅比较签名前后可执行文件哈希判断版本。

实际透明窗口截图确认没有默认名称残留，同时确认原方向动画仍可见。记录未完成的人工观察，不在未验收时宣称“彻底修复”。安装或替换用户当前应用需后续明确授权。

## Testing Decisions

跳过TDD。复用现有标题过渡检查与会话集成夹具，增加真实透明浮窗的结果验证。先复现以定位缺陷不视为引入TDD流程。

### 验证矩阵

| 场景 | 必须检查 |
| --- | --- |
| 默认 → 自定义标题 `123------` | 结束后没有底层 Traceflow 字形，初始显示遵循原调度决定 |
| 红/黄/绿会话 → 默认 | 会话退出内容不压在默认名称下方 |
| 会话 A → B | 原滑入滑出与透明度过渡存在，0.20秒结束后仅B |
| A→B未结束即切C | 不保留占位，不堆积旧文字，旧完成回调不清除C |
| 长标题 → `短` | 新短标题外侧无旧文字残留 |
| 会话标题或项目名恰为Traceflow | 验证实际显示身份与内容，不能仅通过搜索文字Traceflow判断失败 |
| 无标题活跃会话 | 只显示“未命名会话”，不回退项目名 |
| 减少动态效果 | 保留0.15秒淡入淡出，结束后退出内容清理正确 |
| 四种布局 | 同一内容规则，尺寸不变、竖向重绘正确 |
| 浅深背景、背景透明度10%/100% | 底层文字和背景透出分别识别；不通过改变背景修复 |

### 截图与动画采样要求

- 使用生产透明 NSPanel、真实背景材质与同样的 HostingView层级，不用普通不透明测试窗口替代。
- 采样更新前、动画中、动画结束后至少0.30秒三个阶段；持续性残留需再观察1秒。
- 实时时钟会影响灯效，像素比对仅裁标题区域；四布局裁剪坐标按实际坐标方向计算，尤其竖向CGImage与NSView坐标差异。
- 使用受控浅灰/深色背景或测试窗口后方受控图像，避免把桌面后方文字透过HUD误判为旧标题。
- `cacheDisplay`只验证视图绘制，不能独自证明WindowServer最终合成正确。条件允许时保留实际屏幕截图；测试产物只截隔离HUD，不收集无关桌面内容。
- 不同标题长度或PNG逐字节差异不能证明动画存在；需要观察标题位置或透明度中间帧。
- 若固定等待用于观察动画结束，时间须大于原动画上限；模型事件完成仍用现有夹具等待特定事件，不能盲等后读取过期状态。

```sh
swift test --filter HUDTitleRenderingTests
swift test --filter HUDTitleTransitionTests
swift test
swift build
git diff --check
./scripts/build-app.sh
```

每阶段按改动范围运行验证，全量通过后不无理由重复运行。检查失败必须记录实际原因，不扩大到无关功能修复。

## 验收标准

- 默认名称与会话内容按状态互斥，最终画面没有旧默认字形。
- 真实会话之间原滑入、滑出、淡入淡出与时间上限均保留。
- 同会话编辑、快速打断、回默认均清理正确。
- 四布局与生产透明浮窗通过，灯效和背景行为未改变。
- 原问题基线是否复现、修复后是否消失、实际屏幕是否验收有明确记录。
- 若基线未能复现，不以自动测试通过宣称根因已找到；报告验证范围与待观察项。

## Out of Scope

- 取消动画、仅保留进入动画、强制固定标题不切换。
- 改变会话标题编辑、项目分组、轮播策略、灯效或窗口尺寸。
- 通过opaque背景、强制重建整个应用或要求用户反复安装掩盖缺陷。
- 本轮修改应用、提交试验代码、安装或部署。

## 批准与执行

本修复规划需用户明确批准后实施。实施时沿用会话已有的“每阶段验证、提交后立即继续”授权，不在阶段间再次确认；如需要新的关键业务决定或发现无法自行解决的错误，再暂停说明。

Git提交使用 `type(scope): 简体中文描述`；PRD关联路径放提交正文。未提交无动画试验不能混入最终提交。

## 执行模型编码细则

本节为确定的执行清单，不能以“保持差不多的效果”代替原动画契约。所有路径相对于仓库根目录。当前状态是文档待批准，以下操作仅在后续实施获授权时执行。

### A. 基线恢复必须有选择地进行

1. 先查看 `git status --short` 与两个相关文件的 `git diff`。确认仍只有此前自身的无动画试验，不覆盖用户新改动。
2. 从当前提交版本恢复 `HUDView.swift` 中被删除的标题容器和动画辅助函数；保留已有 `displayedTitle = sessionListTitle ?? "Traceflow"` 逻辑、灯效同步实现以及其他已提交修复。
3. 从提交 `69338bf` **只参考**原始 `titleTransition`、`titleAnimation` 的语义，不恢复整个旧文件，否则会丢失后续灯效和会话标题修复。
4. 将临时 `testLiveHostingViewClearsOldTitlePixels` 改造为使用真实HUD控制器的测试。不能删除已有回归，也不能保留“更换HostingView后通过”作为重影不存在的充分证据。
5. 不运行 `git reset --hard`，不清空工作区，不删除整个测试文件。恢复完成后检查差异，确认取消动画的 `.transaction { $0.animation = nil }` 没有留在全部会话动画子树上。
6. 此时dist可能仍是无动画试验产物。完成最终实现后由构建脚本重建；不能将这个包提前交付给用户验证。

### B. 标题文字只能从一个入口获取

保留 `HUDView.displayedTitle` 供语义检查与无障碍描述使用：

```swift
var displayedTitle: String {
    model.displayedSession?.sessionListTitle ?? "Traceflow"
}
```

绘制分支需显式取得会话快照，而不是所有分支都把 `displayedTitle` 当成动画项：

```text
if let session = model.displayedSession
    绘制 session.sessionListTitle
else
    绘制常量 "Traceflow"
```

禁止替换成以下表达式：

- `session.displayTitle`：包含项目名前缀。
- `session.persisted.projectName`：不是会话标题。
- `session.id` 或项目名称作为缺失标题时的显示回退。
- `sessionID ?? "placeholder"` 作为默认名称加入会话动画容器的身份。

会话标题本身可以合法地包含Traceflow，不能通过删除字符串中的“Traceflow”解决重影；必须按显示身份区分默认分支与当前会话。

### C. 建议的最小分支结构

优先在 `HUDView` 提取共用 `titleRegion(vertical:)` 与 `titleContent(_:vertical:)`。调用处的横向、竖向灯区域、图标区域保持原样，只有 `.title` 区域替换为该组件。

以下代码描述建议结构，需要在真实窗口验证其事务行为，不是未经复现就能证明修复完成的答案：

```swift
@ViewBuilder
private func titleRegion(vertical: Bool) -> some View {
    Group {
        if let session = model.displayedSession {
            ZStack {
                titleContent(session.sessionListTitle, vertical: vertical)
                    .compositingGroup()
                    .id(session.id)
                    .transition(titleTransition(vertical: vertical))
            }
            // Only real session-to-session changes receive this animation.
            .transaction { $0.animation = titleAnimation }
            .transition(.identity)
        } else {
            titleContent("Traceflow", vertical: vertical)
                .transition(.identity)
        }
    }
    // Keep the existing outer title-lane dimensions here.
    .frame(
        width: vertical ? HUDMetrics.shortAxis : HUDMetrics.titleLength + HUDMetrics.separatorThickness * 2,
        height: vertical ? HUDMetrics.titleLength + HUDMetrics.separatorThickness * 2 : HUDMetrics.shortAxis
    )
    .clipped()
    // Suppress parent branch transitions; the inner session container sets
    // its own animation. Do not set disablesAnimations = true.
    .transaction { $0.animation = nil }
}
```

`titleContent` 只画传入的字符串，不自行再次读取 `model.displayedSession`，不添加身份、不添加过渡：

```swift
@ViewBuilder
private func titleContent(_ text: String, vertical: Bool) -> some View {
    if vertical {
        VerticalMixedTitleView(title: text, color: model.hudTitleColor)
            .frame(width: HUDMetrics.shortAxis, height: HUDMetrics.titleLength)
    } else {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(model.hudTitleColor == .white ? Color.white : Color.black)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: HUDMetrics.titleTextLength, alignment: .leading)
    }
}
```

重要限制：

- 外层Group仅保证占位与会话分支跨界不动画；**内层会话ZStack必须覆盖回titleAnimation**。如果实际采样发现A→B没有动画，此结构尚未达标，不能交付。
- 禁止外层 `transaction.disablesAnimations = true`，它会阻止内部会话动画。
- 在同一个ZStack里用两个 `opacity` 控制默认与会话可见性，不算拆分；默认内容必须从分支树里移除。
- 含默认名称的分支没有 `.id(sessionID ?? ...)`，没有与会话一起参与的 `.transition(.opacity)`。
- 退出视图内容由当时会话字符串构造，不在旧绘制视图内部临时从最新模型取默认名称，以免切回nil时旧会话层意外画出默认文字。
- 不加 `.id(UUID())`、不重建整个HUD、不改变灯或背景。
- 外层固定尺寸为横向276×40或竖向40×276；横向文字263、竖向文字275，沿用现有几何。禁止因重影修复改变这些尺寸。

### D. 必须恢复的动画辅助函数

从旧提交参考后，函数应与以下行为一致：

```swift
private func titleTransition(vertical: Bool) -> AnyTransition {
    switch HUDTitleTransition.style(
        shouldAnimate: model.shouldAnimateDisplayChange,
        reduceMotion: reduceMotion
    ) {
    case .none:
        return .identity
    case .fade:
        return .opacity
    case .slide:
        return .asymmetric(
            insertion: .move(edge: vertical ? .leading : .bottom).combined(with: .opacity),
            removal: .move(edge: vertical ? .trailing : .top).combined(with: .opacity)
        )
    }
}

private var titleAnimation: Animation? {
    switch HUDTitleTransition.style(
        shouldAnimate: model.shouldAnimateDisplayChange,
        reduceMotion: reduceMotion
    ) {
    case .none: return nil
    case .slide: return .easeOut(duration: HUDTitleTransition.maximumDuration)
    case .fade: return .easeInOut(duration: 0.15)
    }
}
```

- 不把removal改成identity，不改maximumDuration，不修改调度器计时以掩盖动画消失。
- “默认分支立即消失”只约束默认/会话边界，不代表会话A也要立即消失；真实A→B应保留原退出动画。
- 同会话编辑与状态更新不改变session.id，不强制执行轮播动画。
- 模型目前先发布 `shouldAnimateDisplayChange`，再发布 `displayedSession`；测试记录两个值与当前ID。如果证据表明更新顺序或后续状态刷新打断了动画，再局部处理这一问题，不默认重写整个AppModel。

### E. 真实生产窗口测试的构建方式

建议测试建立顺序：

```swift
_ = NSApplication.shared
let fixture = try SessionIntegrationFixture()
defer { fixture.cleanUp() }
fixture.model.autoEnableNewSessions = true
let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
defer { controller.hide() }
controller.show()
```

使用controller创建的window/contentView进行绘制与采样；不要自己替换它的NSHostingView或background，否则测试条件不再等于生产窗口。无桌面屏幕时按既有测试风格XCTSkip并明确报告，没有屏幕不能声称实际窗口验证通过。

测试夹具隔离用户环境，并经Unix socket发送真实Hook。根据已有夹具接口设置标题，不调用模型私有setter。

| 事件或操作 | 期望 |
| --- | --- |
| 会话A `userPromptSubmit` | A运行并参与展示，初始显示通常不动画 |
| A设置自定义标题 `123------` | 仅该字符串，无默认文字残留 |
| 会话B `permissionRequest`，A当前为绿 | B抢占A，产生真实A→B动画 |
| B `interrupt`，A仍运行 | 返回另一个活跃会话，遵循现有调度决定 |
| 将A/B都设为不参与HUD | 恢复默认名称，无会话退出残留 |
| 长标题编辑为 `Q` | 显示短字符串，原字形外侧不再保留 |

通过fixture.waitUntil等待模型处理对应事件；记录当前 `displayedSession.id` 和 `shouldAnimateDisplayChange`，确保动画用例确实命中了动画分支。不要用同会话改名冒充会话切换动画验证。

### F. 三种验证不能互相替代

1. **内容验证**：`displayedTitle`符合规则。它只证明字符串正确。
2. **原生视图验证**：生产窗口内视图绘制结束后无旧字形。cacheDisplay可以辅助，但不要替换hosting或强制全窗口重建使结果通过。
3. **屏幕合成验证**：透明HUD在受控背景上的最终画面没有旧字形；实际屏幕截图或人工观察是独立结果。

不得写“字符串断言通过，因此截图问题已修复”。也不得写“普通窗口通过，因此透明HUD通过”。

采样建议：

- 切换前保存旧标题区域画面。
- A→B真实动画开始后，在约0.05秒与0.10秒采中间帧；不要只等待0.30秒观察结束。
- 0.30秒后采稳定帧，1秒后再采帧排查持续性残留。
- 系统帧调度可能使某个固定时刻错过动画；若没有中间帧，记录情况并重试该具体动画观察，不通过延长原动画来方便测试。
- 横向观察垂直位移、竖向观察水平位移；减少动态效果观察alpha变化。以文字区域墨迹分布或位置辅助判断，不以PNG哈希不同作为动画存在的唯一证明。
- 使用“123------”及“Q”等与Traceflow形状不同的标题，不只用包含Traceflow的名称来判断旧默认字形。
- 后方测试背景使用无文字纯色，与HUD有稳定位置关系，避免把透出的桌面文本误判成重影。
- 截图只捕获隔离HUD区域；若系统截图权限不可用，明确记录屏幕合成验收待完成，不能绕过权限或把cacheDisplay写成屏幕截图。

### G. 失败后如何选择下一步

| 观察 | 下一步 |
| --- | --- |
| 当前字符串仍含项目名前缀 | 检查是否错误接回displayTitle；只修内容来源 |
| 默认分支仍作为退出内容存在 | 修标题组件的分支/身份/退出生命周期 |
| 视图内容与默认分支均正确，透明窗口仍残留 | 检查实际承载层重绘与合成缓存，记录证据后做标题区域修复 |
| 快速A→B→C留下旧视图 | 启用本文备选切换标识与退出状态管理，不添加随机ID |
| 动画消失，但重影消失 | 本修复失败；恢复动画事务，而不是交付无动画版本 |
| 基线未复现，修订也未出现残留 | 报告结构改进和验证边界，不宣称已找到确定根因 |

不能一开始同时加needsDisplay、随机身份、全窗口重建和标题定时器。每个补丁必须对应可观察失败，验证是否解决该失败。

### H. 备选生命周期管理的具体不变量

只有最小分支方案不足时采用；状态局限于标题组件：

- 当前项：真实会话ID及其字符串快照，或默认状态。
- 退出项：至多一个真实会话字符串快照，不允许默认名称。
- 切换版本：单调增加或唯一token，用于判别完成回调是否仍有效。
- 每次开始新切换时先废弃旧完成回调；不能让过期回调清除新当前项。
- 回默认时取消退出项及完成任务，默认立即成为唯一静态显示分支。
- 同ID更新标题只更新当前字符串，不能制造第二个同ID退出项。
- 0.20秒动画结束或最新切换完成后，退出项为空；允许系统渲染调度容差，不能无限保留。
- 如果减少动态效果，仅改变过渡风格与时长，不改变标题内容规则。

如需要改变这一状态约束、取消原动画或调整业务展示规则，先更新PRD并获得用户批准；普通实施细节不反复请用户确认。

### I. 发布包和完成记录

最终记录至少包括：基线提交、修复提交、生产窗口是否复现、哪条路径失败/通过、原动画中间帧是否观察到、原生与屏幕合成验证各自的结果。

- 用 `./scripts/build-app.sh` 重新生成最新包，检查签名；不能把此前无动画dist包标为已修复。
- 用户授权安装后才运行install脚本。默认脚本会重新release构建、打包、退出原安装路径进程并启动；不要为了加快验证改默认安装逻辑。
- 安装版本比对以同一次签名打包后的dist包和安装包为准；原始 `.build/release/Traceflow` 与签名包哈希不同不是旧版本证据。
- 当前安装包Info.plist版本固定0.1.0/1，不足以证明具体Git提交；如需要提交溯源记录，可放在验证文档或本轮构建记录，不在这次修复顺便重做版本系统。
- 原标题转场与最终画面均验证通过才可称“修复已验收”；若实际屏幕验证缺失，写“编码与自动验证完成，屏幕观感待验收”。

### J. 交付前检查清单

- [ ] 无动画试验未混入最终提交。
- [ ] 默认名称位于静态分支，不参与会话ZStack转场。
- [ ] 会话只读取sessionListTitle，缺失时为未命名会话。
- [ ] 原插入与退出方向、opacity、0.20/0.15秒行为恢复。
- [ ] 默认边界不叠加，真实会话动画仍存在。
- [ ] 长变短、快速打断、回默认均检查。
- [ ] 真实HUDPanelController与透明背景验证，而非普通窗口替代。
- [ ] 原生绘制与屏幕合成结果分开记录。
- [ ] 灯效、轮播策略、背景透明度、几何尺寸未改变。
- [ ] 定向测试、全量测试、构建和格式检查结果明确。
- [ ] 最终dist已重建；没有擅自安装或部署。

## 实施记录

### 阶段零

- 基线提交：`3758bf5`。选择性撤回无动画试验，恢复0.20秒双向滑动和0.15秒淡入淡出。
- 普通测试窗口改为生产HUDPanelController；不替换受测HostingView或背景。
- `swift test --filter HUDTitleRenderingTests`：2项通过；`git diff --check`通过。
- 保留完整动画的基线在原生视图cacheDisplay中未复现持续默认字形残留。该结果不能证明WindowServer画面无重影，也不能证明动画中间帧存在。

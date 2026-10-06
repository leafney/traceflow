# HUD 图标区域显示模式产品需求文档

Related discussion: [docs/discuss/2026-10-06-hud-icon-visibility.md](../discuss/2026-10-06-hud-icon-visibility.md)

状态：五阶段功能开发及可执行自动验证已完成；真实屏幕截图因缺少录屏权限未验收，不能据此宣称实屏无残影。验证记录：[docs/verification/2026-10-06-hud-icon-visibility.md](../verification/2026-10-06-hud-icon-visibility.md)。最新授权：连续完成五个阶段，每阶段运行对应验证并提交 Git，提交后立即继续；仅无法自行解决的错误、关键业务决策或全部阶段完成时暂停。此授权覆盖本文逐文件暂停和不自动提交的旧要求。

阅读要求：全文必须读完，尤其文末“编码执行细则”。细则将前文方案落实为具体文件、接口与操作顺序；如两处表述粒度不同，以细则为准。本文中的代码片段是接口契约或局部示例，不是完整文件，不得用片段覆盖整个源文件。

## Problem Statement

图标区域目前只随背景透明度自动显示或隐藏。用户无法在高透明度下保留图标，也无法在低透明度下移除图标。新增控制需要覆盖四种 HUD 布局，并同时处理图标可见性和所占空间，避免出现隐藏后留白或显示时被裁切。

## Solution

设置页“背景透明度”下方新增“图标区域”三段选择：自动、始终显示、始终隐藏。默认自动，四种布局共用，选择立即生效并保存，重启恢复。

| 模式 | 透明度 0%～79% | 透明度 80%～100% |
| --- | --- | --- |
| 自动 | 显示 | 隐藏 |
| 始终显示 | 显示 | 显示 |
| 始终隐藏 | 隐藏 | 隐藏 |

显示时长轴 420 点；隐藏时收起 40 点，长轴 380 点；短轴保持 40 点。复用约 0.2 秒的图标淡入淡出和尺寸过渡。背景透明度仅继续控制现有背景外观；手动模式优先于透明度阈值。

## User Stories

1. 作为用户，我希望默认采用自动模式，以保持升级前行为。
2. 作为用户，我希望自动模式在 79% 显示、80% 隐藏，以获得明确的阈值行为。
3. 作为用户，我希望背景全透明时仍能选择显示图标。
4. 作为用户，我希望背景不透明时也能选择隐藏图标。
5. 作为用户，我希望隐藏图标同时收起空间，避免 HUD 留白。
6. 作为用户，我希望四种布局共用选择，切换布局无需重复设置。
7. 作为用户，我希望更改模式立即看到结果，重启后保留选择。
8. 作为用户，我希望调整透明度后手动模式保持有效。
9. 作为用户，我希望回到自动时立即按照当前透明度决定显示状态。
10. 作为用户，我希望连续切换模式时过渡平滑，最终显示最后一次选择。
11. 作为用户，我希望切换模式不改变已保存位置、钉住状态或会话内容。
12. 作为使用辅助功能的用户，我希望控件具有明确标签，并遵循减少动态效果设置。

## Implementation Decisions

### 模块与接口

1. **偏好模块**：新增三值图标显示模式，建议枚举名 `HUDIconVisibilityMode`，值为 `automatic`、`alwaysShow`、`alwaysHide`。新增独立偏好键 `hudIconVisibilityMode`。缺失、非法值或错误类型回退自动；不改变已有透明度数值。
2. **外观与几何模块**：由透明度和图标模式共同解析最终紧凑状态。现有外观对象可增加模式参数，默认自动以兼容既有调用；尺寸和显示位置统一依赖解析结果，背景透明度计算仍只取透明度。几何状态增加模式及更新入口，目标矩形使用完整状态。
3. **应用模型**：发布图标模式并持久化。启动时先加载透明度和模式，再计算图标可见比例，避免短暂闪现错误状态。
4. **窗口控制模块**：订阅模式变化，复用现有几何更新和尺寸过渡。所有启动、显示、位置恢复、过渡完成、布局或会话展示模式导致的窗口替换路径，统一使用最新模式。
5. **设置视图**：新增带标签的三段选择，绑定同一个模型属性。说明文案：“自动：背景透明度达到 80% 时隐藏图标区域。” 不增加菜单栏入口。
6. **HUD 内容视图**：继续以图标可见比例控制淡入淡出与区域长度；检查现有绑定能否直接复用，不新增独立透明度判定。

### 四种布局的尺寸与锚点

| 布局 | 图标位置 | 尺寸变化固定边 |
| --- | --- | --- |
| 横向左 | 标题右侧 | 左侧状态灯端 |
| 横向右 | 标题左侧 | 右侧状态灯端 |
| 竖向上 | 标题下方 | 上侧状态灯端 |
| 竖向下 | 标题上方 | 下侧状态灯端 |

显示尺寸为横向 420×40、竖向 40×420；隐藏尺寸为横向 380×40、竖向 40×380。沿用参考矩形和屏幕边界约束；屏幕边缘为保证可见可以调整显示位置，不覆盖原始位置锚点。尺寸切换本身不写入位置偏好。

### 状态交互

- 模式切换不重置背景透明度、标题颜色、光晕或会话轮播。
- 手动模式下透明度变化继续更新背景，但不引发图标收缩或展开。
- 不改变最终可见状态的模式切换只保存模式，不重复播放尺寸动画。
- 过渡中再次切换，从当前可见矩形和图标比例继续过渡，最终采用最新状态。
- 拖动过程中模式立即保存，尺寸变化沿用现有延后策略，拖动结束后应用最新目标，避免窗口在指针下突然改变大小。
- HUD 隐藏期间不主动显示窗口；再次显示时采用最新模式与尺寸。
- 布局或会话展示模式导致窗口替换时携带最新模式，不恢复为仅根据透明度计算。
- 减少动态效果时直接采用终态；减少透明度不覆盖用户图标模式。

### 实施顺序

1. 增加模式、偏好加载保存及默认回退。
2. 统一最终显示判定，贯通外观与几何状态。
3. 接入应用模型及窗口更新、初始化和替换路径。
4. 设置页新增控件与阈值说明。
5. 补充必要的边界和复杂状态测试，完成四布局实屏验收。

按上述五阶段连续推进；每阶段验证并提交后立即继续，不逐文件等待确认。

## Testing Decisions

不采用 TDD。测试关注外部行为，仅补充边界逻辑和复杂状态转换，沿用已有偏好、外观、几何及窗口控制测试结构。

- 判定与偏好：三种模式 × 0、79、80、81、100%；缺失和非法配置回退；重启加载保持模式。
- 四布局几何：显示／隐藏尺寸、状态灯侧锚定、参考矩形往返、屏幕边缘反复展开收起不漂移、不覆盖保存位置。
- 复杂交互：动画中反向切换、拖动中切换后应用最终模式、隐藏后重新显示、布局与会话展示模式替换窗口后模式有效。
- 回归：自动模式透明度跨阈值仍正常；手动模式跨阈值图标不变化；减少动态效果立即到终态。
- 实屏验收：四布局分别检查 79% 与 80% 自动行为、100% 始终显示、0% 始终隐藏；快速切换模式和布局无残影、裁切或额外留白。
- 实现后执行相关测试及构建；实屏检查若受环境限制，明确记录未验证项，不以模型或离屏测试代替实屏结论。

## Out of Scope

- 四布局分别保存图标模式。
- 菜单栏快捷入口、透明度阈值自定义。
- 更换图标图案、调整标题或状态灯区域尺寸。
- 重构既有窗口替换、会话轮播、位置存储或光晕算法。
- 安装部署及发布；业务代码修改和阶段提交已获用户授权。

## Further Notes

当前代码阈值为 80%，自动模式以此和本次用户要求为准；旧背景透明度文档中的 90% 不适用于本需求。用户已确认共用模式及仅设置页入口，其他实现与测试细节已随本文批准生效。

## 编码执行细则

### 已授权后续修复：自动阈值附近的过渡流畅度

用户实测反馈：自动模式在 80% 附近调整透明度时，图标显隐过渡卡顿。本次属于已授权功能的动画修复，沿用连续验证、提交规则，不变更三种模式、阈值及最终几何。

- 用 macOS 14 原生视图显示链接驱动尺寸动画，跟随窗口所在屏幕刷新；使用弱引用回调，隐藏、拖动、窗口替换和完成时停止驱动。
- 保留约 0.2 秒完整过渡；中断后的短距离过渡按剩余比例缩短，最短约 0.05 秒。
- 反向时继承当前图标比例速度，使用有界三次插值平滑减速再反向；图标比例始终处于 0～1，矩形使用同一插值。
- 相同目标不重启动画；每帧提交图标比例、窗口和内容尺寸，正常刷新显示，避免强制即时重绘。
- 增加纯插值速度连续性、边界与短距离测试，以及四布局自动模式连续跨阈值、同侧更新、窗口生命周期回归。
- 自动测试不能证明用户实屏感受已改善，录屏权限限制仍单独记录。

本节按用户要求额外提供文件路径、接口形状和操作细节，供编码模型直接执行。路径均相对仓库根目录。先检查仓库当前版本；若目标函数已变动，按职责定位，不依赖行号。发现需求冲突时先更新本文并取得用户批准，不能自行扩大范围。

### 1. 唯一判定入口和字段含义

采用扩展现有 `HUDBackgroundAppearance` 的方案，不再另建第二套图标策略服务。

| 名称 | 含义 | 谁负责修改 |
| --- | --- | --- |
| `hudIconVisibilityMode` | 用户选择，三值枚举，全局共用 | 设置控件通过应用模型写入 |
| `compact` | 当前目标是否隐藏图标、收起区域 | 外观对象按透明度与模式计算 |
| `hudIconFraction` | 当前画面图标比例，动画中可为 0～1 | 模型初始化；此后由窗口控制器更新 |
| `reference` | 未经屏幕约束的完整 420 点参考矩形 | 现有位置恢复及用户拖动流程 |
| `transitionTarget` | 当前尺寸动画的目标显示矩形 | 现有窗口尺寸动画流程 |

必须分清“用户选择”“目标状态”“动画当前状态”。例如用户刚选始终隐藏，目标比例是 0，但动画尚未结束时当前比例可能是 0.6。不能在模式属性的 `didSet` 中将当前比例直接设为 0，否则图标先消失、窗口后收缩。

`compact` 的完整规则只有三条：

```swift
switch iconVisibilityMode {
case .automatic: transparency >= Self.iconHiddenThreshold
case .alwaysShow: false
case .alwaysHide: true
}
```

该片段用于现有 `compact` 计算属性，阈值常量仍为 80。其他生产代码禁止另写 `transparency >= 80` 来决定图标。

### 2. 逐文件改动与完成条件

#### 任务一：`Sources/TraceflowCore/HUDPreferences.swift`

在已有 HUD 枚举附近增加枚举，明确接口：

```swift
public enum HUDIconVisibilityMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case alwaysShow
    case alwaysHide
    public var id: String { rawValue }
}
```

在 `HUDPreferences` 增加：

- `public static let iconVisibilityKey = "hudIconVisibilityMode"`。
- `public func loadIconVisibilityMode() -> HUDIconVisibilityMode`。
- `public func saveIconVisibilityMode(_ mode: HUDIconVisibilityMode)`。

加载时以 `defaults.string(forKey:)` 读取，用枚举原始值解析，失败返回 `.automatic`。加载不必写入默认值；仅保存用户选择时写入 `mode.rawValue`。不得把 `hudIconFraction` 或透明度写入该键。

完成条件：三个合法值可保存、跨偏好实例恢复；缺失、未知字符串、数字、布尔值均返回自动。既有偏好键和透明度默认值 10 均不变。

#### 任务二：`Sources/TraceflowCore/HUDBackgroundAppearance.swift`

- 增加 `public let iconVisibilityMode: HUDIconVisibilityMode`。
- 初始化接口调整为 `public init(_ value: Int, iconVisibilityMode: HUDIconVisibilityMode = .automatic)`，继续使用原有归一化函数。
- `compact` 改为上节三分支判定。
- `size(_:)`、`displayFrame(_:layout:)` 继续通过 `compact` 获取状态；现有尺寸和偏移计算无需重写。
- `backgroundAlpha`、`materialAlpha`、`normalize(_:)`、`referenceFrame(_:layout:)`、`HUDSizeTransition` 保持既有算法。

完成条件：单参数构造仍代表自动模式；始终显示时 100% 得到 420 点，始终隐藏时 0% 得到 380 点；相同透明度不同图标模式的背景透明度结果完全一致。

#### 任务三：`Sources/TraceflowCore/HUDGeometryState.swift`

- 增加 `public private(set) var iconVisibilityMode: HUDIconVisibilityMode`。
- 初始化接口为 `public init(transparency: Int, pinned: Bool, iconVisibilityMode: HUDIconVisibilityMode = .automatic)`，保存模式。
- 增加 `public mutating func setIconVisibilityMode(_ mode: HUDIconVisibilityMode)`，只更新模式，不修改 `reference`、透明度或交互状态。
- 增加 `public var appearance: HUDBackgroundAppearance`，由自身透明度和模式构造完整外观对象。
- `target(layout:visible:)` 改为使用 `appearance.displayFrame(...)`。
- 保留拖动中目标返回 `nil`、屏幕约束、拖动结束依据真实窗口恢复参考矩形等逻辑。

完成条件：在同一参考矩形下切换模式能正确改变目标；拖动中保存最新模式但不生成几何目标；模式来回切换不会修改原始参考矩形。

#### 任务四：`Sources/TraceflowApp/AppModel.swift`

- 在 HUD 偏好属性附近增加 `@Published var hudIconVisibilityMode: HUDIconVisibilityMode`。
- `didSet` 只调用 `hudPreferences.saveIconVisibilityMode(hudIconVisibilityMode)`。
- 初始化时加载模式，再和已加载透明度共同构造外观，初始化 `hudIconFraction = appearance.compact ? 0 : 1`。
- 可以使用局部常量保存加载结果，避免在所有存储属性初始化完成前访问实例计算属性。
- 不改 `previewTransparency`、透明度草稿、松手保存和退出保存逻辑。图标模式选择是立即保存，不复用透明度草稿。

完成条件：偏好为 100%＋始终显示时，模型创建完成比例就是 1；0%＋始终隐藏时就是 0。仅模式属性改变时不得直接跳变图标比例。

#### 任务五：`Sources/TraceflowApp/HUDPanel.swift`

这是主要集成任务，必须核查下表每一项，不能只新增订阅。

| 入口 | 必须改动 |
| --- | --- |
| 控制器字段 | 增加持有订阅的 `iconVisibilityObserver: AnyCancellable?` |
| 控制器初始化几何 | 将模型模式传入 `HUDGeometryState` 初始化 |
| 控制器初始化尺寸 | 使用已初始化 `geometry.appearance.size(layout)` |
| 模式订阅 | 见下一节，更新几何模式后调用既有尺寸更新 |
| `replacePanel` 初始尺寸 | 使用 `nextGeometry.appearance.size(targetLayout)` |
| `replacePanel` 创建前图标比例 | 使用 `nextGeometry.appearance.compact ? 0 : 1` |
| `finishTransition` 图标终态 | 使用 `geometry.appearance.compact ? 0 : 1` |
| `updateGeometry` 外观和比例目标 | 使用 `geometry.appearance`，目标矩形仍由 `geometry.target` 获取 |
| 位置恢复、再次显示、屏幕变化 | 继续走几何目标；确认没有绕过模式的新尺寸计算 |

新增订阅的局部示例：

```swift
iconVisibilityObserver = model.$hudIconVisibilityMode
    .removeDuplicates().dropFirst()
    .sink { [weak self] value in
        guard let self else { return }
        self.geometry.setIconVisibilityMode(value)
        if !self.geometry.interaction.isDragging {
            self.updateGeometry(animated: true)
        }
    }
```

订阅保存到字段，不能只创建临时变量。沿用控制器当前主线程运行方式；不要增加后台队列或异步跨线程更新窗口。

`@Published` 发布发生在属性存储更新之前：必须用订阅参数 `value` 更新几何，不能在这个同步回调内读取 `model.hudIconVisibilityMode` 作为新值。`updateGeometry` 和 `finishTransition` 使用几何中的外观，因此能拿到正确的新模式。

模式变化本身不调用 `background.update`、`replacePanel`、`restorePosition`、`savePosition` 或 `orderFrontRegardless`。背景仍由透明度订阅更新。真正布局或会话展示模式变化继续走已有窗口替换，不改变其释放旧窗口的流程。

`replacePanel` 中保留 `nextGeometry = geometry` 的模式复制。不能用只传透明度的初始化重新创建 `nextGeometry`。既有窗口替换选择保存当前矩形或动画目标的分支保留，测试验证新窗口尺寸与目标图标比例一致；若同时发生模式与展示模式切换，尺寸动画目标必须采用最新几何状态。

`updateGeometry` 已有“相同动画目标不重启”的逻辑继续复用。新目标不同时，先取消旧定时器，再以当前 `window.frame` 和当前 `hudIconFraction` 创建过渡。不能先调用 `finishTransition()` 再创建反向动画，这会先跳到旧终态。

完成条件：模式切换本身保留同一窗口；真正布局或会话展示模式变化仍按现有规则替换窗口；两种情况均使用正确图标状态，窗口阴影仍关闭。

#### 任务六：`Sources/TraceflowApp/SettingsView.swift`

在背景透明度的整个 `VStack` 之后、标题颜色的 `HStack` 之前插入：

```swift
Picker("图标区域", selection: $model.hudIconVisibilityMode) {
    Text("自动").tag(HUDIconVisibilityMode.automatic)
    Text("始终显示").tag(HUDIconVisibilityMode.alwaysShow)
    Text("始终隐藏").tag(HUDIconVisibilityMode.alwaysHide)
}
.pickerStyle(.segmented)
.accessibilityLabel("图标区域")
Text("自动：背景透明度达到 80% 时隐藏图标区域。")
    .font(.caption)
    .foregroundStyle(.secondary)
```

三项顺序固定；即使 HUD 当前隐藏或钉住，也允许选择。继续使用模型枚举绑定，不增加局部 `@State` 镜像或“应用”按钮。设置页仅显示产品规则，不显示偏好键、类名等实现细节。

完成条件：三项选择无布局拥挤，当前值与模型一致，辅助功能能识别控件。

#### 任务七：检查无需改动的文件

- `Sources/TraceflowApp/HUDView.swift`：已有图标透明度、区域长度和总长度均使用 `hudIconFraction`，继续复用；禁止通过 `if` 删除图标视图后另加一套动画。背景描边只读取 `backgroundAlpha` 的单参数外观构造可以保留。
- `Sources/TraceflowApp/HUDBackgroundView.swift`：只读取背景外观，单参数构造可以保留，无需增加图标模式参数。
- `Sources/TraceflowApp/TraceflowApp.swift`：本需求不改菜单，不新增图标模式入口或观察器。
- 位置存储、窗口展示类、状态灯算法：无需因本功能改结构。

### 3. 坐标计算实例，防止上下方向写反

窗口几何采用 AppKit 屏幕坐标，`y` 增大表示向上；SwiftUI 的内容排列视觉方向不能直接套到窗口原点。

取完整参考矩形原点 `(100, 200)`，远离屏幕边缘。结果必须为：

| 布局 | 显示图标时 `(x,y,w,h)` | 隐藏图标时 `(x,y,w,h)` | 相等的固定边 |
| --- | --- | --- | --- |
| 横向左 | `(100,200,420,40)` | `(100,200,380,40)` | `minX = 100` |
| 横向右 | `(100,200,420,40)` | `(140,200,380,40)` | `maxX = 520` |
| 竖向上 | `(100,200,40,420)` | `(100,240,40,380)` | `maxY = 620` |
| 竖向下 | `(100,200,40,420)` | `(100,200,40,380)` | `minY = 200` |

这些差异已经由既有 `displayFrame` 实现；本功能只改变 `compact` 的来源。不要交换 `verticalTop` 和 `verticalBottom` 的偏移。屏幕边缘的约束允许显示矩形平移，但 `reference` 不跟着被约束值覆盖。

### 4. 必须覆盖的事件顺序

| 场景 | 操作顺序 | 最终结果 |
| --- | --- | --- |
| 自动阈值 | 透明度 79 → 80 → 79 | 比例 1 → 0 → 1，长轴 420 → 380 → 420 |
| 全透明显示 | 100% 自动 → 始终显示 | 背景仍全透明，图标出现，长轴 420 |
| 不透明隐藏 | 0% 自动 → 始终隐藏 | 背景仍不透明，图标消失，长轴 380 |
| 手动覆盖阈值 | 始终显示，透明度 0 → 100 | 始终比例 1、长轴 420 |
| 手动隐藏 | 始终隐藏，透明度 100 → 0 | 始终比例 0、长轴 380 |
| 回到自动 | 100% 始终显示 → 自动 | 收起；0% 始终隐藏 → 自动则展开 |
| 等效目标 | 79% 自动 → 始终显示 | 保存模式；已有完整尺寸保持，无多余动画 |
| 反向动画 | 收缩开始约 0.1 秒后改始终显示 | 从当前尺寸与比例展开，无跳到旧终态 |
| 拖动中切换 | 开始拖动 → 改隐藏 → 继续拖 → 松手 | 拖动中尺寸不变；松手保存正常拖动位置后收起 |
| 拖动中多次切换 | 拖动中隐藏 → 显示 → 隐藏 → 松手 | 只应用最后隐藏目标 |
| 隐藏 HUD 后切换 | 隐藏 HUD → 改模式 → 再显示 HUD | 设置时不主动显示；再次显示尺寸与模式一致 |
| 布局替换 | 手动模式下依次切四种布局 | 图标状态不重置，每种布局使用正确尺寸 |
| 会话展示模式替换 | 手动模式下无会话 → 有会话 → 无会话 | 标题按原逻辑变化，图标状态不重置 |
| 动画与布局同时改变 | 改模式后立即改布局 | 旧动画停止，新窗口仅呈现最终布局和模式 |
| 减少动态效果 | 系统减少动态效果已启用，切换模式 | 立即到终态，比例与矩形一致 |

普通模式或透明度变化不持久化位置。用户实际拖动时仍按原规则保存位置；不能为满足“不覆盖位置”而禁用正常拖动保存。

### 5. 测试文件、断言及执行方式

优先扩展现有测试文件，不新建与功能无关的测试框架。测试期望值应来自本文行为表或明确数值，不能只拿新生产函数的输出与自身比较。

1. `Tests/TraceflowCoreTests/HUDPreferencesTests.swift`：验证三个原始值往返、缺失回退、错误字符串／数字／布尔值回退；使用独立 `UserDefaults` suite 并清理，禁止污染用户真实设置。
2. `Tests/TraceflowCoreTests/HUDBackgroundAppearanceTests.swift`：三模式 × 五个透明度 × 四布局，断言实际尺寸及上述固定边；断言同透明度下三模式背景计算相同；保留旧自动阈值和中断动画测试。
3. `Tests/TraceflowCoreTests/HUDGeometryStateTests.swift`：重复模式切换时参考矩形不变；模式在拖动中更新后目标仍为 `nil`；正常结束拖动后用最新模式生成正确矩形；屏幕边缘展开收起不积累漂移。
4. `Tests/TraceflowAppTests/HUDLayoutControllerTests.swift`：扩展启动模式、控制器订阅、隐藏后显示、窗口替换及同窗口动画行为。复用 `SessionIntegrationFixture`、`contentParts` 和旧窗口退休检查；不为测试将控制器私有字段公开。

应用层测试等待方式：模型赋值后，涉及排队窗口替换的断言先让主队列执行；需要完成动画时沿用现有约 300 毫秒等待。不能赋值后立刻断言比例已到 0 或 1，因为这与平滑动画要求冲突。反向动画测试在约 100 毫秒时触发第二次变化，最终等待第二次过渡完成。精确插值用现有纯 `HUDSizeTransition` 测试验证，避免用真实定时器断言某一毫秒必须等于 0.5。

需要屏幕的测试沿用 `NSApplication.shared` 和现有无屏幕跳过规则。实屏残影需捕获最终合成画面或人工确认；仅检查 `NSHostingView` 尺寸正确不能证明没有残影。

实现完成后从仓库根目录按顺序执行：

```sh
swift test --filter HUDPreferencesTests
swift test --filter HUDBackgroundAppearanceTests
swift test --filter HUDGeometryStateTests
swift test --filter HUDLayoutControllerTests
swift build
git diff --check
```

失败先修复并重跑相关检查，不增加大范围无关测试。记录通过、失败、跳过和实屏未验证项；每阶段运行对应验证。

### 6. 调用点审计，避免漏改

实现后运行：

```sh
rg -n 'HUDBackgroundAppearance|HUDGeometryState|hudIconFraction|compact|iconHiddenThreshold' Sources
```

逐项核查，不能全局盲目替换：

- 所有读取 `.compact`、`.size(...)`、`.displayFrame(...)` 的应用运行路径必须包含最新模式，优先用 `geometry.appearance` 或模型初始化的完整外观。
- 单参数外观构造若仅用于背景透明度、材质、默认透明度或归一化，可保留。
- 静态 `referenceFrame` 不需要模式，因为它由当前实际矩形和布局恢复完整参考尺寸。
- 测试中旧单参数构造仍测试自动模式，不能把所有旧测试改为手动模式来绕过回归。
- 模式切换不得新增第二个定时器、第二个图标比例字段、第二个位置缓存或第二套窗口替换策略。

### 7. 执行暂停点与交付标准

本文已经批准。按“实施顺序”五阶段连续推进，不逐文件等待确认；中间阶段尚未接好完整行为时不得宣称功能已完成。

每阶段实现后补充相关测试并运行验证，验证通过后提交 Git，再继续下一阶段；不自动打包安装或发布。提交信息遵守英文 type/scope、简体中文 description；PRD 路径放提交正文中单独一行，避免英文路径混入中文 description。

最终完成需要同时满足：

- 六项主要源文件任务已接通；三模式、四布局符合行为表。
- 控件仅在设置页出现，选择持久化且启动无错误初始状态。
- 图标比例、内容长度、窗口尺寸在动画结束时一致。
- 手动模式在透明度变化及两种窗口替换路径下持续有效。
- 相关自动测试与构建通过；实屏检查结果单独报告。
- 无额外业务逻辑、菜单改动或位置格式迁移。

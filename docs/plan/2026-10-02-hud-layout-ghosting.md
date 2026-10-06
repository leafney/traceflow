# 透明浮窗布局切换残影修复方案

> 已证伪并被取代：本方案的强制重绘实现已在最新版安装包的真实屏幕上确认仍会产生持续残影。后续不得继续以本方案作为实现依据。请改用 `docs/plan/2026-10-03-hud-layout-content-reset.md`。

Related discussion: [docs/discuss/2026-10-02-hud-layout-ghosting.md](../discuss/2026-10-02-hud-layout-ghosting.md)

状态：已批准，编码、自动验证与发布包构建完成；实屏残影与动画观感待验收。本轮未安装或部署。

## 问题与证据边界

用户在无会话时，将同一浮窗从横向左切到横向右：新布局已经出现，旧布局的三个灯和默认名称仍以阴影形态存在。两套文字跟随整个浮窗移动；会话轮播时，底层旧文字固定，上层当前标题切换。

已确认安装包与当前dist一致，只有一个应用进程。隔离原生图层诊断中，左右切换会移动现有文字和灯图层，未观察到两套同时保留的图层。当前重点调查透明窗口绘制失效与屏幕合成刷新；尚不能宣称具体缓存缺陷已确诊。

先前验证遗漏了同一窗口连续切换布局。重新绘制后的cacheDisplay结果也不能证明重绘前屏幕没有旧像素。

## 目标与用户故事

1. 用户切换左右或上下布局后，只能看到新布局的三个灯和一个标题。
2. 用户横竖切换后，旧方向的文字、灯、轮廓均不残留。
3. 用户快速连续切换时，最终画面与最后选择的布局一致。
4. 用户查看多个会话时，原有标题滑入、滑出和淡入淡出继续工作。
5. 用户切换布局后，浮窗位置、固定状态、背景透明度和会话状态继续遵循已有规则。
6. 用户无需通过降低透明度、重启或反复安装暂时隐藏问题。

## 范围与文件

| 文件 | 计划工作 |
| --- | --- |
| Sources/TraceflowApp/HUDPanel.swift | 布局切换完成后的内容区绘制失效、异步刷新合并；必要时替换内容承载 |
| Tests/TraceflowAppTests/HUDLayoutControllerTests.swift | 同一生产窗口连续布局切换、快速切换、已有交互规则回归 |
| Tests/TraceflowAppTests/HUDTitleRenderingTests.swift | 与布局切换组合的会话动画和标题残留验证，保留现有内容测试 |
| docs/plan/2026-10-02-hud-layout-ghosting.md | 记录实际失败证据、选用方案、验证与构建结果 |

首选实现不修改HUDView标题来源、灯效算法和轮播调度器。不增加第三方依赖。

## 首选方案：布局事件触发完整内容区重绘

### 触发范围

只在HUDPanelController接受一个有效的新布局时执行。沿用现有检查：新布局等于模型最新选择，且不同于控制器当前布局。重复选择与过期异步回调直接忽略。

不在每次Hook、每次会话改名、每次轮播、每个灯动画帧或窗口拖动帧触发全内容区重绘。

### 执行顺序

1. 保存切换前承载视图和容器的bounds，记为旧内容区。
2. 沿用现有取消拖动、停止尺寸动画、取消旧位置重试的处理；不新增持久化写入。
3. 更新控制器布局和hudIconFraction，按现有restorePosition逻辑恢复新布局位置与窗口尺寸。
4. 对新的承载和容器请求布局，让布局树处理模型的最新方向；不能在Published发出新值、属性尚未更新时强制渲染旧布局。
5. 标记整个承载与容器需要重绘，不只标记新标题文字占据的矩形。横竖尺寸发生变化时，旧内容区与新内容区均须纳入失效处理；使用正确的视图局部坐标，裁剪到各视图有效bounds，不能把屏幕坐标当作视图坐标。
6. 当前主线程调用完成后，在下一轮主线程调度中再处理一次布局完成后的失效与displayIfNeeded，覆盖SwiftUI更新比原生尺寸更新稍晚的情况。这是一次性收尾，不是常驻刷新计时器。
7. 收尾闭包检查版本和最新布局，只允许最新切换收尾；已有窗口隐藏时仅保留正常失效标记，不强制显示窗口。
8. 按现有规则启动必要的位置重试。绘制修复不得改变恢复位置的算法。

实现可提取私有方法，例如requestLayoutRedraw。名称可调整，但必须由switchLayout调用，不能塞入通用setDisplayFrame使尺寸动画每帧触发。

### 异步更新约束

- 增加控制器内部单调递增的布局刷新版本或可取消的DispatchWorkItem，以合并快速切换产生的收尾。
- 闭包弱引用控制器，不阻止窗口释放。
- 横左→横右→竖上快速发生时，旧横右收尾不能重设根视图、窗口尺寸或布局。
- 刷新辅助方法只处理绘制；不要重新播放标题过渡、改变shouldAnimateDisplayChange或重置轮播计时。
- hide与后续布局切换应取消未执行的收尾，或使其版本失效。

### 禁止操作

- 不通过设置opaque、不透明背景色、降低背景透明度或隐藏旧文字覆盖块来修复。
- 不直接访问、删除或改写SwiftUI私有CGDrawingLayer和CABackdropLayer。
- 不无限调用needsDisplay/display，不新增30Hz或60Hz的全窗口刷新。
- 不在无证据时修改背景材质blendingMode或重做窗口合成结构。
- 不取消标题动画，不加随机UUID强迫每次模型更新重建视图。

## 条件备选：仅在布局切换时替换内容承载

启用条件：首选重绘实现后，正常屏幕上仍能复现旧灯或旧文字；记录切换方向、设置、时间和失败画面后才启用。本机没有录屏权限属于缺少证据，不等同于首选方案失败。

### 实现步骤

1. 将控制器hostingView属性由let改为var，使其始终指向唯一当前承载。
2. 提取承载创建方法，初始化和布局切换共用；继续使用同一个AppModel，不创建新模型或监听服务。
3. 在有效布局更新和位置尺寸恢复后创建新NSHostingView，frame与容器bounds一致，autoresizingMask保持width/height。
4. 移除旧承载，再将新承载加入原容器、置于原背景之上，并更新hostingView引用。操作在主线程一次完成，不跨await让两套承载同时停留。
5. 不替换NSPanel、HUDDragView容器或HUDBackgroundView，不复制和保留旧承载截图作为过渡层。
6. 按首选方案对内容区执行一次性失效处理，使旧像素清除与新内容绘制都得到通知。
7. 确认旧承载从superview移除；没有额外强引用导致其继续运行，不手动删除其私有子层。

### 行为限制

- 重建仅属于布局切换路径；会话A→B、同会话编辑和灯动画均不重建。
- 布局切换发生在会话过渡中时，旧布局的过渡随旧承载移除，当前会话在新布局正常显示；后续会话过渡继续使用原方向和时长。
- 切换后灯的时间采样继续沿用原系统时钟，不重置会话状态。
- 隐藏窗口切换布局不弹出窗口，不改变固定和鼠标穿透状态。
- 使用原有几何、拖动回调和位置存储，不每次切换创建新窗口。

## 标题绘制路径的后续处理

默认文字与会话文字使用不同原生层级是诊断观察，不是已确认根因。本轮不预先加入标题容器一致化补丁。

只有整个布局残影消除后，默认→会话仍能在不切布局的情况下独立复现默认文字残留，才单独调查标题承载与原生清除。届时补充证据及实现范围，不把三个候选补丁一次全加进去。

## 测试和实际验收

### 核心用例

所有切换用例必须复用同一个HUDPanelController和NSPanel，不能为每种布局另建窗口来代替切换。

| 场景 | 预期 |
| --- | --- |
| 无会话，横左→横右→横左 | 每次只有当前方向的一组三个灯和一个默认标题，旧位置没有字形或圆形残留 |
| 无会话，竖上→竖下→竖上 | 同上，旧纵向图案消失 |
| 横左→竖下→横右→竖上 | 尺寸正确，旧方向的灯、标题及轮廓不残留 |
| 快速连续切换20次 | 最后选择生效，不持续增加承载或重复绘制内容 |
| 有会话时切换布局 | 当前标题来源正确，不恢复旧默认名称 |
| 切换布局后A→B→C | 原标题插入、退出动画仍存在，过渡结束只有当前标题 |
| 动画中切布局，随后继续轮播 | 新布局正确，后续动画正常，无旧方向残留 |
| 隐藏状态切布局后再显示 | 不提前显示，显示时只有新布局 |
| 固定、拖动和显示器位置恢复 | 已有位置存储、取消拖动、固定及穿透规则不回退 |

先使用用户实际参数：白色标题、86%透明度。再覆盖10%、79%、80%、100%透明度及黑白标题、无文字浅深背景。79%与80%用于验证图标折叠边界。

### 三种证据分别记录

1. 业务与几何：模型、布局、尺寸、位置、会话选择正确。
2. 原生视图和图层：内容层级不重复，移除流程正确，辅助绘制结果一致。
3. 真实屏幕：普通显示过程没有旧图案，标题动画中间帧可见。

必须先获取正常屏幕观察，再调用cacheDisplay等会主动绘制的工具。不能用cacheDisplay清理待观察状态后宣称没有缺陷。测试代码不允许自行额外重建受测承载使测试通过；若启用备选，重建只能来自生产switchLayout。

没有录屏权限时明确跳过截图，保留人工验收项，不绕过权限，不把原生层级验证标成屏幕通过。截图或人工观察关注切换后0.30秒和1秒仍有无残留；动画另采中间帧，不能只比最终PNG证明动画存在。

### 自动验证命令

```sh
swift test --filter HUDLayoutControllerTests
swift test --filter HUDTitleRenderingTests
swift test --filter HUDTitleTransitionTests
swift test
swift build
git diff --check
./scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 dist/Traceflow.app
```

跳过TDD；针对快速布局切换、隐藏窗口和轮播组合的复杂状态转换补回归，不为单纯needsDisplay赋值编写镜像测试。

## 实施阶段和完成标准

### 阶段一：建立正确复现与首选实现

补充同一窗口无会话布局切换的检查，实现一次性内容区重绘及过期收尾丢弃。定向验证、构建和差异检查通过后提交。

记录用户旧版本复现、隔离测试能否复现以及首选实现的实际画面。未复现不能记为确定根因。

### 阶段二：必要的备选与组合回归

首选在实际画面失败才启用承载替换；否则保持最小修复。验证快速切换、横竖互换、透明度边界、会话轮播及拖动位置。全量通过后提交。

若缺少屏幕证据，继续完成独立的自动验证，但首选结果标为待验收，不自动加备选、不擅自宣布彻底修复。

### 阶段三：发布包与验收记录

重新构建并签名dist应用包，记录源码提交和各类验证结果，提交文档。安装与部署不属于本PRD授权范围。

用户批准后，沿用每阶段验证、提交后立即继续的执行规则；遇到需要新的业务决定或无法解决的错误才中断。提交格式使用type(scope):简体中文描述，关联PRD路径放提交正文。

最终完成结论必须区分“编码与自动验证完成”和“真实屏幕验收完成”。未观察实际屏幕就不能将后者标为完成。

## 执行模型编码细则

本节将前面的方案落实为具体操作。实现前必须完整阅读本文和关联调查，不可只复制代码。用户已批准，按本文连续实施并分阶段验证提交。

### A. 工作区和证据核对

1. 在仓库根目录执行git status --short和git diff，确认没有其他人的未提交代码需要保留。
2. 此方案创建时生产代码未修改，临时HUDDiagnosticTests已删除。若执行时再次发现临时试验，先检查来源，不全仓库reset，也不删除未知改动。
3. 记录当前基线提交。用户截图证明旧布局残影存在，不能因为离屏绘制正常否认用户复现。
4. 先建立隔离配置的同窗口复现，再改变生产逻辑；不发送事件到用户真实Socket，不修改标准UserDefaults。
5. 原图中的Traceflow可能是旧默认画面。禁止删除所有包含Traceflow的文字，合法会话标题允许使用该名称。

### B. 需要增加的控制器状态

首选方案保持hostingView为let。在HUDPanelController增加两个私有字段：

```swift
private var layoutRedrawGeneration: UInt64 = 0
private var layoutRedrawWork: DispatchWorkItem?
```

含义：generation表示最新有效刷新版本；work是最多一个待执行的收尾。它们不是轮播状态，不写UserDefaults，不加入AppModel。

取消函数的确定行为：

```swift
private func cancelLayoutRedraw() {
    layoutRedrawGeneration &+= 1
    layoutRedrawWork?.cancel()
    layoutRedrawWork = nil
}
```

DispatchWorkItem.cancel本身不能保证已开始的代码停止，因此仍须检查generation，不能省略版本校验。

### C. switchLayout的具体修改位置

保留函数最前面的现有guard，不能在guard前取消最新有效任务。

接受有效切换后，按下列位置插入操作：

```text
guard确认是最新且不同的布局
获取window.contentView；无容器时不尝试绘制
cancelLayoutRedraw，记录该次generation
保存hostingView.bounds和container.bounds
尺寸改变前对旧完整bounds标记needsDisplay
原cancelInteraction与positionRetry取消逻辑
原layout赋值、hudIconFraction赋值
原restorePosition
requestLayoutRedraw（传入布局、版本、旧bounds）
原isTemporaryPosition分支与位置重试
```

标记旧bounds应在restorePosition改变窗口尺寸之前完成；改变后再标记当前bounds，避免把旧范围错误裁掉。

现有layoutObserver使用DispatchQueue.main.async，让Published的新值先写入模型。保留这个机制，修正其“replacement root view”注释为实际布局与重绘行为；首选方案并未替换rootView。

setDisplayFrame保持原用途，不在其中调用requestLayoutRedraw。restorePosition也供显示器恢复、拖动取消等入口使用，不能把本次布局专用逻辑塞进去扩大刷新频率。

### D. 重绘辅助方法的参考结构

以下为首选方案的实现参考，需要用当前SDK编译验证。不是“屏幕一定修好”的证明。

```swift
private func invalidateLayoutContent(
    oldHostingBounds: NSRect,
    oldContainerBounds: NSRect
) {
    guard let container = window?.contentView else { return }
    container.needsLayout = true
    hostingView.needsLayout = true
    container.layoutSubtreeIfNeeded()

    let hostDirty = oldHostingBounds.union(hostingView.bounds)
        .intersection(hostingView.bounds)
    let containerDirty = oldContainerBounds.union(container.bounds)
        .intersection(container.bounds)
    if !hostDirty.isEmpty {
        hostingView.setNeedsDisplay(hostDirty)
    }
    if !containerDirty.isEmpty {
        container.setNeedsDisplay(containerDirty)
    }
}

private func requestLayoutRedraw(
    expectedLayout: HUDLayoutMode,
    generation: UInt64,
    oldHostingBounds: NSRect,
    oldContainerBounds: NSRect
) {
    invalidateLayoutContent(
        oldHostingBounds: oldHostingBounds,
        oldContainerBounds: oldContainerBounds
    )

    let work = DispatchWorkItem { [weak self] in
        guard let self,
              self.layoutRedrawGeneration == generation,
              self.layout == expectedLayout,
              self.model?.hudLayoutMode == expectedLayout else { return }
        self.layoutRedrawWork = nil
        self.invalidateLayoutContent(
            oldHostingBounds: oldHostingBounds,
            oldContainerBounds: oldContainerBounds
        )
        guard let window = self.window, window.isVisible else { return }
        window.contentView?.displayIfNeeded()
    }
    layoutRedrawWork = work
    DispatchQueue.main.async(execute: work)
}
```

调用前必须已经取消上一个work并取得当前generation。以上方法只使用公开AppKit API，不遍历和修改SwiftUI私有图层。

补充约束：

- 旧hosting bounds用于hosting本地坐标；旧container bounds用于container本地坐标，不能混用。
- 旧bounds在缩小后超出新bounds的部分，不能靠对新视图请求越界绘制清除；尺寸变更和原生窗口更新负责已不属于窗口的部分。不要虚构一个超出窗口的清理画布。
- 当前整个bounds的失效是有意的，因为旧灯和旧标题均受影响；不是只重画Text。
- 两次失效分别发生在布局切换完成时和一次异步收尾中；没有循环，没有sleep，没有新增Timer。
- 此处displayIfNeeded是拟议生产修复的一部分。验收时要观察应用自然运行该逻辑的结果，测试不得再额外调用显示方法“帮它清理”。
- 不把清理改为NSColor.clear的普通sourceOver填充：透明sourceOver不会擦掉旧像素。首选方案不自行绘制清屏色，交由正确失效与AppKit绘制处理。

### E. hide与快速切换时序

hide开头调用cancelLayoutRedraw，然后保留原orderOut、cancelInteraction、restorePosition行为。隐藏状态下接受布局切换可以更新几何与失效标记，但不能orderFront或激活应用。

必须理解以下场景：

| 时序 | 正确结果 |
| --- | --- |
| 右切换已排收尾，随后切竖上 | 右收尾因版本失效不执行，竖上收尾生效 |
| 右→左→右，最终又是右 | 最终右不能因与旧右同名而复用旧任务，必须比较generation |
| 排收尾后hide | 不显示窗口，不执行过期可见刷新 |
| 过期layoutObserver回调晚到 | guard拒绝，不取消当前有效收尾 |
| 同布局再次选择 | 不重建、不刷新、不改变位置存储 |

### F. 承载替换备选的参考结构

先写失败证据，再改hostingView为var。以下方法只在switchLayout的有效布局变化内、restorePosition之后调用：

```swift
private func replaceLayoutHostingView() {
    guard let model, let container = window?.contentView else { return }
    let replacement = NSHostingView(rootView: HUDView(model: model))
    replacement.frame = container.bounds
    replacement.autoresizingMask = [.width, .height]

    let previous = hostingView
    previous.removeFromSuperview()
    hostingView = replacement
    container.addSubview(replacement, positioned: .above, relativeTo: background)
}
```

正式实现应提取初始化与替换共用的承载工厂，避免新旧承载字体环境、尺寸掩码和配置分叉。保留window.contentView的HUDDragView以及它的拖动闭包，不重新调用整个makeGlassContent覆盖容器。

异步收尾访问self.hostingView，让它指向最新承载；不要在收尾闭包强捕获previous或replacement，使旧承载存活。首选重绘收尾仍受版本约束。

不实现“每次失败就重建一次”的自动探测逻辑；是否采用备选是实施时依据证据做出的确定选择，产品运行中不增加失败计数器或定时重建。

### G. 可重复的测试操作

使用SessionIntegrationFixture的隔离defaults、临时TRACEFLOW_HOME和真实Socket；无会话用例不调用hook。建立一个HUDPanelController，show一次，之后在该控制器上切换。

首要用例步骤：

1. 设置横向左、白色标题、previewTransparency(86)，建立并显示控制器；等待原生布局完成。
2. 确认无displayedSession、默认标题Traceflow、尺寸380×40。
3. 设置model.hudLayoutMode为横向右，通过现有observer进入生产switchLayout，不在测试中调用私有重绘函数。
4. 等待模型与窗口几何处理完成，在切换后约0.30秒及1秒观察新画面。
5. 横右只允许左侧当前默认名称及右侧三个灯，旧左侧圆形和旧中间标题不得存在。
6. 再切回横向左，用同一个窗口重复检查；记录控制器和窗口对象身份未变。

几何断言表：

| 透明度 | 横向尺寸 | 竖向尺寸 | 图标比例 |
| --- | --- | --- | --- |
| 10、79 | 420×40 | 40×420 | 1 |
| 80、86、100 | 380×40 | 40×380 | 0 |

快速切换用例分两种：同一主线程连续设置20次（验证排队更新只应用最新值）；每次让出主线程后继续切20次（验证实际承载重排不累积）。结束后只有一个NSHostingView直接承载HUD，不能要求内部SwiftUI子层数量固定。

会话动画用例：A通过userPromptSubmit处于运行状态，等待A稳定；B先建立并设置不同标题，然后permissionRequest触发红灯抢占A。断言displayedSession为B且shouldAnimateDisplayChange为true，再采样中间与结束画面。不能用同会话改名替代会话间动画检查。

核心动画契约保持横向新标题从下进入、旧标题向上退出；竖向新标题从左进入、旧标题向右退出；滑动0.20秒，减少动态效果opacity过渡0.15秒。合法标题Traceflow也应正常显示，不能用全局搜索该词判定失败。

### H. 屏幕截图的特殊注意

- 优先截指定隔离HUD窗口，或使用明确的受控背景与区域；只截测试内容，不采集无关桌面。
- 若使用屏幕矩形截图，多显示器包含负坐标，不能假定所有屏幕原点为零。NSWindow与截图坐标转换必须先核对主显示器坐标系，再核对截图尺寸和backingScaleFactor。
- 新旧布局的位置可能不同；对比时使用各自实际窗口位置，不把旧屏幕位置截图错认成新窗口残影。
- 原生层级里没有两套内容只算辅助证据，不能证明WindowServer缓存正确。
- 固定等待0.30秒用于动画结束观察；Socket事件仍用fixture.waitUntil等待特定事件被应用，避免读到上一事件。

### I. 失败决策与交付标准

| 结果 | 执行动作 |
| --- | --- |
| 首选实屏无残影，动画正常 | 保留首选，不加入承载替换 |
| 首选实屏仍有旧灯或文字 | 记录失败，启用备选，再按相同用例验证 |
| 无录屏权限且无人观察 | 自动验证可继续，屏幕项记待验收，不能按失败启用备选 |
| 备选实屏仍失败 | 停止堆补丁，记录重绘与合成证据，重新调查；不取消动画交付 |
| 残影消失但动画消失 | 修复不达标，定位动画受影响原因 |
| 只有同布局默认→会话仍失败 | 单列标题绘制问题，更新方案后处理，不混入布局成功结论 |

每阶段提交前检查：仅改授权文件、生产透明度和窗口激活行为未变、没有测试专用生产开关、没有遗留临时探针、没有修改用户真实配置。

最终记录至少包括：基线提交、实施方案、每阶段提交、自动测试总数与跳过项、无会话左右切换画面结果、横竖切换结果、会话动画观察结果、构建签名结果、安装是否执行。

### J. 交付检查清单

- [x] 同一窗口无会话左右切换已覆盖。
- [x] 旧bounds在尺寸变更前标记，当前完整bounds在变更后标记。
- [x] 下一轮刷新只有一次，版本可失效，闭包弱引用。
- [x] 过期回调、ABA切换、隐藏窗口均正确处理。
- [x] 重绘仅由布局变化触发，没有常驻全内容刷新。
- [x] 备选启用有首选失败证据，或明确未启用。
- [x] 灯效、位置存储、固定状态、背景与标题动画保持原规则。
- [x] 原生辅助验证与屏幕验收结果分开记录。
- [x] 定向、全量、构建、签名和差异检查结果明确。
- [x] 未执行未授权安装，没有将待验收项宣称完成。

## 逐项实施清单与完整接线示例

本节进一步消除实现歧义。出现表述差异时：业务与动画契约保持不变；接线顺序以本节为准；重绘效果仍必须验证，示例不代表已确诊系统缺陷。

### 1. 首选方案只做以下改动

1. 在HUDPanelController加入B节的两个私有字段。
2. 加入cancelLayoutRedraw、invalidateLayoutContent、requestLayoutRedraw三个私有方法。
3. 在switchLayout插入旧区域失效和新布局刷新请求。
4. 在hide开头取消刷新收尾。
5. 修正layoutObserver注释，保留其异步调度代码。
6. 补充同窗口回归与验证记录。

不要同时修改HUDView、HUDBackgroundView、AppModel、CarouselScheduler或StatusLightFrame。不要预先将hostingView改为var，首选方案不需要它可变。

### 2. switchLayout完整接线参考

以下展示新增操作与原业务代码的准确关系；辅助方法使用前文定义。

```swift
func switchLayout(to newLayout: HUDLayoutMode) {
    guard newLayout == model?.hudLayoutMode, newLayout != layout else { return }

    cancelLayoutRedraw()
    let generation = layoutRedrawGeneration
    let oldHostingBounds = hostingView.bounds
    let oldContainerBounds = window?.contentView?.bounds ?? .zero
    hostingView.setNeedsDisplay(oldHostingBounds)
    window?.contentView?.setNeedsDisplay(oldContainerBounds)

    // Preserve the existing interaction and position logic.
    cancelInteraction()
    positionRetry?.cancel()
    positionRetry = nil
    positionRetryDeadline = nil
    layout = newLayout
    model?.hudIconFraction = HUDBackgroundAppearance(transparency).compact ? 0 : 1
    restorePosition()

    requestLayoutRedraw(
        expectedLayout: newLayout,
        generation: generation,
        oldHostingBounds: oldHostingBounds,
        oldContainerBounds: oldContainerBounds
    )

    if isTemporaryPosition {
        positionRetryDeadline = Date().addingTimeInterval(HUDPositionRetryPolicy.duration)
        schedulePositionRetry()
    }
}

func hide() {
    cancelLayoutRedraw()
    window?.orderOut(nil)
    cancelInteraction()
    restorePosition()
}
```

这里container不存在时使用零bounds、跳过原生绘制，但原来的布局与交互处理仍执行。不要新增“没有contentView便return”使原业务逻辑被意外跳过。requestLayoutRedraw可以在没有contentView时直接跳过绘制和排队。

requestLayoutRedraw入口再检查generation、控制器layout、模型hudLayoutMode和contentView是否仍有效。这个检查可以防止以后增加其他调用入口时误刷新；不改变当前调用顺序。

### 3. 主线程与闭包生命周期

HUDPanelController是@MainActor类。所有NSView、NSWindow和模型访问必须在主线程完成。

如果当前编译器要求DispatchWorkItem闭包显式进入主Actor，将D节的work闭包改为如下包裹方式，闭包内部仍使用原来的版本检查与绘制代码：

```swift
let work = DispatchWorkItem { [weak self] in
    MainActor.assumeIsolated {
        guard let self,
              self.layoutRedrawGeneration == generation,
              self.layout == expectedLayout,
              self.model?.hudLayoutMode == expectedLayout else { return }
        // Execute the existing final invalidation and visible display here.
    }
}
DispatchQueue.main.async(execute: work)
```

assumeIsolated只能用于已确定从main队列运行的闭包。禁止把work改为global队列后继续使用此包裹；禁止为消除编译报错把控制器改为非隔离类或把AppKit操作放入Task.detached。

work闭包不得捕获work本身，避免work引用自身；引用self必须weak。过期work不能设置layoutRedrawWork=nil，否则可能误清除新work的引用。只有通过generation检查的最新work可以清空字段。

### 4. 区分“重绘”和“恢复窗口位置”

- 重绘方法不调用restorePosition、savePosition、ensureVisible或show，不改变window.frame。
- 位置变化仍由原switchLayout和位置重试处理。若系统没有屏幕，沿用已有位置重试，不创建虚拟屏幕尺寸来使测试通过。
- 旧灯和旧文字残留在当前浮窗内部属于本次问题。若旧窗口屏幕位置在移动后还残留图案，需要额外记录WindowServer画面；不能调用重绘所有桌面窗口来清理。
- invalidateShadow只更新窗口投影，不能代替清除三个灯和文字；不把它当首选修复的核心。
- 在尺寸相同的横左→横右路径也必须请求内容失效，不能写成“只有窗口大小变化才刷新”。这正是用户的关键复现。

### 5. 测试必须走实际入口

新增测试沿用@MainActor和async throws。先创建NSApplication.shared，再创建SessionIntegrationFixture；defer cleanUp。夹具启动的是隔离监听，不操作用户真实服务。

无会话用例不发送Hook，fixture.model.autoEnableNewSessions无需改变。设置hudLayoutMode和hudTitleColor，调用previewTransparency(86)后再创建控制器。controller.show一次；defer hide。保存window和contentView的对象身份用于切换后确认。

在测试中只赋值model.hudLayoutMode，通过layoutObserver触发新流程。已有几何测试直接调用switchLayout可以保留，但不能仅用这些同步调用测试代替新入口回归。

横左与横右尺寸相同，不能用“尺寸已等于380×40”作为布局切换完成的唯一等待条件。让主线程处理排队回调，并保留0.30秒稳定画面观察；不要通过测试手动执行生产私有收尾。

生产代码不允许等待300毫秒，只有测试观测使用固定等待。固定等待不能替代Hook事件的完成等待。

同一个用例中若发现旧内容，先保存正常屏幕证据，再作cacheDisplay辅助对比。严禁先调用以下方法再宣称原画面无残影：测试主动display、强制rootView赋值、额外创建新hosting替换、重新show刷新窗口。

### 6. 备选方案与首选方案不能并列启用

启用备选时是在原switchLayout的restorePosition之后、requestLayoutRedraw之前插入replaceLayoutHostingView。其余版本取消、失效与位置重试保留。

不是添加用户设置让用户选择两套修复，不是增加运行时猜测算法。实现最终只有一种确定流程：首选重绘，或有失败证据后的“布局专用承载替换加重绘”。

以下改动仅在备选启用后执行：hostingView改var；提取共用hosting工厂；添加replaceLayoutHostingView。背景仍是原background对象，container仍是原HUDDragView，panel仍是原NonActivatingPanel。

替换后setDisplayFrame必须访问当前hostingView属性；禁止把旧承载另存为长期属性。layoutObserver与transparencyObserver不需要重复订阅，原来的控制器订阅继续使用。

### 7. 每阶段的验证和提交顺序

| 阶段 | 实现与验证 | 提交内容 |
| --- | --- | --- |
| 一 | 首选生产改动；布局、标题、过渡定向测试；swift build；diff检查 | 首选修复、首要回归、基线与证据记录 |
| 二 | 依据实屏结果决定是否备选；补快速切换、隐藏、轮播组合；swift test全量；diff检查 | 组合回归、必要备选、实际结果 |
| 三 | build-app脚本；签名校验；包完整性检查；最终代码范围核对 | 构建与验收记录；不强制把已忽略的dist纳入Git |

同一个测试失败修正后重跑对应测试；相关定向测试通过后再做一次全量验证。全量通过且代码未再变化，无需无理由重复全部测试。

建议提交描述：fix(hud): 修复浮窗布局切换后的内容刷新；test(hud): 覆盖连续布局切换与会话动画回归；docs(hud): 记录浮窗残影修复验证结果。description使用简体中文，PRD路径放提交正文。

### 8. 执行记录模板

实现者在本文末尾新增以下记录，缺失结果填写“待验收”或“未执行”，不能留空，也不能把人工尚未检查写成通过：

```text
基线提交：
用户原问题：无会话横左切横右，旧灯和默认文字残留
隔离环境基线是否复现：
采用方案：首选 / 有失败证据的备选
备选失败证据（未启用则写未启用）：
同一窗口左右切换：业务几何 / 原生辅助 / 真实屏幕分别记录
横竖切换：业务几何 / 原生辅助 / 真实屏幕分别记录
快速切换和隐藏窗口结果：
标题滑入滑出与减少动态效果实屏观察：
自动测试：执行数量、失败数量、跳过数量及原因
构建与签名校验：
每阶段Git提交：
安装：未执行 / 用户另行授权后执行
尚未完成的验收与实际限制：
```

以上细则已获用户批准。实际实施与验证结果见文末记录。

## 实施与验证记录

### 阶段一

- 基线提交：9279171。工作区只有本方案和讨论文档，无其他未提交生产代码。
- 基线验证：同一生产窗口横左→横右→横左，通过模型observer进入切换；原生几何正确，未观察到重复承载。屏幕项因录屏权限缺失跳过，未能确认基线实屏残留。
- 实现：只修改HUDPanel.swift，增加旧bounds/当前完整bounds失效及一次主队列收尾；版本校验与取消处理覆盖新切换和hide。承载仍为let，未修改标题动画、背景、灯效、轮播或位置算法。
- 阶段一定向测试14项：12项通过、2项屏幕测试跳过、0失败。swift build和git diff --check通过。
- 采用首选重绘方案。没有首选实屏失败证据，不启用承载替换。实际屏幕效果待验收。

### 阶段二（组合验证）

- 阶段一提交：56cfdb5。备选未启用：缺少首选方案实屏失败证据，不能把录屏权限缺失当成失败。
- 新增同一窗口跨方向测试，覆盖86/10/79/80/100%透明度、黑白标题与图标折叠边界，检查当前灯位置、窗口及承载身份和几何。
- 快速切换覆盖同线程排队20次、交错20次、右→左→右、同布局重复选择；固定与位置存储保持正确。
- hide在布局observer之后、收尾之前排队，检查取消刷新及隐藏布局变化不弹窗；重新显示时为新布局。
- 真实Socket事件触发A→B红灯抢占，在过渡中切布局，随后B→C继续命中动画决策；检查稳定标题与回默认。原生像素对比是辅助重绘检查，不是动画中间帧的屏幕验收。
- 组合定向验证15项：13通过、2项屏幕测试跳过、0失败。屏幕测试没有执行，窗口截图参考路径仍需有权限后验证；浅深受控背景和实际减少动态效果观感均待人工验收。

- 阶段二全量swift test：213项，211通过、2项录屏权限导致跳过、0失败。git diff --check通过。

### 阶段三与交付结果

- 阶段二提交：0d52794。阶段三只更新验证记录，应用包源码对应0d52794。
- ./scripts/build-app.sh成功，重新生成dist/Traceflow.app；Info.plist、codesign --verify --deep --strict校验通过，通知辅助程序可执行且图标非空。
- 签名后主程序SHA-256：351b8d6041a8f97419e4f2324e00d3fe88c88388047795c254103e14d50e4dde。
- 最终生产差异仅HUDPanel.swift的布局事件重绘与取消逻辑；未修改标题动画、灯效、背景材质、模型和调度器。
- 安装未执行，未替换或重启当前应用；构建包已更新，当前运行应用不会因编译自动获得修复。
- 同窗口左右/横竖切换：业务几何与原生辅助验证通过；真实屏幕待验收。快速切换、固定、位置存储、隐藏和会话组合检查通过。
- 原标题动画实现与核心过渡规则保留，动画决策断言通过；实际滑入滑出和系统减少动态效果观感待验收。
- 全量213项，211通过、2跳过、0失败；两个跳过项均缺少屏幕录制权限。git diff --check通过，工作区无临时探针。
- 备选未启用。没有首选实屏失败证据，也没有实屏通过证据，不能宣称截图残影已经彻底解决。
- 清单勾选代表编码与相应自动验证完成，实屏检查的限制以上述记录为准。

人工验收建议：使用最新包，在无会话、白色标题、86%透明度下左→右→左；再横竖互换，观察0.30秒和1秒后是否有旧灯与文字。随后验证多个会话切换的滑入滑出。未取得实际观察结果前，屏幕修复状态保持待验收。

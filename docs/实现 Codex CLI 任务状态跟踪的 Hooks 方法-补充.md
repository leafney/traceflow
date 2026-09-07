# Codex HUD (macOS) 项目开发实现规划与技术设计说明书

根据您的最新要求，以下为您整理并细化了 **Codex HUD** 项目的完整开发设计文档（Markdown 格式）。文档中对各个模块的数据结构、核心算法以及平台交互的底层细节进行了代码级的深度细化。

---

## 1. 系统整体架构与数据流向

整个系统分为三个核心组件，生命周期和职责边界如下：

```
+--------------------------------------------------------------------------+
|                          macOS Host (Local PC)                           |
|                                                                          |
|  [Codex CLI / ChatGPT Client]                                            |
|              | (fork process, short-lived)                               |
|              v                                                           |
|    [hooks.json] -> [codex-hud-notify] (Swift CLI)                        |
|                           | (Unix Domain Socket write / JSON payload)    |
|                           v                                              |
|                    [hud.sock]                                            |
|                           |                                              |
|  [CodexHUD.app] (SwiftUI Swift App, Daemon-like)                         |
|        |                                                                 |
|        +--> [NWListener Server]                                          |
|        |          | (UDS Read / Parse payload / Append timestamp)        |
|        |          v                                                      |
|        +--> [SessionStateMachine] (Time-ordered State Jump Filter)       |
|        |          | (Active transition? Push to scheduler)               |
|        |          v                                                      |
|        +--> [CarouselScheduler] (Preemptive Stack + Fair Round-Robin)    |
|        |          | (Update selected session)                            |
|        |          v                                                      |
|        +--> [UI Panel (NSPanel)] (Dynamic Island-like SwiftUI Capsule)   |
+--------------------------------------------------------------------------+
```

---

## 2. 命令行转发器 `codex-hud-notify` 实现细节

转发器必须是超轻量、无状态的原生 Swift 命令行工具。其唯一职责是：读取标准输入 $\rightarrow$ 包装单调时间戳 $\rightarrow$ 写入 Unix 域套接字 $\rightarrow$ 退出。

### 2.1 核心数据结构与 IPC 协议
转发器在从 `stdin` 读取到 Codex 传入的 JSON 后，将其解析为通用 Dict，并在外层包裹高精度时间戳，构造为 `HUDEnvelope` 发送：

```swift
import Foundation

struct HUDEnvelope: Codable {
    let hudTimestamp: UInt64         // 纳秒级单调系统时间，用于防乱序
    let rawPayload: [String: AnyCodable] // Codex 原始 payload (包含 session_id, cwd, hook_event_name)
    
    enum CodingKeys: String, CodingKey {
        case hudTimestamp = "_hud_ts"
        case rawPayload = "raw_payload"
    }
}
```

### 2.2 转发器核心执行逻辑
```swift
import Foundation
import Network

@main
struct CodexHUDNotify {
    static func main() {
        // 1. 读取 stdin 的全部内容
        guard let stdinData = readStdin(), !stdinData.isEmpty else {
            exit(0)
        }
        
        // 2. 生成单调时间戳 (使用 System Uptime 纳秒数，不受系统时间同步影响)
        let timestamp = DispatchTime.now().uptimeNanoseconds
        
        // 3. 组装信封
        let socketPayload: [String: Any] = [
            "_hud_ts": timestamp,
            "raw_payload": try? JSONSerialization.jsonObject(with: stdinData) ?? [:]
        ]
        
        guard let serializedData = try? JSONSerialization.data(withJSONObject: socketPayload) else {
            exit(0)
        }
        
        // 4. 通过 Unix Domain Socket 写入后台，超时时间设为 1.5 秒，避免卡死 CLI
        let socketPath = "\(NSHomeDirectory())/Library/Application Support/CodexHUD/hud.sock"
        let connection = NWConnection(to: .unix(path: socketPath), using: .customLocalProtocol)
        
        let semaphore = DispatchSemaphore(value: 0)
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.send(content: serializedData, completion: .contentProcessed({ error in
                    connection.cancel()
                    semaphore.signal()
                }))
            } else if case .failed = state {
                semaphore.signal()
            }
        }
        
        connection.start(queue: .global())
        _ = semaphore.wait(timeout: .now() + 1.5)
        exit(0)
    }
    
    private static func readStdin() -> Data? {
        var data = Data()
        while let line = readLine(strippingNewline: false) {
            if let lineData = line.data(using: .utf8) {
                data.append(lineData)
            }
        }
        return data.isEmpty ? nil : data
    }
}
```

---

## 3. 状态机 `SessionStateMachine` 实现细节

主 App 在接收到 Socket 数据后，将其分发给各会话的独立状态机处理。

### 3.1 四态定义与数据结构
```swift
enum SessionColor: String, Codable {
    case red      // 🔴 请求授权、等待批准等需要人工干预的状态 (PermissionRequest)
    case yellow   // 🟡 正在执行任务，思维/Thinking 状态 (SessionStart, UserPromptSubmit)
    case green    // 🟢 任务已结束，等待查看 (Stop, SessionEnd)
    case gray     // ⚫ 熄灭/待机状态 (绿态维持超10分钟无交互自动转灰)
}

struct SessionState: Codable, Equatable {
    let sessionId: String
    let cwd: String
    var projectTitle: String       // 从 cwd 路径末端派生
    var currentColor: SessionColor
    var lastAppliedTimestamp: UInt64
    var enteredGreenAt: Date?      // 记录进入绿态的绝对挂钟时间，防睡眠失效
}
```

### 3.2 过滤与状态跳转逻辑
```swift
class SessionStateMachine {
    private(set) var state: SessionState
    
    init(initialState: SessionState) {
        self.state = initialState
    }
    
    /// 接收新事件，执行过滤与状态跳变，返回是否发生颜色跳变
    func apply(envelope: HUDEnvelope) -> Bool {
        // 1. 防乱序判定
        guard envelope.hudTimestamp > state.lastAppliedTimestamp else {
            return false // 丢弃过期事件
        }
        state.lastAppliedTimestamp = envelope.hudTimestamp
        
        let payload = envelope.rawPayload
        guard let eventName = payload["hook_event_name"] as? String else { return false }
        let oldColor = state.currentColor
        
        switch eventName {
        case "SessionStart":
            // 过滤：只有 startup/resume/clear 能够改变状态，忽略自动 compaction 触发
            if let source = payload["source"] as? String,
               ["startup", "resume", "clear"].contains(source) {
                transitTo(.yellow)
            }
            
        case "UserPromptSubmit":
            transitTo(.yellow)
            
        case "PermissionRequest":
            transitTo(.red)
            
        case "Stop", "SessionEnd":
            // 过滤：如果当前状态已经是 gray，说明已经沉寂，收尾事件不再亮起绿灯
            if state.currentColor != .gray {
                transitTo(.green)
            }
            
        default:
            break
        }
        
        return state.currentColor != oldColor
    }
    
    private func transitTo(_ color: SessionColor) {
        state.currentColor = color
        if color == .green {
            state.enteredGreenAt = Date()
        } else {
            state.enteredGreenAt = nil
        }
    }
    
    /// 绿转灰降级轮询检测（由后台每30秒触发一次）
    func checkGreenTimeout() -> Bool {
        guard state.currentColor == .green, let greenDate = state.enteredGreenAt else {
            return false
        }
        // 使用挂钟时间差，确保系统休眠唤醒后依然精确
        if Date().timeIntervalSince(greenDate) >= 600.0 { // 10分钟
            state.currentColor = .gray
            state.enteredGreenAt = nil
            return true // 发生跳变：绿色 -> 灰色（熄灭）
        }
        return false
    }
}
```

---

## 4. 轮播调度器 `CarouselScheduler` 核心算法

调度器管理两组数据结构：一个用于**跳变抢占**的插队栈（Preemptive Stack），一个用于**常规曝光**的优先级队列。

### 4.1 算法结构体设计
```swift
class CarouselScheduler: ObservableObject {
    @Published var currentlyDisplayedSession: SessionState?
    
    private var allSessions: [String: SessionStateMachine] = [:]
    private var preemptiveStack: [String] = [] // 存储由于颜色跳变而强制插队的 session_id
    private var lastDisplayedTimes: [String: Date] = [:] // 记录每个 session 上一次完全曝光结束的绝对时间
    
    private var displayTimer: Timer?
    private let timeSlice: TimeInterval = 5.0 // 默认曝光5秒
    
    func start() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: timeSlice, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    /// 当任意 Session 的状态发生跳变时，由外部调用此接口触发抢占
    func reportStateJump(sessionId: String) {
        guard let machine = allSessions[sessionId] else { return }
        
        // 灰色（不亮灯）不参与轮播
        if machine.state.currentColor == .gray {
            preemptiveStack.removeAll { $0 == sessionId }
            return
        }
        
        // 1. 将发生跳变的 session 推入插队栈（如果已在栈中则移至最前）
        preemptiveStack.removeAll { $0 == sessionId }
        preemptiveStack.append(sessionId)
        
        // 2. 抢占式调度：立刻中断当前 5 秒周期，切到最新跳变的任务
        triggerImmediatePreemption()
    }
    
    private func triggerImmediatePreemption() {
        displayTimer?.invalidate()
        tick() // 立即更新显示
        start() // 重新开始 5 秒计时器
    }
    
    /// 定时调度核心 tick 算法
    private func tick() {
        // 过滤灰色 session
        let activeSessions = allSessions.filter { $0.value.state.currentColor != .gray }
        
        if activeSessions.isEmpty {
            currentlyDisplayedSession = nil
            return
        }
        
        // 边界：当只有一个活跃 session 时，跳过不必要的重复切换逻辑
        if activeSessions.count == 1, let first = activeSessions.values.first {
            currentlyDisplayedSession = first.state
            return
        }
        
        // 1. 优先从抢占栈中弹出待展示的任务（先进先出/栈顶展示）
        while !preemptiveStack.isEmpty {
            let nextId = preemptiveStack.removeFirst()
            if let machine = allSessions[nextId], machine.state.currentColor != .gray {
                displaySession(machine.state)
                return
            }
        }
        
        // 2. 抢占栈为空，退回到优先级常规轮播
        if let nextSession = findNextFairSession(from: activeSessions.values.map { $0.state }) {
            displaySession(nextSession)
        }
    }
    
    /// 优先级公平轮播过滤算法
    private func findNextFairSession(from sessions: [SessionState]) -> SessionState? {
        // 分组归类
        let reds = sessions.filter { $0.currentColor == .red }
        let yellows = sessions.filter { $0.currentColor == .yellow }
        let greens = sessions.filter { $0.currentColor == .green }
        
        // 组优先级：红 > 黄 > 绿
        let targetGroup: [SessionState]
        if !reds.isEmpty {
            targetGroup = reds
        } else if !yellows.isEmpty {
            targetGroup = yellows
        } else {
            targetGroup = greens
        }
        
        // 组内公平性轮转：选择最久未被曝光的会话 (lastDisplayedTime 最小的)
        return targetGroup.min { (a, b) -> Bool in
            let t1 = lastDisplayedTimes[a.sessionId] ?? Date.distantPast
            let t2 = lastDisplayedTimes[b.sessionId] ?? Date.distantPast
            return t1 < t2
        }
    }
    
    private func displaySession(_ session: SessionState) {
        currentlyDisplayedSession = session
        lastDisplayedTimes[session.sessionId] = Date() // 更新此 session 曝光的最近完成时间
    }
}
```

---

## 5. UI Panel 及 SwiftUI 视觉规范

### 5.1 胶囊视图（Capsule View）
胶囊状态展示界面需要具有灵动岛（Dynamic Island）的高级感，尺寸建议宽度 220px，高度 36px，圆角设为完全半圆。

```swift
struct HUDCapsuleView: View {
    let session: SessionState
    
    var body: some View {
        HStack(spacing: 12) {
            // 左侧：会话项目名称 (由 cwd 派生，稳定且不包含隐私敏感 prompt)
            Text(session.projectTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                
            Spacer()
            
            // 右侧：三色红绿灯状态点
            HStack(spacing: 6) {
                LightIndicator(color: .red, active: session.currentColor == .red)
                LightIndicator(color: .yellow, active: session.currentColor == .yellow)
                LightIndicator(color: .green, active: session.currentColor == .green)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 220, height: 36)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
                .background(VisualEffectView(material: .ultraThinMaterial, blendingMode: .withinWindow))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

struct LightIndicator: View {
    let color: SessionColor
    let active: Bool
    
    var systemColor: Color {
        switch color {
        case .red: return Color.red
        case .yellow: return Color.yellow
        case .green: return Color.green
        case .gray: return Color.clear
        }
    }
    
    var body: some View {
        Circle()
            .fill(active ? systemColor : Color.white.opacity(0.15)) // 激活时亮灯，未激活时呈现不亮状态
            .frame(width: 8, height: 8)
            .shadow(color: active ? systemColor.opacity(0.6) : Color.clear, radius: 4)
            // 🟡 任务中状态：使用呼吸动画进行动效区别
            .scaleEffect(active && color == .yellow ? 1.1 : 1.0)
            .animation(active && color == .yellow ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: active)
    }
}
```

### 5.2 窗口承载层 (`NSPanel` 实例化)
在 macOS App 入口类中，通过如下配置让 HUD 悬浮在所有窗口之上，但不会在任务管理器、Dock 栏或 Alt+Tab 切换中出现：

```swift
class HUDPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 36),
            styleMask: [.nonactivatingPanel, .hudWindow, .borderless, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .statusBar          // 悬浮置于最顶层
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.contentView = contentView
    }
}
```

---

## 6. 开发规范、注意事项与调试指南

### 6.1 开发安全与签名防拦截规范
* **Gatekeeper 防阻断**：所有编译交付的 `codex-hud-notify` 原生二进制必须走完全苹果证书的代码签名流程 (`codesign --force --sign "Developer ID Application" ...`)。否则，当被 Codex 以后台进程无头调起时，系统会在没有任何视觉阻断提示下将其静默屏蔽，导致 HUD 无法更新。
* **隐私落盘标准**：如果在未来规划持久化历史会话等功能，涉及在磁盘中落盘 `UserPromptSubmit` 中的 `prompt` 内容，必须在存储前过滤任何敏感密钥或 API token (例如通过正则表达式模糊匹配并遮蔽 `sk-[a-zA-Z0-9]{32,}`).

### 6.2 稳定性与唤醒兜底
* **唤醒对时**：Swift App 在启动后注册 `NSWorkspace.didWakeNotification` 广播。当操作系统自睡眠唤醒后，立即拉起一个全局挂钟对准，更新所有绿态会话的超时距离：
  ```swift
  NSWorkspace.shared.notificationCenter.addObserver(
      self, 
      selector: #selector(systemDidWake), 
      name: NSWorkspace.didWakeNotification, 
      object: nil
  )
  ```

### 6.3 统一可观测性：日志打印规范
为了提高开发联调效率，主 App 不得将 debug 日志输出到标准控制台，应统一将其定向追加写入到本地隐藏诊断日志文件中：
* **日志文件绝对路径**：`~/Library/Logs/CodexHUD/events.log`
* **格式范例**：`[2026-09-07 15:30:20.123] [session_1ef2a] YELLOW -> RED (Triggered by: PermissionRequest)`
* **调试指令**：
  在终端中执行以下命令可直接观察实时跳转状态：
  ```bash
  tail -f ~/Library/Logs/CodexHUD/events.log
  ```

---

## 7. 阶段化项目落地规划与时间排期

### 阶段 1：验证核心机制可行性 (PoC)
* **时间段**：第 1 ~ 3 天
* **核心内容**：编写全局 `hooks.json`，拦截 `SessionStart`、`Stop` 和 `PermissionRequest` 信号，编写极简 python socket mock 脚本，确认 `session_id`、`cwd` 等多终端并发数据的隔离状态完全符合预期。

### 阶段 2：开发状态机与调度算法核心 (Swift Core)
* **时间段**：第 4 ~ 8 天
* **核心内容**：不写任何 UI 代码，建立纯 Swift 代码的 `SessionStateMachine` 与 `CarouselScheduler` 控制组件。通过编写本设计说明书第 4 节、第 5 节描述的逻辑，搭建完善的单体测试用例，完全阻断可能出现的时间序列防乱序或抢占优先级算法缺陷。

### 阶段 3：打通本机进程间通信 (IPC Bridge)
* **时间段**：第 9 ~ 12 天
* **核心内容**：基于 Network 框架实现 `codex-hud-notify` 二进制和 `CodexHUD.app`。通过 Unix Socket 传递真实加密、带纳秒级时间戳的 JSON 数据包，验证在并发多开 terminal 及同时通过 ChatGPT client 执行任务的情况下，后台无丢包、无阻塞地刷新内存表结构。

### 阶段 4：图形界面、动效及交互兜底 (SwiftUI + Popover)
* **时间段**：第 13 ~ 17 天
* **核心内容**：编写 `NSPanel` 视图宿主和 `HUDCapsuleView` 界面。实现上滑切换视图效果和圆点呼吸状态。实现点击下拉展开 Popover 显示全部已知 session 的历史列表并提供手动干预置顶（手动插队）接口。

### 阶段 5：分发打包及代码签名公证 (Notarization)
* **时间段**：第 18 ~ 20 天
* **核心内容**：建立标准打包发布脚本，跑通 Apple 公证和代码签名流程。针对操作系统睡眠与唤醒机制进行压力测试，确保在多线程常驻情况下 CPU 和内存空载占用降至最低（常驻空载内存建议控制在 25MB 以内）。

*内容由 AI 生成仅供参考*
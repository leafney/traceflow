import AppKit
import Combine
import TraceflowCore

/// A single application-owned clock. Windows own revocable presentation tokens.
@MainActor
final class HUDMarqueeCoordinator {
    struct Frame {
        let generation: UInt64
        let sessionID: String?
        let contentRevision: UInt64
        let layout: HUDTitleTextLayout
        let offset: CGFloat
        let reduceMotion: Bool
    }
    let frames = PassthroughSubject<Frame, Never>()
    private(set) var state = HUDTitleMarqueeState()
    private(set) var generation: UInt64 = 0
    private(set) var contentRevision: UInt64 = 0
    private(set) var currentFrame: Frame?
    private var sessionID: String?
    private var title = "Traceflow"
    private var vertical = false
    private var style: HUDDisplayStyle = .standard
    private var visible = false
    private var validWindow = false
    private var layout: HUDTitleTextLayout?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var systemAsleep = false
    private var screenAsleep = false
    private(set) var reduceMotion: Bool
    private let clock: () -> Double
    private let automaticTicks: Bool
    var isTicking: Bool { timer != nil }

    init(clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }, automaticTicks: Bool = true,
         observeSystem: Bool = true) {
        self.clock = clock
        self.automaticTicks = automaticTicks
        reduceMotion = observeSystem && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if observeSystem {
            let center = NSWorkspace.shared.notificationCenter
            let events: [(Notification.Name, (HUDMarqueeCoordinator) -> Void)] = [
                (NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, { $0.setReduceMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }),
                (NSWorkspace.willSleepNotification, { $0.setSleeping(system: true) }),
                (NSWorkspace.didWakeNotification, { $0.setSleeping(system: false) }),
                (NSWorkspace.screensDidSleepNotification, { $0.setSleeping(screen: true) }),
                (NSWorkspace.screensDidWakeNotification, { $0.setSleeping(screen: false) })
            ]
            for (name, action) in events {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if let self { action(self) } }
                })
            }
        }
    }

    deinit {
        timer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func beginWindow(layout: HUDLayoutMode, style: HUDDisplayStyle, session: SessionSnapshot?) -> UInt64 {
        let now = clock()
        freeze(now: now)
        generation &+= 1
        validWindow = true
        visible = false
        vertical = !layout.isHorizontal
        self.style = style
        self.layout = nil
        sessionID = nil
        title = "Traceflow"
        update(session: session, generation: generation)
        return generation
    }

    func retire(generation: UInt64) {
        guard validWindow, generation == self.generation else { return }
        freeze(now: clock())
        visible = false
        validWindow = false
    }

    func setVisible(_ visible: Bool, generation: UInt64) {
        guard validWindow, generation == self.generation else { return }
        self.visible = visible
        reconcile(now: clock())
    }

    func update(session: SessionSnapshot?, generation: UInt64) {
        guard validWindow, generation == self.generation else { return }
        let nextID = session?.id
        let nextTitle = session?.sessionListTitle ?? "Traceflow"
        guard sessionID != nextID || title != nextTitle || layout == nil else { return }
        let now = clock()
        freeze(now: now) // Outgoing subscribers receive their exact final sample first.
        contentRevision &+= 1
        sessionID = nextID
        title = nextTitle
        if style == .medium {
            layout = HUDTitleTextLayout(title: title, vertical: vertical)
            if let id = sessionID, let layout {
                state.configure(id, title: title, textLength: Double(layout.length), now: now)
            }
        }
        reconcile(now: now)
    }

    func updateBackingScale(_ scale: CGFloat, generation: UInt64, sessionID: String?, title: String) {
        guard validWindow, generation == self.generation, sessionID == self.sessionID, title == self.title,
              style == .medium, layout?.backingScale != scale else { return }
        let now = clock()
        freeze(now: now)
        layout = HUDTitleTextLayout(title: title, vertical: vertical, backingScale: scale)
        if let id = sessionID, let layout { state.configure(id, title: title, textLength: Double(layout.length), now: now) }
        reconcile(now: now)
    }

    func synchronizeTitles(_ titles: [String: String]) {
        let now = clock()
        if let id = sessionID, titles[id] != title { freeze(now: now) }
        state.synchronizeTitles(titles, now: now)
        if state.activeSessionID == nil { stopTimer() }
        // A published session snapshot will configure the new title before activation.
    }

    func setReduceMotion(_ enabled: Bool) {
        guard reduceMotion != enabled else { return }
        let now = clock()
        freeze(now: now)
        reduceMotion = enabled
        reconcile(now: now)
    }

    func setSleeping(system: Bool? = nil, screen: Bool? = nil) {
        let now = clock()
        freeze(now: now)
        if let system { systemAsleep = system }
        if let screen { screenAsleep = screen }
        reconcile(now: now)
    }

    private func reconcile(now: Double) {
        if validWindow, visible, style == .medium, !reduceMotion, !systemAsleep, !screenAsleep,
           let id = sessionID, state.records[id]?.title == title, layout != nil {
            state.activate(id, now: now)
        } else {
            state.pauseActive(now: now)
        }
        emit(now: now)
        if automaticTicks, state.activeSessionID != nil, timer == nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.renderFrame() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else if state.activeSessionID == nil { stopTimer() }
    }

    private func freeze(now: Double) {
        state.pauseActive(now: now)
        if sessionID == nil || sessionID.flatMap({ state.records[$0]?.title }) == title { emit(now: now) }
        stopTimer()
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    func renderFrame() { emit(now: clock()) }

    private func emit(now: Double) {
        guard let layout else { currentFrame = nil; return }
        let offset = sessionID.map { state.sample($0, now: now).offset } ?? 0
        let frame = Frame(generation: generation, sessionID: sessionID, contentRevision: contentRevision, layout: layout,
                          offset: reduceMotion ? 0 : CGFloat(offset), reduceMotion: reduceMotion)
        currentFrame = frame
        frames.send(frame)
    }
}

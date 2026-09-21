import AppKit
import Combine
import Foundation
import SwiftUI
import TraceflowCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [SessionSnapshot] = []
    @Published private(set) var displayedSession: SessionSnapshot?
    @Published private(set) var hooksHealth = HooksHealth(state: .notInstalled, detail: "尚未安装 Traceflow Hooks")
    @Published var isHUDVisible: Bool { didSet { defaults.set(isHUDVisible, forKey: "hudVisible") } }
    @Published var displayDuration: Double { didSet { defaults.set(displayDuration, forKey: "displayDuration") } }
    @Published var glowStrength: Int { didSet { defaults.set(glowStrength, forKey: "glowStrength") } }

    private let defaults = UserDefaults.standard
    private let logger = RotatingLogger(directory: TraceflowPaths.logs())
    private let sessionStore = SessionStore(url: TraceflowPaths.sessions())
    private var machines: [String: SessionStateMachine] = [:]
    private var scheduler = CarouselScheduler()
    private var server: UnixSocketServer?
    private var nextRotationIndex = 0
    private var settingsController: NSWindowController?

    init() {
        defaults.register(defaults: ["hudVisible": true, "displayDuration": 5.0, "glowStrength": 1])
        isHUDVisible = defaults.bool(forKey: "hudVisible")
        displayDuration = [3.0, 5.0, 10.0].contains(defaults.double(forKey: "displayDuration")) ? defaults.double(forKey: "displayDuration") : 5
        glowStrength = min(2, max(0, defaults.integer(forKey: "glowStrength")))
        restoreSessions()
    }

    func startListening() {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let logger = self.logger
        let server = UnixSocketServer(path: TraceflowPaths.socket().path) { data in
            guard let envelope = try? decoder.decode(HookEnvelope.self, from: data) else { logger.log("error=invalid_envelope"); return }
            DispatchQueue.main.async { [weak self] in self?.apply(envelope) }
        }
        do { try server.start(); self.server = server; logger.log("socket=started"); refreshHooksHealth() }
        catch { logger.log("error=socket_start code=\(error)"); hooksHealth = HooksHealth(state: .error, detail: "本地通信启动失败") }
    }

    func stopListening() { server?.stop(); server = nil; logger.flush() }

    func tick(now: Date = Date()) {
        recheckCompletionTimeouts(now: now)
        if let decision = scheduler.advance(now: now, displayDuration: displayDuration) { updateDisplay(decision.sessionID) }
    }

    func recheckCompletionTimeouts(now: Date = Date()) {
        var changed = false
        for id in machines.keys {
            guard var machine = machines[id], machine.expireCompletion(now: now) else { continue }
            machines[id] = machine; changed = true
            _ = scheduler.reportStateChange(sessionID: id, newState: .idle, stateChanged: true, now: now)
        }
        if changed { refreshSessions() }
    }

    func openSettingsWindow() {
        if settingsController == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Traceflow 设置"
            window.contentView = NSHostingView(rootView: SettingsView(model: self))
            window.center()
            settingsController = NSWindowController(window: window)
        }
        settingsController?.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func setIncluded(_ included: Bool, sessionID: String) {
        guard var machine = machines[sessionID] else { return }
        machine.setIncludedInHUD(included)
        machines[sessionID] = machine
        refreshSessions(); persistSessions()
    }

    func deleteSession(_ sessionID: String) {
        machines.removeValue(forKey: sessionID)
        refreshSessions(); persistSessions()
    }

    func clearSessions() {
        machines.removeAll(); nextRotationIndex = 0
        refreshSessions(); persistSessions()
    }

    func clearLogs() { logger.clear() }

    func openLogsDirectory() {
        try? FileManager.default.createDirectory(at: TraceflowPaths.logs(), withIntermediateDirectories: true)
        NSWorkspace.shared.open(TraceflowPaths.logs())
    }

    func resetHUDPosition() { NotificationCenter.default.post(name: .traceflowResetHUDPosition, object: nil) }

    private func apply(_ envelope: HookEnvelope) {
        let id = envelope.payload.sessionID
        var machine = machines[id] ?? makeMachine(for: envelope)
        let result = machine.apply(envelope, now: Date())
        guard result.accepted else { logger.log("event=discarded reason=\(String(describing: result.rejection))"); return }
        machines[id] = machine
        refreshSessions()
        persistSessions()
        defaults.set(Date(), forKey: "lastHookEvent")
        refreshHooksHealth()
        if let decision = scheduler.reportStateChange(sessionID: id, newState: machine.snapshot.state, stateChanged: result.stateChanged, now: Date()) { updateDisplay(decision.sessionID) }
        else if displayedSession?.id == id { updateDisplay(id) }
        logger.log("event=\(envelope.payload.eventName.rawValue) state=\(result.oldState.rawValue)->\(result.newState.rawValue)")
    }

    private func makeMachine(for envelope: HookEnvelope) -> SessionStateMachine {
        defer { nextRotationIndex += 1 }
        let now = Date()
        let persisted = PersistedSession(sessionID: envelope.payload.sessionID, projectPath: envelope.payload.cwd, projectName: TitleBuilder.projectName(from: envelope.payload.cwd), discoveredAt: now, lastUpdatedAt: now, rotationIndex: nextRotationIndex)
        return SessionStateMachine(snapshot: SessionSnapshot(persisted: persisted))
    }

    private func refreshSessions() {
        sessions = machines.values.map(\.snapshot).sorted { $0.persisted.rotationIndex < $1.persisted.rotationIndex }
        if let decision = scheduler.updateSessions(sessions, now: Date()) { updateDisplay(decision.sessionID) }
        else if let id = scheduler.currentSessionID { updateDisplay(id) }
    }

    private func updateDisplay(_ id: String?) { displayedSession = id.flatMap { machines[$0]?.snapshot } }

    private func restoreSessions() {
        do {
            let restored = try sessionStore.load()
            for persisted in restored { machines[persisted.sessionID] = SessionStateMachine(snapshot: SessionSnapshot(persisted: persisted, state: .idle)); nextRotationIndex = max(nextRotationIndex, persisted.rotationIndex + 1) }
            refreshSessions()
        } catch { hooksHealth = HooksHealth(state: .error, detail: "会话记录损坏"); logger.log("error=session_store_read") }
    }

    private func persistSessions() {
        do { try sessionStore.save(sessions.map(\.persisted)) }
        catch { logger.log("error=session_store_write") }
    }

    private func refreshHooksHealth() {
        let notifierExists = FileManager.default.isExecutableFile(atPath: TraceflowPaths.installedNotifier().path)
        let configExists = FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json").path)
        if !notifierExists || !configExists { hooksHealth = HooksHealth(state: .notInstalled, detail: "尚未安装完整 Traceflow Hooks") }
        else if let last = defaults.object(forKey: "lastHookEvent") as? Date { hooksHealth = HooksHealth(state: .healthy, detail: "最近事件：\(last.formatted(date: .abbreviated, time: .shortened))") }
        else { hooksHealth = HooksHealth(state: .pendingVerification, detail: "请在 Codex 中执行 /hooks 并发送消息") }
    }
}

extension Notification.Name { static let traceflowResetHUDPosition = Notification.Name("TraceflowResetHUDPosition") }

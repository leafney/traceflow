import AppKit
import Combine
import Foundation
import SwiftUI
import TraceflowCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [SessionSnapshot] = []
    @Published private(set) var displayedSession: SessionSnapshot?
    @Published var isHUDVisible: Bool { didSet { defaults.set(isHUDVisible, forKey: "hudVisible") } }
    @Published var displayDuration: Double { didSet { defaults.set(displayDuration, forKey: "displayDuration") } }
    @Published var glowStrength: Int { didSet { defaults.set(glowStrength, forKey: "glowStrength") } }

    private let defaults = UserDefaults.standard
    private let logger = RotatingLogger(directory: TraceflowPaths.logs())
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
    }

    func startListening() {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let logger = self.logger
        let server = UnixSocketServer(path: TraceflowPaths.socket().path) { data in
            guard let envelope = try? decoder.decode(HookEnvelope.self, from: data) else { logger.log("error=invalid_envelope"); return }
            DispatchQueue.main.async { [weak self] in self?.apply(envelope) }
        }
        do { try server.start(); self.server = server; logger.log("socket=started") }
        catch { logger.log("error=socket_start code=\(error)") }
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

    private func apply(_ envelope: HookEnvelope) {
        let id = envelope.payload.sessionID
        var machine = machines[id] ?? makeMachine(for: envelope)
        let result = machine.apply(envelope, now: Date())
        guard result.accepted else { logger.log("event=discarded reason=\(String(describing: result.rejection))"); return }
        machines[id] = machine
        refreshSessions()
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
}

import AppKit
import Combine
import Foundation
import SwiftUI
import TraceflowCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [SessionSnapshot] = []
    @Published private(set) var sessionProjects: [SessionProjectGroup] = []
    @Published private(set) var expandedProjectKeys: Set<String> = []
    @Published private(set) var displayedSession: SessionSnapshot?
    @Published private(set) var hooksHealth = HooksHealth(state: .notInstalled, detail: "尚未安装 Traceflow Hooks")
    @Published var hooksActionMessage: String?
    @Published private(set) var isVerifyingHooks = false
    @Published private(set) var isSyncingSessions = false
    @Published var sessionSyncMessage: String?
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
    private var pendingHealthCheckID: String?

    init() {
        defaults.register(defaults: ["hudVisible": true, "displayDuration": 5.0, "glowStrength": 1])
        isHUDVisible = defaults.bool(forKey: "hudVisible")
        displayDuration = [3.0, 5.0, 10.0].contains(defaults.double(forKey: "displayDuration")) ? defaults.double(forKey: "displayDuration") : 5
        glowStrength = min(2, max(0, defaults.integer(forKey: "glowStrength")))
        expandedProjectKeys = Set(defaults.stringArray(forKey: "expandedProjectKeys") ?? [])
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 680), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
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

    func setProjectIncluded(_ included: Bool, projectKey: String) {
        let sessionIDs = sessionProjects.first(where: { $0.id == projectKey })?.sessions.map(\.id) ?? []
        guard !sessionIDs.isEmpty else { return }
        for sessionID in sessionIDs {
            guard var machine = machines[sessionID] else { continue }
            machine.setIncludedInHUD(included)
            machines[sessionID] = machine
        }
        refreshSessions()
        persistSessions()
    }

    func setProjectExpanded(_ expanded: Bool, projectKey: String) {
        if expanded { expandedProjectKeys.insert(projectKey) }
        else { expandedProjectKeys.remove(projectKey) }
        defaults.set(Array(expandedProjectKeys).sorted(), forKey: "expandedProjectKeys")
    }

    func deleteSession(_ sessionID: String) {
        machines.removeValue(forKey: sessionID)
        refreshSessions(); persistSessions()
    }

    func clearSessions() {
        machines.removeAll(); nextRotationIndex = 0; expandedProjectKeys.removeAll()
        defaults.removeObject(forKey: "expandedProjectKeys")
        refreshSessions(); persistSessions()
    }

    func clearLogs() { logger.clear() }

    func openLogsDirectory() {
        try? FileManager.default.createDirectory(at: TraceflowPaths.logs(), withIntermediateDirectories: true)
        NSWorkspace.shared.open(TraceflowPaths.logs())
    }

    func resetHUDPosition() { NotificationCenter.default.post(name: .traceflowResetHUDPosition, object: nil) }

    func installHooks() {
        do { try makeHooksInstaller().installOrRepair(); defaults.removeObject(forKey: "lastHookEvent"); hooksActionMessage = "安装完成。请在 Codex 中重新执行 /hooks 并信任新定义，然后点击“测试转发通道”。"; refreshHooksHealth() }
        catch { hooksHealth = HooksHealth(state: .error, detail: error.localizedDescription); hooksActionMessage = error.localizedDescription }
    }

    func removeHooks() {
        do { try makeHooksInstaller().remove(); defaults.removeObject(forKey: "lastHookEvent"); hooksActionMessage = "Traceflow Hooks 已移除。"; refreshHooksHealth() }
        catch { hooksHealth = HooksHealth(state: .error, detail: error.localizedDescription); hooksActionMessage = error.localizedDescription }
    }

    func verifyHooksConnection() {
        guard !isVerifyingHooks else { return }
        let installer = makeHooksInstaller()
        guard installer.isInstalled() else {
            hooksHealth = HooksHealth(state: .notInstalled, detail: "请先安装或修复 Traceflow Hooks")
            hooksActionMessage = "未找到完整且可执行的 Traceflow Hooks。"
            return
        }

        let checkID = "__traceflow_health_check__:\(UUID().uuidString)"
        pendingHealthCheckID = checkID
        isVerifyingHooks = true
        hooksActionMessage = "正在测试转发器、本地通信和应用接收链路……"
        let command = HooksInstaller.shellQuote(installer.installedNotifierURL.path)
        Task.detached { [weak self] in
            do {
                let payload = HookPayload(sessionID: checkID, eventName: .sessionStart, source: "traceflow-health-check")
                let data = try JSONEncoder().encode(payload)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", command]
                let input = Pipe()
                let output = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                try process.run()
                try input.fileHandleForWriting.write(contentsOf: data)
                try input.fileHandleForWriting.close()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    await self?.finishHealthCheckFailure(checkID: checkID, message: "转发器执行失败")
                }
            } catch {
                await self?.finishHealthCheckFailure(checkID: checkID, message: error.localizedDescription)
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.finishHealthCheckFailure(checkID: checkID, message: "5 秒内未收到测试事件")
        }
    }

    func syncCodexSessions() {
        guard !isSyncingSessions else { return }
        isSyncingSessions = true
        sessionSyncMessage = "正在从 Codex 读取会话摘要……"
        Task.detached { [weak self] in
            do {
                let threads = try CodexAppServerClient().listThreads()
                await self?.mergeCodexThreads(threads)
            } catch {
                await self?.finishSessionSyncFailure(error.localizedDescription)
            }
        }
    }

    private func apply(_ envelope: HookEnvelope) {
        let id = envelope.payload.sessionID
        if id.hasPrefix("__traceflow_health_check__:") {
            if id == pendingHealthCheckID, envelope.payload.source == "traceflow-health-check" {
                pendingHealthCheckID = nil
                isVerifyingHooks = false
                defaults.set(Date(), forKey: "lastHookEvent")
                refreshHooksHealth()
                hooksActionMessage = "转发通道正常。注意：Codex 是否信任仍以 /hooks 页面为准。"
                logger.log("hooks=health_check_success")
            }
            return
        }
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
        let persisted = HookSessionFactory.makePersistedSession(
            sessionID: envelope.payload.sessionID,
            cwd: envelope.payload.cwd,
            now: now,
            rotationIndex: nextRotationIndex
        )
        return SessionStateMachine(snapshot: SessionSnapshot(persisted: persisted))
    }

    private func refreshSessions() {
        sessions = machines.values.map(\.snapshot).sorted { $0.persisted.rotationIndex < $1.persisted.rotationIndex }
        sessionProjects = SessionProjectGrouper.groups(from: sessions)
        let validProjectKeys = Set(sessionProjects.map(\.id))
        let retainedExpandedKeys = expandedProjectKeys.intersection(validProjectKeys)
        if retainedExpandedKeys != expandedProjectKeys {
            expandedProjectKeys = retainedExpandedKeys
            defaults.set(Array(expandedProjectKeys).sorted(), forKey: "expandedProjectKeys")
        }
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

    private func mergeCodexThreads(_ threads: [CodexThreadSummary]) {
        let result = CodexThreadImporter.merge(
            threads,
            into: machines.values.map(\.snapshot.persisted),
            nextRotationIndex: nextRotationIndex
        )
        var mergedMachines: [String: SessionStateMachine] = [:]
        for persisted in result.sessions {
            if var machine = machines[persisted.sessionID] {
                machine.updatePersistedMetadata(persisted)
                mergedMachines[persisted.sessionID] = machine
            } else {
                mergedMachines[persisted.sessionID] = SessionStateMachine(
                    snapshot: SessionSnapshot(persisted: persisted, state: .idle)
                )
            }
        }
        machines = mergedMachines
        nextRotationIndex = result.nextRotationIndex
        refreshSessions()
        persistSessions()
        isSyncingSessions = false
        sessionSyncMessage = "同步完成：新增 \(result.addedCount) 个，更新 \(result.updatedCount) 个，共读取 \(threads.count) 个会话。新会话默认关闭，请展开项目并选择需要参与 HUD 的会话。"
        logger.log("sessions=sync_success count=\(threads.count) added=\(result.addedCount)")
    }

    private func finishSessionSyncFailure(_ message: String) {
        isSyncingSessions = false
        sessionSyncMessage = "同步失败：\(message)"
        logger.log("sessions=sync_failed")
    }

    private func finishHealthCheckFailure(checkID: String, message: String) {
        guard pendingHealthCheckID == checkID else { return }
        pendingHealthCheckID = nil
        isVerifyingHooks = false
        hooksHealth = HooksHealth(state: .error, detail: "转发通道测试失败")
        hooksActionMessage = "\(message)。请先修复 Hooks，再在 Codex 中执行 /hooks 并信任。"
        logger.log("hooks=health_check_failed")
    }

    private func refreshHooksHealth() {
        if !makeHooksInstaller().isInstalled() { hooksHealth = HooksHealth(state: .notInstalled, detail: "尚未安装完整 Traceflow Hooks") }
        else if let last = defaults.object(forKey: "lastHookEvent") as? Date { hooksHealth = HooksHealth(state: .healthy, detail: "最近事件：\(last.formatted(date: .abbreviated, time: .shortened))") }
        else { hooksHealth = HooksHealth(state: .pendingVerification, detail: "请在 /hooks 信任后测试转发通道") }
    }

    private func makeHooksInstaller() -> HooksInstaller {
        let hooksURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let bundled = executable.deletingLastPathComponent().appendingPathComponent("traceflow-notify")
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/release/traceflow-notify")
        return HooksInstaller(hooksURL: hooksURL, installedNotifierURL: TraceflowPaths.installedNotifier(), sourceNotifierURL: FileManager.default.fileExists(atPath: bundled.path) ? bundled : development)
    }
}

extension Notification.Name { static let traceflowResetHUDPosition = Notification.Name("TraceflowResetHUDPosition") }

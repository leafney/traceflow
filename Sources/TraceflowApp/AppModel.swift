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
    @Published private(set) var shouldAnimateDisplayChange = false
    @Published private(set) var hooksHealth = HooksHealth(state: .notInstalled, detail: "尚未安装 Traceflow Hooks")
    @Published private(set) var localCommunicationHealth = LocalCommunicationHealth(state: .error, detail: "尚未启动本地通信")
    @Published var hooksActionMessage: String?
    @Published private(set) var isVerifyingHooks = false
    @Published private(set) var isSyncingSessions = false
    @Published private(set) var sessionDataHealth: SessionDataHealth = .healthy
    @Published private(set) var isRebuildingSessions = false
    @Published var sessionSyncMessage: String?
    @Published var isHUDVisible: Bool { didSet { defaults.set(isHUDVisible, forKey: "hudVisible") } }
    @Published var displayDuration: Double {
        didSet {
            defaults.set(displayDuration, forKey: "displayDuration")
            scheduler.updateTimingConfiguration(CarouselTimingConfiguration(mode: timingMode, uniformDuration: displayDuration))
            logger.log(SessionEventLogFormatter.carouselSettings(mode: timingMode, uniformDuration: displayDuration))
        }
    }
    @Published var timingMode: CarouselTimingMode {
        didSet {
            defaults.set(timingMode.rawValue, forKey: "carouselTimingMode")
            scheduler.updateTimingConfiguration(CarouselTimingConfiguration(mode: timingMode, uniformDuration: displayDuration))
            logger.log(SessionEventLogFormatter.carouselSettings(mode: timingMode, uniformDuration: displayDuration))
        }
    }
    @Published var hudLayoutMode: HUDLayoutMode { didSet { hudPreferences.saveLayoutMode(hudLayoutMode) } }
    @Published var hudGlowMode: HUDGlowMode { didSet { hudPreferences.saveGlowMode(hudGlowMode) } }

    private let defaults: UserDefaults
    private let hudPreferences: HUDPreferences
    private let logger = RotatingLogger(directory: TraceflowPaths.logs())
    private let sessionStore = SessionStore(url: TraceflowPaths.sessions())
    private var machines: [String: SessionStateMachine] = [:]
    private var scheduler = CarouselScheduler()
    private var server: UnixSocketServer?
    private var nextRotationIndex = 0
    private var settingsController: NSWindowController?
    private var pendingHealthCheckID: String?

    init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        hudPreferences = HUDPreferences(defaults: defaults)
        defaults.register(defaults: ["hudVisible": true, "displayDuration": 5.0])
        isHUDVisible = defaults.bool(forKey: "hudVisible")
        displayDuration = [3.0, 5.0, 10.0].contains(defaults.double(forKey: "displayDuration")) ? defaults.double(forKey: "displayDuration") : 5
        timingMode = defaults.string(forKey: "carouselTimingMode").flatMap(CarouselTimingMode.init(rawValue:)) ?? .uniform
        hudLayoutMode = hudPreferences.loadLayoutMode()
        hudGlowMode = hudPreferences.loadGlowMode()
        scheduler.updateTimingConfiguration(CarouselTimingConfiguration(mode: timingMode, uniformDuration: displayDuration))
        expandedProjectKeys = Set(defaults.stringArray(forKey: "expandedProjectKeys") ?? [])
        restoreSessions()
    }

    func startListening() {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let logger = self.logger
        let server = UnixSocketServer(
            path: TraceflowPaths.socket().path,
            dropHandler: { drop in
                switch drop {
                case let .readError(bytes): logger.log(DiagnosticLogFormatter.socketDrop(reason: "read_error", bytes: bytes))
                case .emptyInput: logger.log(DiagnosticLogFormatter.socketDrop(reason: "empty_input", bytes: 0))
                case let .oversizeInput(bytes): logger.log(DiagnosticLogFormatter.socketDrop(reason: "oversize_input", bytes: bytes))
                }
            }
        ) { data in
            guard let envelope = try? decoder.decode(HookEnvelope.self, from: data) else {
                logger.log(DiagnosticLogFormatter.decodeFailed(bytes: data.count))
                return
            }
            logger.log(DiagnosticLogFormatter.event(stage: "app.received", envelope: envelope, receivedAt: Date()))
            DispatchQueue.main.async { [weak self] in self?.apply(envelope) }
        }
        do {
            try server.start()
            self.server = server
            localCommunicationHealth = LocalCommunicationHealth(state: .healthy, detail: "本地通信正常")
            logger.log("socket=started")
            refreshHooksHealth()
        } catch {
            logger.log("error=socket_start code=\(error)")
            localCommunicationHealth = LocalCommunicationHealth(state: .error, detail: "本地通信启动失败")
        }
    }

    func stopListening() { server?.stop(); server = nil; logger.flush() }

    func tick(now: Date = Date()) {
        recheckCompletionTimeouts(now: now)
        if let decision = scheduler.advance(now: now) { applyDisplayDecision(decision) }
    }

    func recheckCompletionTimeouts(now: Date = Date()) {
        var changed = false
        for id in machines.keys {
            guard var machine = machines[id], machine.expireCompletion(now: now) else { continue }
            machines[id] = machine
            changed = true
        }
        if changed {
            refreshSessions()
            persistSessions()
        }
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
        guard sessionDataHealth.allowsSaving else { return }
        guard var machine = machines[sessionID] else { return }
        machine.setIncludedInHUD(included)
        machines[sessionID] = machine
        refreshSessions(); persistSessions()
    }

    func setProjectIncluded(_ included: Bool, projectKey: String) {
        guard sessionDataHealth.allowsSaving else { return }
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
        guard sessionDataHealth.allowsSaving else { return }
        machines.removeValue(forKey: sessionID)
        refreshSessions(); persistSessions()
    }

    func clearSessions() {
        guard sessionDataHealth.allowsSaving else { return }
        machines.removeAll(); nextRotationIndex = 0; expandedProjectKeys.removeAll()
        defaults.removeObject(forKey: "expandedProjectKeys")
        refreshSessions(); persistSessions()
    }

    func clearLogs() { logger.clear() }

    func openLogsDirectory() {
        try? FileManager.default.createDirectory(at: TraceflowPaths.logs(), withIntermediateDirectories: true)
        NSWorkspace.shared.open(TraceflowPaths.logs())
    }

    func openSessionDataDirectory() {
        let directory = TraceflowPaths.sessions().deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func retrySessionSave() {
        do {
            try sessionStore.retrySave(sessions.map(\.persisted))
            sessionDataHealth = sessionStore.health
            sessionSyncMessage = "会话数据保存成功。"
        } catch {
            sessionDataHealth = sessionStore.health
            sessionSyncMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    func backupAndRebuildSessions() {
        guard !isRebuildingSessions else { return }
        isRebuildingSessions = true
        do {
            let backup = try sessionStore.backupAndRebuild()
            machines.removeAll()
            nextRotationIndex = 0
            expandedProjectKeys.removeAll()
            defaults.removeObject(forKey: "expandedProjectKeys")
            sessionDataHealth = sessionStore.health
            refreshSessions()
            sessionSyncMessage = "损坏数据已备份为 \(backup.lastPathComponent)，正在重新同步……"
            isRebuildingSessions = false
            syncCodexSessions()
        } catch {
            sessionDataHealth = sessionStore.health
            isRebuildingSessions = false
            sessionSyncMessage = "重建失败：\(error.localizedDescription)"
        }
    }

    func resetHUDPosition() { NotificationCenter.default.post(name: .traceflowResetHUDPosition, object: nil) }
    func logDiagnostic(_ message: String) { logger.log(message) }

    func installHooks() {
        do { try makeHooksInstaller().installOrRepair(); defaults.removeObject(forKey: "lastHookEvent"); hooksActionMessage = "安装完成。请在 Codex 中重新执行 /hooks 并信任新定义，然后点击“测试转发通道”。"; refreshHooksHealth() }
        catch {
            hooksActionMessage = error.localizedDescription
            refreshHooksHealth()
            if hooksHealth.state == .notInstalled { hooksHealth = HooksHealth(state: .error, detail: error.localizedDescription) }
        }
    }

    func removeHooks() {
        do { try makeHooksInstaller().remove(); defaults.removeObject(forKey: "lastHookEvent"); hooksActionMessage = "Traceflow Hooks 已移除。"; refreshHooksHealth() }
        catch {
            hooksActionMessage = error.localizedDescription
            refreshHooksHealth()
            if hooksHealth.state == .notInstalled { hooksHealth = HooksHealth(state: .error, detail: error.localizedDescription) }
        }
    }

    func verifyHooksConnection() {
        guard !isVerifyingHooks else { return }
        let installer = makeHooksInstaller()
        let inspection = installer.inspect()
        guard inspection.isComplete else {
            switch inspection.state {
            case .missing:
                hooksHealth = HooksHealth(state: .notInstalled, detail: inspection.summary)
            case .corrupted, .incomplete:
                hooksHealth = HooksHealth(state: .needsRepair, detail: inspection.summary)
            case .complete:
                break
            }
            hooksActionMessage = "Traceflow Hooks 缺失、损坏或定义不完整，请先安装或修复。"
            return
        }

        let checkID = "__traceflow_health_check__:\(UUID().uuidString)"
        pendingHealthCheckID = checkID
        isVerifyingHooks = true
        localCommunicationHealth = LocalCommunicationHealth(state: .testing, detail: "正在测试转发通道")
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
                process.standardInput = input
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                try input.fileHandleForWriting.write(contentsOf: data)
                try input.fileHandleForWriting.close()
                guard ProcessLifecycle.waitForExit(process, timeout: 5) else {
                    ProcessLifecycle.terminate(process)
                    await self?.finishHealthCheckFailure(checkID: checkID, message: "转发器执行超时")
                    return
                }
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
        guard !isSyncingSessions, sessionDataHealth.allowsSaving else { return }
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
                localCommunicationHealth = LocalCommunicationHealth(state: .healthy, detail: "转发通道正常")
                refreshHooksHealth()
                hooksActionMessage = "转发通道正常。注意：Codex 是否信任仍以 /hooks 页面为准。"
                logger.log("hooks=health_check_success")
                logger.log(DiagnosticLogFormatter.event(stage: "app.internal_handled", envelope: envelope, appliedAt: Date(), extras: [("reason", "health_check")]))
            } else {
                logger.log(DiagnosticLogFormatter.event(stage: "app.internal_ignored", envelope: envelope, appliedAt: Date(), extras: [("reason", "unmatched_health_check")]))
            }
            return
        }
        guard !SessionSourcePolicy.isInternalHookSource(envelope.payload.source) else {
            logger.log("event=discarded reason=internal_source")
            logger.log(DiagnosticLogFormatter.event(stage: "app.internal_ignored", envelope: envelope, appliedAt: Date(), extras: [("reason", "internal_source")]))
            return
        }
        var machine = machines[id] ?? makeMachine(for: envelope)
        let result = machine.apply(envelope, now: Date())
        let appliedAt = Date()
        guard result.accepted else {
            logger.log("event=discarded reason=\(String(describing: result.rejection))")
            logger.log(DiagnosticLogFormatter.event(stage: "app.rejected", envelope: envelope, appliedAt: appliedAt, extras: [("reason", String(describing: result.rejection))]))
            return
        }
        logger.log(DiagnosticLogFormatter.event(
            stage: "app.accepted",
            envelope: envelope,
            appliedAt: appliedAt,
            extras: [("old_state", result.oldState.rawValue), ("new_state", result.newState.rawValue), ("state_changed", String(result.stateChanged))]
        ))
        localCommunicationHealth = LocalCommunicationHealth(state: .healthy, detail: "最近成功收到 Hook 事件")
        machines[id] = machine
        let snapshot = machine.snapshot
        publishSessions()
        let membershipDecision = scheduler.updateSessions(sessions, now: Date(), updateExistingStates: false, processNewlyIncluded: false)
        let eventDecision = scheduler.reportStateChange(sessionID: id, newState: machine.snapshot.state, stateChanged: result.stateChanged, now: Date())
        persistSessions()
        defaults.set(Date(), forKey: "lastHookEvent")
        refreshHooksHealth()
        if let decision = eventDecision ?? membershipDecision { applyDisplayDecision(decision) }
        else if displayedSession?.id == id { updateDisplay(id) }
        logger.log(SessionEventLogFormatter.stateTransition(
            event: envelope.payload.eventName,
            oldState: result.oldState,
            newState: result.newState,
            projectName: snapshot.persisted.projectName ?? "",
            sessionID: snapshot.id,
            title: snapshot.displayTitle
        ))
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
        publishSessions()
        if let decision = scheduler.updateSessions(sessions, now: Date()) { applyDisplayDecision(decision) }
        else if let id = scheduler.currentSessionID { updateDisplay(id) }
    }

    private func publishSessions() {
        sessions = machines.values.map(\.snapshot).sorted { $0.persisted.rotationIndex < $1.persisted.rotationIndex }
        sessionProjects = SessionProjectGrouper.groups(from: sessions)
        let validProjectKeys = Set(sessionProjects.map(\.id))
        let retainedExpandedKeys = expandedProjectKeys.intersection(validProjectKeys)
        if retainedExpandedKeys != expandedProjectKeys {
            expandedProjectKeys = retainedExpandedKeys
            defaults.set(Array(expandedProjectKeys).sorted(), forKey: "expandedProjectKeys")
        }
    }

    private func applyDisplayDecision(_ decision: CarouselDecision) {
        shouldAnimateDisplayChange = decision.animated
        displayedSession = decision.sessionID.flatMap { machines[$0]?.snapshot }
        logger.log(SessionEventLogFormatter.carouselSwitch(
            fromSessionID: decision.previousSessionID,
            toSessionID: decision.sessionID,
            projectName: displayedSession?.persisted.projectName,
            state: displayedSession?.state,
            reason: decision.reason,
            cycle: decision.cycle
        ))
    }

    private func updateDisplay(_ id: String?) {
        shouldAnimateDisplayChange = false
        displayedSession = id.flatMap { machines[$0]?.snapshot }
    }

    private func restoreSessions() {
        do {
            let restored = try sessionStore.load()
            for persisted in restored { machines[persisted.sessionID] = SessionStateMachine(snapshot: SessionSnapshot(persisted: persisted, state: .idle)); nextRotationIndex = max(nextRotationIndex, persisted.rotationIndex + 1) }
            refreshSessions()
            sessionDataHealth = sessionStore.health
        } catch {
            sessionDataHealth = sessionStore.health
            logger.log("error=session_store_read")
        }
    }

    @discardableResult
    private func persistSessions() -> Bool {
        guard sessionDataHealth.allowsSaving else { return false }
        do {
            try sessionStore.save(sessions.map(\.persisted))
            sessionDataHealth = sessionStore.health
            return true
        } catch {
            sessionDataHealth = sessionStore.health
            logger.log("error=session_store_write")
            return false
        }
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
        let saved = persistSessions()
        isSyncingSessions = false
        sessionSyncMessage = SessionSyncReport.message(
            readCount: threads.count,
            addedCount: result.addedCount,
            updatedCount: result.updatedCount,
            saved: saved
        )
        if saved {
            logger.log("sessions=sync_success count=\(threads.count) added=\(result.addedCount)")
        } else {
            logger.log("sessions=sync_persist_failed count=\(threads.count)")
        }
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
        localCommunicationHealth = LocalCommunicationHealth(state: .error, detail: "转发通道测试失败")
        hooksActionMessage = "\(message)。请先修复 Hooks，再在 Codex 中执行 /hooks 并信任。"
        logger.log("hooks=health_check_failed")
    }

    private func refreshHooksHealth() {
        let inspection = makeHooksInstaller().inspect()
        switch inspection.state {
        case .missing:
            hooksHealth = HooksHealth(state: .notInstalled, detail: inspection.summary)
        case .corrupted, .incomplete:
            hooksHealth = HooksHealth(state: .needsRepair, detail: inspection.summary)
        case .complete:
            if let last = defaults.object(forKey: "lastHookEvent") as? Date {
                hooksHealth = HooksHealth(state: .healthy, detail: "最近事件：\(last.formatted(date: .abbreviated, time: .shortened))")
            } else {
                hooksHealth = HooksHealth(state: .pendingVerification, detail: "请在 /hooks 信任后测试转发通道")
            }
        }
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

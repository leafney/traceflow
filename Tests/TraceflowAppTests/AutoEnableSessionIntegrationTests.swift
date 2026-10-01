import AppKit
import Darwin
import XCTest
import TraceflowCore
@testable import TraceflowApp

/// Exercises the real discovery and socket entry points without changing private APIs.
/// XCTest runs these cases serially; each fixture restores its process environment.
@MainActor
final class AutoEnableSessionIntegrationTests: XCTestCase {
    func testAutomaticDiscoveryEnablesOnlyNewSessionsAndPreservesIdleHUD() async throws {
        try await withFixture { fixture in
            let model = fixture.model
            XCTAssertFalse(model.autoEnableNewSessions)
            try await fixture.discover(["off"])
            XCTAssertFalse(try fixture.session("off").persisted.isIncludedInHUD)
            model.autoEnableNewSessions = true
            try await fixture.discover(["off", "on"])
            XCTAssertFalse(try fixture.session("off").persisted.isIncludedInHUD)
            XCTAssertTrue(try fixture.session("on").persisted.isIncludedInHUD)
            XCTAssertEqual(try fixture.session("on").state, .idle)
            XCTAssertNil(model.displayedSession)
            XCTAssertTrue(model.recentSessions.contains { $0.id == "on" })
            try await fixture.hook("on", event: .userPromptSubmit)
            XCTAssertEqual(model.displayedSession?.id, "on")
            XCTAssertFalse(model.isHUDVisible)
            model.autoEnableNewSessions = false
            XCTAssertTrue(try fixture.session("on").persisted.isIncludedInHUD)
        }
    }

    func testHookSessionStartWaitsForActivityAndUserSelectionWins() async throws {
        try await withFixture { fixture in
            fixture.model.autoEnableNewSessions = true
            try await fixture.hook("hook", event: .sessionStart)
            XCTAssertTrue(try fixture.session("hook").persisted.isIncludedInHUD)
            XCTAssertEqual(try fixture.session("hook").state, .idle)
            XCTAssertNil(fixture.model.displayedSession)
            try await fixture.hook("hook", event: .userPromptSubmit)
            XCTAssertEqual(fixture.model.displayedSession?.id, "hook")
            try await fixture.discover(["hook"])
            XCTAssertEqual(try fixture.session("hook").state, .running)
            XCTAssertTrue(try fixture.session("hook").persisted.isIncludedInHUD)
            fixture.model.setIncluded(false, sessionID: "hook")
            try await fixture.hook("hook", event: .userPromptSubmit)
            XCTAssertFalse(try fixture.session("hook").persisted.isIncludedInHUD)
            try await fixture.discover(["hook"])
            XCTAssertFalse(try fixture.session("hook").persisted.isIncludedInHUD)
            XCTAssertNil(fixture.model.displayedSession)
            fixture.model.autoEnableNewSessions = false
            try await fixture.hook("off", event: .userPromptSubmit)
            XCTAssertFalse(try fixture.session("off").persisted.isIncludedInHUD)
        }
    }

    func testManualSyncNeverAutoEnablesAndLaterInputsPreserveSelection() async throws {
        try await withFixture { fixture in
            for enabled in [false, true] {
                fixture.model.autoEnableNewSessions = enabled
                let id = enabled ? "manual-on" : "manual-off"
                try await fixture.discover([id], manual: true)
                XCTAssertFalse(try fixture.session(id).persisted.isIncludedInHUD)
                try await fixture.hook(id, event: .userPromptSubmit)
                try await fixture.discover([id])
                XCTAssertFalse(try fixture.session(id).persisted.isIncludedInHUD)
            }
            XCTAssertNil(fixture.model.displayedSession)
        }
    }

    func testAutomaticResponseUsesLatestPreferenceInBothDirections() async throws {
        try await withFixture { fixture in
            for initial in [false, true] {
                fixture.model.autoEnableNewSessions = initial
                let id = initial ? "changed-off" : "changed-on"
                try fixture.writeThreads([id])
                try Data().write(to: fixture.root.appendingPathComponent("delay"))
                try? FileManager.default.removeItem(at: fixture.root.appendingPathComponent("requested"))
                fixture.model.openSettingsWindow()
                try await fixture.waitUntil {
                    FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("requested").path)
                }
                fixture.model.autoEnableNewSessions = !initial
                try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("delay"))
                try await fixture.waitUntil { !fixture.model.isDiscoveringRecentSessions }
                XCTAssertNil(fixture.model.recentDiscoveryMessage)
                XCTAssertEqual(try fixture.session(id).persisted.isIncludedInHUD, !initial)
            }
        }
    }

    func testPreferenceAndSelectionsRestoreWithoutShowingHiddenHUD() async throws {
        try await withFixture { fixture in
            fixture.model.autoEnableNewSessions = true
            try await fixture.discover(["enabled"])
            try await fixture.discover(["manual"], manual: true)
            let restored = AppModel(defaults: fixture.defaults)
            XCTAssertTrue(restored.autoEnableNewSessions)
            XCTAssertFalse(restored.isHUDVisible)
            XCTAssertTrue(try XCTUnwrap(restored.sessions.first { $0.id == "enabled" }).persisted.isIncludedInHUD)
            XCTAssertFalse(try XCTUnwrap(restored.sessions.first { $0.id == "manual" }).persisted.isIncludedInHUD)
            XCTAssertNil(restored.displayedSession)
        }
    }

    func testHookWinsInitialSelectionWhileAutomaticResponseIsInFlight() async throws {
        try await withFixture { fixture in
            try fixture.writeThreads(["shared"])
            try Data().write(to: fixture.root.appendingPathComponent("delay"))
            fixture.model.openSettingsWindow()
            try await fixture.waitUntil {
                FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("requested").path)
            }
            // Hook creates a closed record before the enabled automatic merge arrives.
            try await fixture.hook("shared", event: .userPromptSubmit)
            fixture.model.autoEnableNewSessions = true
            try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("delay"))
            try await fixture.waitUntil { !fixture.model.isDiscoveringRecentSessions }
            XCTAssertNil(fixture.model.recentDiscoveryMessage)
            XCTAssertEqual(fixture.model.sessions.filter { $0.id == "shared" }.count, 1)
            XCTAssertFalse(try fixture.session("shared").persisted.isIncludedInHUD)
            XCTAssertEqual(try fixture.session("shared").state, .running)
            XCTAssertNil(fixture.model.displayedSession)
        }
    }

    private func withFixture(_ body: (AutoEnableFixture) async throws -> Void) async throws {
        _ = NSApplication.shared
        let fixture = try AutoEnableFixture()
        defer { fixture.cleanUp() }
        do {
            try await body(fixture)
        } catch {
            // Release an intentionally delayed response before removing its files.
            try? FileManager.default.removeItem(at: fixture.root.appendingPathComponent("delay"))
            try? await fixture.waitUntil {
                !fixture.model.isDiscoveringRecentSessions && !fixture.model.isSyncingSessions
            }
            throw error
        }
    }
}

@MainActor
private final class AutoEnableFixture {
    let root: URL
    let defaults: UserDefaults
    let model: AppModel
    private let domain: String
    private let environment: [String: String?]
    private let initialWindows: Set<Int>

    init() throws {
        // A short path keeps the Unix socket below sockaddr_un's path limit.
        root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("tf-" + String(UUID().uuidString.prefix(8)))
        domain = "Traceflow.AutoEnable." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        initialWindows = Set(NSApplication.shared.windows.map(\.windowNumber))
        environment = Dictionary(uniqueKeysWithValues: ["TRACEFLOW_HOME", "ZDOTDIR"].map { key in
            (key, getenv(key).map { String(cString: $0) })
        })
        let files = FileManager.default
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            let executable = root.appendingPathComponent("codex")
            try Self.server.write(to: executable, atomically: true, encoding: .utf8)
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            // Both files belong to the fixture; never load the user's shell files.
            let quotedRoot = "'" + root.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            let path = "export PATH=" + quotedRoot + ":$PATH\n"
            for name in [".zshenv", ".zlogin"] {
                try path.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
        } catch {
            try? files.removeItem(at: root)
            defaults.removePersistentDomain(forName: domain)
            throw error
        }
        setenv("TRACEFLOW_HOME", root.path, 1)
        setenv("ZDOTDIR", root.path, 1)
        model = AppModel(defaults: defaults)
        model.isHUDVisible = false
        model.startListening()
    }

    func cleanUp() {
        model.stopListening()
        for window in NSApplication.shared.windows where !initialWindows.contains(window.windowNumber) {
            window.orderOut(nil)
        }
        defaults.removePersistentDomain(forName: domain)
        for (key, value) in environment {
            if let value { setenv(key, value, 1) } else { unsetenv(key) }
        }
        try? FileManager.default.removeItem(at: root)
    }

    func session(_ id: String) throws -> SessionSnapshot {
        try XCTUnwrap(model.sessions.first { $0.id == id })
    }

    func writeThreads(_ ids: [String]) throws {
        let now = Int64(Date().timeIntervalSince1970) - 1
        let rows = ids.map { ["id": $0, "cwd": "/work/qa", "createdAt": now, "updatedAt": now, "source": "cli"] as [String: Any] }
        try JSONSerialization.data(withJSONObject: rows).write(to: root.appendingPathComponent("threads.json"), options: .atomic)
    }

    func discover(_ ids: [String], manual: Bool = false) async throws {
        try writeThreads(ids)
        if manual {
            model.syncCodexSessions()
            try await waitUntil { !model.isSyncingSessions }
            XCTAssertFalse(model.sessionSyncMessage?.contains("失败") ?? true)
        } else {
            model.openSettingsWindow()
            try await waitUntil { !model.isDiscoveringRecentSessions }
            XCTAssertNil(model.recentDiscoveryMessage)
        }
        for id in ids { _ = try session(id) }
    }

    func hook(_ id: String, event: HookEventName) async throws {
        let uptime = DispatchTime.now().uptimeNanoseconds
        let envelope = HookEnvelope(
            eventID: UUID().uuidString, capturedUptimeNanoseconds: uptime, forwardedAt: Date(),
            payload: HookPayload(sessionID: id, cwd: "/work/qa", eventName: event)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try UnixSocketClient.send(encoder.encode(envelope), to: TraceflowPaths.socket().path)
        // Wait for THIS event, even when the previous event left the state running.
        try await waitUntil { model.sessions.first { $0.id == id }?.lastAppliedUptimeNanoseconds == uptime }
    }

    func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date(timeIntervalSinceNow: 8)
        while !predicate(), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard predicate() else {
            XCTFail("应用入口异步处理超时")
            throw CocoaError(.coderReadCorrupt)
        }
    }

    private static let server = """
    #!/usr/bin/python3
    import json, sys, time, pathlib
    root = pathlib.Path(__file__).parent
    for line in sys.stdin:
        request = json.loads(line)
        if request['method'] == 'initialize':
            result = {}
        elif request['method'] == 'thread/list':
            (root / 'requested').write_text('yes')
            deadline = time.monotonic() + 5
            while (root / 'delay').exists() and time.monotonic() < deadline:
                time.sleep(.01)
            result = {'data': json.loads((root / 'threads.json').read_text()), 'nextCursor': None}
        else:
            continue
        print(json.dumps({'id': request['id'], 'result': result}), flush=True)
    """
}

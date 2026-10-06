import AppKit
import Darwin
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class SessionIntegrationFixture {
    let root: URL
    let defaults: UserDefaults
    let model: AppModel
    private let domain: String
    private let environment: [String: String?]
    private let initialWindows: Set<Int>

    init(beforeWrite: (() -> Void)? = nil) throws {
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
        model = AppModel(defaults: defaults, sessionStore: SessionStore(url: TraceflowPaths.sessions(), beforeWrite: beforeWrite))
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
            try await model.flushSessionWrites()
            XCTAssertFalse(model.sessionSyncMessage?.contains("失败") ?? true)
        } else {
            model.openSettingsWindow()
            try await waitUntil { !model.isDiscoveringRecentSessions }
            XCTAssertNil(model.recentDiscoveryMessage)
        }
        try await model.flushSessionWrites()
        for id in ids { _ = try session(id) }
    }

    func hook(_ id: String, event: HookEventName, flush: Bool = true) async throws {
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
        if flush { try await model.flushSessionWrites() }
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

/// Await outside XCTest's synchronous autoclosures.
@MainActor
func assertAsyncThrows<T>(_ expression: @autoclosure () async throws -> T,
                          file: StaticString = #filePath, line: UInt = #line,
                          _ handler: (Error) -> Void = { _ in }) async {
    do { _ = try await expression(); XCTFail("预期异步操作失败", file: file, line: line) }
    catch { handler(error) }
}

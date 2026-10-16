import AppKit
import Foundation
import XCTest
import TraceflowCore
@testable import TraceflowApp

/// Blocks one physical write, while allowing the main actor to keep processing.
private final class SessionWriteGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var armed = false
    private var blocked = false
    private var count = 0

    var writes: Int { lock.lock(); defer { lock.unlock() }; return count }
    var isBlocked: Bool { lock.lock(); defer { lock.unlock() }; return blocked }
    func arm() { lock.lock(); armed = true; lock.unlock() }
    func release() { semaphore.signal() }
    func beforeWrite() {
        lock.lock()
        count += 1
        let shouldBlock = armed
        armed = false
        blocked = shouldBlock
        lock.unlock()
        if shouldBlock {
            _ = semaphore.wait(timeout: .now() + 8)
            lock.lock(); blocked = false; lock.unlock()
        }
    }
}

@MainActor
final class SessionWriteQueueTests: XCTestCase {
    func testHistoricalPendingChoiceIsSupersededAndOldCommitCannotRestoreIt() async throws {
        _ = NSApplication.shared
        let gate = SessionWriteGate()
        let old = Date(timeIntervalSince1970: 100)
        let fixture = try SessionIntegrationFixture(beforeWrite: gate.beforeWrite, initialSessions: [
            PersistedSession(sessionID: "old", discoveredAt: old, lastUpdatedAt: old, rotationIndex: 0)
        ])
        defer { gate.release(); fixture.cleanUp() }
        try await fixture.model.flushSessionWrites()
        var completions = 0
        gate.arm()
        fixture.model.requestMarkerColor("#123456", sessionID: "old") { result in
            if case .success = result { completions += 1 }
        }
        try await fixture.waitUntil { gate.isBlocked }
        try fixture.writeThreads([String]())
        fixture.model.syncCodexSessions()
        try await fixture.waitUntil { !fixture.model.isSyncingSessions }
        let writes = gate.writes
        gate.arm()
        gate.release()
        try await fixture.waitUntil { gate.writes == writes + 1 && gate.isBlocked }
        XCTAssertNil(try fixture.session("old").persisted.markerColorHex)
        XCTAssertEqual(completions, 0, "旧回调不能提前完成被清理取代的编辑")
        gate.release()
        try await fixture.model.flushSessionWrites()
        XCTAssertEqual(completions, 1)
        XCTAssertNil(try fixture.session("old").persisted.markerColorHex)
        XCTAssertNil(try SessionStore(url: TraceflowPaths.sessions()).load().first?.markerColorHex)
    }

    func testHistoricalClearInFlightDoesNotOverwriteReactivatedHook() async throws {
        _ = NSApplication.shared
        let gate = SessionWriteGate()
        let old = Date(timeIntervalSince1970: 100)
        let fixture = try SessionIntegrationFixture(beforeWrite: gate.beforeWrite, initialSessions: [
            PersistedSession(sessionID: "old", customTitle: "保留标题", isIncludedInHUD: true,
                discoveredAt: old, lastUpdatedAt: old, rotationIndex: 0)
        ])
        defer { gate.release(); fixture.cleanUp() }
        try await fixture.model.flushSessionWrites()
        try await fixture.model.setMarkerColor("#123456", sessionID: "old")
        try fixture.writeThreads([String]())
        gate.arm()
        fixture.model.syncCodexSessions()
        try await fixture.waitUntil { !fixture.model.isSyncingSessions && gate.isBlocked }
        XCTAssertNil(try fixture.session("old").persisted.markerColorHex)
        try await fixture.hook("old", event: .userPromptSubmit, flush: false)
        let revived = try fixture.session("old")
        XCTAssertNotNil(revived.persisted.markerColorHex)
        gate.release()
        try await fixture.model.flushSessionWrites()
        XCTAssertEqual(try fixture.session("old"), revived)
        XCTAssertEqual(fixture.model.displayedSession?.persisted.markerColorHex, revived.persisted.markerColorHex)
        XCTAssertEqual(try SessionStore(url: TraceflowPaths.sessions()).load(), [try persistedRoundTrip(revived.persisted)])
    }

    func testSupersededPendingClearCanBeReplacedByReactivationBeforeCommit() async throws {
        _ = NSApplication.shared
        let gate = SessionWriteGate()
        let old = Date(timeIntervalSince1970: 100)
        let fixture = try SessionIntegrationFixture(beforeWrite: gate.beforeWrite, initialSessions: [
            PersistedSession(sessionID: "old", discoveredAt: old, lastUpdatedAt: old, rotationIndex: 0)
        ])
        defer { gate.release(); fixture.cleanUp() }
        try await fixture.model.flushSessionWrites()
        var completed = false
        gate.arm()
        fixture.model.requestMarkerColor("#123456", sessionID: "old") { result in
            if case .success = result { completed = true }
        }
        try await fixture.waitUntil { gate.isBlocked }
        try fixture.writeThreads([String]())
        fixture.model.syncCodexSessions()
        try await fixture.waitUntil { !fixture.model.isSyncingSessions }
        try await fixture.hook("old", event: .permissionRequest, flush: false)
        XCTAssertFalse(completed)
        gate.release()
        try await fixture.model.flushSessionWrites()
        XCTAssertTrue(completed)
        let revived = try fixture.session("old")
        XCTAssertEqual(revived.state, .attention)
        XCTAssertNotNil(revived.persisted.markerColorHex)
        XCTAssertEqual(try SessionStore(url: TraceflowPaths.sessions()).load(), [try persistedRoundTrip(revived.persisted)])
    }

    func testAlreadyGrayHistoricalStartupDoesNotScheduleWrite() async throws {
        _ = NSApplication.shared
        let gate = SessionWriteGate()
        let old = Date(timeIntervalSince1970: 100)
        let fixture = try SessionIntegrationFixture(beforeWrite: gate.beforeWrite, initialSessions: [
            PersistedSession(sessionID: "old", discoveredAt: old, lastUpdatedAt: old, rotationIndex: 0)
        ])
        defer { fixture.cleanUp() }
        try await fixture.model.flushSessionWrites()
        XCTAssertEqual(gate.writes, 0)
        XCTAssertNil(try fixture.session("old").persisted.markerColorHex)
    }

    func testRecentPendingManualColorReservesAutomaticAllocation() async throws {
        _ = NSApplication.shared
        let gate = SessionWriteGate()
        let fixture = try SessionIntegrationFixture(beforeWrite: gate.beforeWrite)
        defer { gate.release(); fixture.cleanUp() }
        try await fixture.hook("a", event: .sessionStart)
        let visible = try XCTUnwrap(fixture.session("a").persisted.markerColorHex)
        // This is the color the old allocator would choose without the pending edit.
        let choice = try SessionMarkerColor.allocate(occupied: [visible])
        gate.arm()
        fixture.model.requestMarkerColor(choice, sessionID: "a") { _ in }
        try await fixture.waitUntil { gate.isBlocked }
        try fixture.writeThreads(["b"])
        fixture.model.syncCodexSessions()
        try await fixture.waitUntil { !fixture.model.isSyncingSessions }
        XCTAssertEqual(try fixture.session("a").persisted.markerColorHex, visible)
        XCTAssertNotEqual(try fixture.session("b").persisted.markerColorHex, choice)
        gate.release()
        try await fixture.model.flushSessionWrites()
        XCTAssertEqual(try fixture.session("a").persisted.markerColorHex, choice)
        XCTAssertNotEqual(try fixture.session("b").persisted.markerColorHex, choice)
    }

    func testHistoricalCleanupSaveFailureIsVisibleAndRetryPersistsCleanup() async throws {
        _ = NSApplication.shared
        let gate = SessionWriteGate()
        let old = Date(timeIntervalSince1970: 100)
        let fixture = try SessionIntegrationFixture(beforeWrite: gate.beforeWrite, initialSessions: [
            PersistedSession(sessionID: "old", discoveredAt: old, lastUpdatedAt: old, rotationIndex: 0)
        ])
        defer { gate.release(); fixture.cleanUp() }
        try await fixture.model.flushSessionWrites()
        try await fixture.model.setMarkerColor("#123456", sessionID: "old")
        try fixture.writeThreads(["recent"])
        gate.arm()
        fixture.model.openSettingsWindow()
        try await fixture.waitUntil { !fixture.model.isDiscoveringRecentSessions && gate.isBlocked }
        let directory = TraceflowPaths.sessions().deletingLastPathComponent()
        let backup = fixture.root.appendingPathComponent("data-backup")
        try FileManager.default.moveItem(at: directory, to: backup)
        try Data("blocked".utf8).write(to: directory)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: backup, to: directory)
        }
        gate.release()
        await assertAsyncThrows(try await fixture.model.flushSessionWrites())
        XCTAssertNil(try fixture.session("old").persisted.markerColorHex)
        XCTAssertNotNil(fixture.model.markerColorErrorMessage)
        XCTAssertFalse(fixture.model.sessionDataHealth.allowsSaving)
        XCTAssertEqual(try SessionStore(url: backup.appendingPathComponent("sessions.json")).load().first?.markerColorHex, "#123456")
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backup, to: directory)
        fixture.model.retrySessionSave()
        try await fixture.model.flushSessionWrites()
        XCTAssertNil(fixture.model.markerColorErrorMessage)
        XCTAssertTrue(fixture.model.sessionDataHealth.allowsSaving)
        XCTAssertNil(try SessionStore(url: TraceflowPaths.sessions()).load().first { $0.id == "old" }?.markerColorHex)
    }

    func testFailedPendingManualSaveDoesNotCollideWithNewAutomaticColorOnRetry() async throws {
        _ = NSApplication.shared
        let gate = SessionWriteGate()
        let fixture = try SessionIntegrationFixture(beforeWrite: gate.beforeWrite)
        defer { gate.release(); fixture.cleanUp() }
        try await fixture.hook("a", event: .sessionStart)
        let choice = "#123456"
        // Without reserving the committed fallback, B would receive this exact color.
        let fallback = try SessionMarkerColor.allocate(occupied: [choice])
        try await fixture.model.setMarkerColor(fallback, sessionID: "a")
        gate.arm()
        fixture.model.requestMarkerColor(choice, sessionID: "a") { _ in }
        try await fixture.waitUntil { gate.isBlocked }
        try fixture.writeThreads(["b"])
        fixture.model.syncCodexSessions()
        try await fixture.waitUntil { !fixture.model.isSyncingSessions }
        let generated = try XCTUnwrap(fixture.session("b").persisted.markerColorHex)
        XCTAssertNotEqual(generated, fallback)
        XCTAssertNotEqual(generated, choice)
        let directory = TraceflowPaths.sessions().deletingLastPathComponent()
        let backup = fixture.root.appendingPathComponent("data-backup")
        try FileManager.default.moveItem(at: directory, to: backup)
        try Data("blocked".utf8).write(to: directory)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: backup, to: directory)
        }
        gate.release()
        await assertAsyncThrows(try await fixture.model.flushSessionWrites())
        XCTAssertEqual(try fixture.session("a").persisted.markerColorHex, fallback)
        XCTAssertEqual(try fixture.session("b").persisted.markerColorHex, generated)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backup, to: directory)
        fixture.model.retrySessionSave()
        try await fixture.model.flushSessionWrites()
        let colors = try SessionStore(url: TraceflowPaths.sessions()).load().compactMap(\.markerColorHex)
        XCTAssertEqual(Set(colors), [fallback, generated])
    }

    func testContinuousPanelChoicesCoalesceAndCloseRetargetKeepFinalValues() async throws {
        _ = NSApplication.shared
        let gate = SessionWriteGate()
        let fixture = try SessionIntegrationFixture(beforeWrite: gate.beforeWrite)
        defer { gate.release(); fixture.cleanUp() }
        try await fixture.hook("a", event: .sessionStart)
        try await fixture.hook("b", event: .sessionStart)
        let initialWrites = gate.writes
        let oldA = try fixture.session("a").persisted.markerColorHex
        let panel = NSColorPanel.shared
        let controller = fixture.model.sessionColorPanel
        controller.open(sessionID: "a")
        gate.arm()
        panel.color = .red
        try XCTUnwrap(controller.target).colorChanged(panel)
        try await fixture.waitUntil { gate.isBlocked }
        for index in 1...40 {
            panel.color = NSColor(srgbRed: CGFloat(index) / 100, green: 0.2, blue: 0.3, alpha: 1)
            try XCTUnwrap(controller.target).colorChanged(panel)
        }
        // Retarget before any completion; already accepted A edits must survive.
        controller.open(sessionID: "b")
        panel.color = .blue
        try XCTUnwrap(controller.target).colorChanged(panel)
        controller.close()
        XCTAssertEqual(try fixture.session("a").persisted.markerColorHex, oldA)
        XCTAssertEqual(gate.writes, initialWrites + 1)
        fixture.model.isHUDPinned.toggle() // main actor responds during disk stall
        gate.release()
        try await fixture.model.flushSessionWrites()
        XCTAssertEqual(try fixture.session("a").persisted.markerColorHex, "#66334D")
        XCTAssertEqual(try fixture.session("b").persisted.markerColorHex, "#0000FF")
        XCTAssertEqual(gate.writes, initialWrites + 2, "等待中的连续通知只能合并成一批写入")
        let saved = try SessionStore(url: TraceflowPaths.sessions()).load()
        XCTAssertEqual(saved.first { $0.id == "a" }?.markerColorHex, "#66334D")
        XCTAssertEqual(saved.first { $0.id == "b" }?.markerColorHex, "#0000FF")
    }

    func testInFlightColorDoesNotOverwriteHookTitleOrInclusion() async throws {
        _ = NSApplication.shared
        let gate = SessionWriteGate()
        let fixture = try SessionIntegrationFixture(beforeWrite: gate.beforeWrite)
        defer { gate.release(); fixture.cleanUp() }
        try await fixture.hook("a", event: .sessionStart)
        var colorFinished = false
        gate.arm()
        fixture.model.requestMarkerColor("#123456", sessionID: "a") { result in
            if case .success = result { colorFinished = true }
        }
        try await fixture.waitUntil { gate.isBlocked }
        try await fixture.hook("a", event: .permissionRequest, flush: false)
        let latest = try fixture.session("a")
        fixture.model.setIncluded(true, sessionID: "a")
        let editing = SessionTitleEditingState(model: fixture.model, session: latest)
        editing.draft = "并发保存标题"
        let titleTask = Task { await editing.save() }
        try await fixture.waitUntil { editing.isSaving }
        XCTAssertFalse(editing.canSave)
        XCTAssertFalse(colorFinished)
        gate.release()
        try await fixture.model.flushSessionWrites()
        let titleSaved = await titleTask.value
        XCTAssertTrue(titleSaved)
        XCTAssertTrue(colorFinished)
        let after = try fixture.session("a")
        XCTAssertEqual(after.state, .attention)
        XCTAssertEqual(after.lastAppliedUptimeNanoseconds, latest.lastAppliedUptimeNanoseconds)
        XCTAssertEqual(after.persisted.markerColorHex, "#123456")
        XCTAssertEqual(after.persisted.customTitle, "并发保存标题")
        XCTAssertTrue(after.persisted.isIncludedInHUD)
        XCTAssertEqual(try SessionStore(url: TraceflowPaths.sessions()).load(), [try persistedRoundTrip(after.persisted)])
    }

    func testDeletionAndSameIDReimportRejectOldEditAndOldCompletion() async throws {
        _ = NSApplication.shared
        let gate = SessionWriteGate()
        let fixture = try SessionIntegrationFixture(beforeWrite: gate.beforeWrite)
        defer { gate.release(); fixture.cleanUp() }
        try await fixture.hook("a", event: .sessionStart)
        gate.arm()
        var error: SessionMarkerColorError?
        fixture.model.requestMarkerColor("#FFFFFF", sessionID: "a") { result in
            if case .failure(let failure) = result { error = failure as? SessionMarkerColorError }
        }
        try await fixture.waitUntil { gate.isBlocked }
        fixture.model.deleteSession("a")
        XCTAssertNotNil(error)
        if case .missingSession? = error {} else { XCTFail("删除必须取消目标编辑") }
        // Manual import explicitly recreates a record with the same ID.
        try fixture.writeThreads(["a"])
        fixture.model.syncCodexSessions()
        try await fixture.waitUntil { !fixture.model.isSyncingSessions }
        let recreated = try fixture.session("a")
        XCTAssertNotEqual(recreated.persisted.markerColorHex, "#FFFFFF")
        gate.release()
        try await fixture.model.flushSessionWrites()
        XCTAssertEqual(try fixture.session("a"), recreated)
        XCTAssertEqual(try SessionStore(url: TraceflowPaths.sessions()).load(), [recreated.persisted])
        fixture.model.deleteSession("a")
        try await fixture.model.flushSessionWrites()
        XCTAssertTrue(try SessionStore(url: TraceflowPaths.sessions()).load().isEmpty)
    }

    func testFailedBatchPublishesNoColorAndRetrySavesLatestHook() async throws {
        _ = NSApplication.shared
        let gate = SessionWriteGate()
        let fixture = try SessionIntegrationFixture(beforeWrite: gate.beforeWrite)
        defer { gate.release(); fixture.cleanUp() }
        try await fixture.hook("a", event: .sessionStart)
        let oldColor = try fixture.session("a").persisted.markerColorHex
        gate.arm()
        var failures = 0
        let completion: (Result<Void, Error>) -> Void = { result in
            if case .failure = result { failures += 1 }
        }
        fixture.model.requestMarkerColor("#111111", sessionID: "a", completion: completion)
        try await fixture.waitUntil { gate.isBlocked }
        fixture.model.requestMarkerColor("#222222", sessionID: "a", completion: completion)
        try await fixture.hook("a", event: .userPromptSubmit, flush: false)
        fixture.model.setIncluded(true, sessionID: "a")
        let directory = TraceflowPaths.sessions().deletingLastPathComponent()
        let backup = fixture.root.appendingPathComponent("data-backup")
        try FileManager.default.moveItem(at: directory, to: backup)
        try Data("blocked".utf8).write(to: directory)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: backup, to: directory)
        }
        gate.release()
        await assertAsyncThrows(try await fixture.model.flushSessionWrites())
        XCTAssertEqual(failures, 2)
        XCTAssertEqual(try fixture.session("a").persisted.markerColorHex, oldColor)
        XCTAssertEqual(try fixture.session("a").state, .running)
        XCTAssertFalse(fixture.model.sessionDataHealth.allowsSaving)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backup, to: directory)
        fixture.model.retrySessionSave()
        XCTAssertNotEqual(fixture.model.sessionSyncMessage, "会话数据保存成功。")
        try await fixture.model.flushSessionWrites()
        XCTAssertEqual(fixture.model.sessionSyncMessage, "会话数据保存成功。")
        XCTAssertTrue(fixture.model.sessionDataHealth.allowsSaving)
        XCTAssertEqual(try SessionStore(url: TraceflowPaths.sessions()).load(), [try persistedRoundTrip(fixture.session("a").persisted)])
    }

    func testSuccessfulIntermediateColorRemainsVisibleWhenLatestChoiceFails() async throws {
        _ = NSApplication.shared
        let gate = SessionWriteGate()
        let fixture = try SessionIntegrationFixture(beforeWrite: gate.beforeWrite)
        defer { gate.release(); fixture.cleanUp() }
        try await fixture.hook("a", event: .sessionStart)
        let initialWrites = gate.writes
        gate.arm()
        fixture.model.requestMarkerColor("#111111", sessionID: "a") { _ in }
        try await fixture.waitUntil { gate.isBlocked }
        fixture.model.requestMarkerColor("#222222", sessionID: "a") { _ in }
        gate.arm() // block the follow-up write after the first successful commit
        gate.release()
        try await fixture.waitUntil { gate.writes == initialWrites + 2 && gate.isBlocked }
        XCTAssertEqual(try fixture.session("a").persisted.markerColorHex, "#111111")
        let directory = TraceflowPaths.sessions().deletingLastPathComponent()
        let backup = fixture.root.appendingPathComponent("data-backup")
        try FileManager.default.moveItem(at: directory, to: backup)
        try Data("blocked".utf8).write(to: directory)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: backup, to: directory)
        }
        gate.release()
        await assertAsyncThrows(try await fixture.model.flushSessionWrites())
        XCTAssertEqual(try fixture.session("a").persisted.markerColorHex, "#111111")
        XCTAssertEqual(try SessionStore(url: backup.appendingPathComponent("sessions.json")).load().first?.markerColorHex, "#111111")
    }

    func testSynchronousCleanupBarrierCannotLeaveLateWrites() async throws {
        _ = NSApplication.shared
        let gate = SessionWriteGate()
        let fixture = try SessionIntegrationFixture(beforeWrite: gate.beforeWrite)
        defer { gate.release(); fixture.cleanUp() }
        try await fixture.hook("a", event: .sessionStart)
        gate.arm()
        fixture.model.requestMarkerColor("#111111", sessionID: "a") { _ in }
        try await fixture.waitUntil { gate.isBlocked }
        fixture.model.requestMarkerColor("#ABCDEF", sessionID: "a") { _ in }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { gate.release() }
        fixture.model.stopListening()
        XCTAssertEqual(try SessionStore(url: TraceflowPaths.sessions()).load().first?.markerColorHex, "#ABCDEF")
        try FileManager.default.removeItem(at: fixture.root)
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.path))
    }

    private func persistedRoundTrip(_ record: PersistedSession) throws -> PersistedSession {
        // Existing on-disk ISO dates have second precision; live Hook dates do not.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PersistedSession.self, from: encoder.encode(record))
    }

    func testShutdownFlushWaitsForLastAcceptedChoice() async throws {
        _ = NSApplication.shared
        let gate = SessionWriteGate()
        let fixture = try SessionIntegrationFixture(beforeWrite: gate.beforeWrite)
        defer { gate.release(); fixture.cleanUp() }
        try await fixture.hook("a", event: .sessionStart)
        gate.arm()
        fixture.model.requestMarkerColor("#111111", sessionID: "a") { _ in }
        try await fixture.waitUntil { gate.isBlocked }
        fixture.model.requestMarkerColor("#ABCDEF", sessionID: "a") { _ in }
        fixture.model.beginShutdown()
        var flushed = false
        let task = Task {
            try await fixture.model.flushSessionWrites()
            flushed = true
        }
        await Task.yield()
        XCTAssertFalse(flushed)
        gate.release()
        try await task.value
        XCTAssertTrue(flushed)
        XCTAssertEqual(try SessionStore(url: TraceflowPaths.sessions()).load().first?.markerColorHex, "#ABCDEF")
    }
}

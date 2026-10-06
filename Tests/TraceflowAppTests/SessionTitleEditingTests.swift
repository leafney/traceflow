import AppKit
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class SessionTitleEditingTests: XCTestCase {
    func testSaveRestoreAndBackgroundInputsKeepLatestState() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.autoEnableNewSessions = true
        try await fixture.hook("title", event: .userPromptSubmit)
        let before = try fixture.session("title")
        try await model.setCustomTitle(" 自定义标题 ", sessionID: "title")
        var expected = before
        expected.persisted.customTitle = "自定义标题"
        XCTAssertEqual(try fixture.session("title"), expected)
        XCTAssertEqual(model.displayedSession?.displayTitle, "qa · 自定义标题")
        XCTAssertEqual(model.recentSessions.first { $0.id == "title" }?.sessionListTitle, "自定义标题")
        XCTAssertEqual(model.sessionProjects.first?.sessions.first?.sessionListTitle, "自定义标题")
        let restored = AppModel(defaults: fixture.defaults)
        XCTAssertEqual(restored.sessions.first?.persisted.customTitle, "自定义标题")
        try await fixture.discover(["title"])
        try await fixture.hook("title", event: .permissionRequest)
        XCTAssertEqual(try fixture.session("title").persisted.customTitle, "自定义标题")
        let latest = try fixture.session("title")
        try await model.setCustomTitle("另一个标题", sessionID: "title")
        expected = latest
        expected.persisted.customTitle = "另一个标题"
        XCTAssertEqual(try fixture.session("title"), expected)
        let now = Int64(Date().timeIntervalSince1970) - 1
        let rows: [[String: Any]] = [["id": "title", "name": "最新默认名称", "cwd": "/work/qa", "createdAt": now, "updatedAt": now, "source": "cli"]]
        try JSONSerialization.data(withJSONObject: rows).write(to: fixture.root.appendingPathComponent("threads.json"))
        model.syncCodexSessions()
        try await fixture.waitUntil { !model.isSyncingSessions }
        XCTAssertEqual(try fixture.session("title").persisted.customTitle, "另一个标题")
        try await model.resetCustomTitle(sessionID: "title")
        XCTAssertNil(try fixture.session("title").persisted.customTitle)
        XCTAssertEqual(model.displayedSession?.state, .attention)
        XCTAssertEqual(model.displayedSession?.displayTitle, "qa · 最新默认名称")
    }

    func testRenameDoesNotRestartRotationOrDisplayIdleSession() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        fixture.model.displayDuration = 10
        try await fixture.hook("a", event: .userPromptSubmit)
        let visibleFrom = Date()
        try await fixture.hook("b", event: .userPromptSubmit)
        XCTAssertEqual(fixture.model.displayedSession?.id, "a")
        // Rename well into the cycle. A reset here would expire after the probe below.
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let renamedAt = Date()
        try await fixture.model.setCustomTitle("当前项", sessionID: "a")
        try await fixture.model.setCustomTitle("非当前项", sessionID: "b")
        XCTAssertEqual(fixture.model.displayedSession?.id, "a")
        fixture.model.tick(now: visibleFrom.addingTimeInterval(10.2))
        XCTAssertLessThan(visibleFrom.addingTimeInterval(10.2), renamedAt.addingTimeInterval(10))
        XCTAssertEqual(fixture.model.displayedSession?.id, "b")
        try await fixture.hook("idle", event: .sessionStart)
        try await fixture.model.setCustomTitle("待机项", sessionID: "idle")
        XCTAssertEqual(try fixture.session("idle").state, .idle)
        XCTAssertEqual(fixture.model.displayedSession?.id, "b")
    }

    func testFailedWriteDoesNotPublishCandidateAndInvalidTargetsDoNotCreateRecords() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        try await fixture.hook("title", event: .userPromptSubmit)
        try await fixture.model.setCustomTitle("原标题", sessionID: "title")
        let before = try fixture.session("title")
        let display = fixture.model.displayedSession
        let file = TraceflowPaths.sessions()
        let bytes = try Data(contentsOf: file)
        await assertAsyncThrows(try await fixture.model.setCustomTitle(" \n ", sessionID: "title"))
        await assertAsyncThrows(try await fixture.model.setCustomTitle("有效", sessionID: "missing"))
        XCTAssertEqual(fixture.model.sessions.count, 1)
        // Block directory creation deterministically rather than rely on chmod/root behavior.
        let directory = file.deletingLastPathComponent()
        let backup = fixture.root.appendingPathComponent("saved-data")
        try FileManager.default.moveItem(at: directory, to: backup)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: backup, to: directory)
        }
        try Data("blocked".utf8).write(to: directory)
        await assertAsyncThrows(try await fixture.model.setCustomTitle("不能落盘", sessionID: "title")) {
            XCTAssertEqual($0 as? SessionTitleSaveError, .writeFailed)
        }
        XCTAssertEqual(try fixture.session("title"), before)
        XCTAssertEqual(fixture.model.displayedSession, display)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("sessions.json")), bytes)
        XCTAssertFalse(fixture.model.sessionDataHealth.allowsSaving)
        await assertAsyncThrows(try await fixture.model.resetCustomTitle(sessionID: "title"))
    }

    func testDeletedRecordCannotBeRenamedOrRecoverItsCustomTitle() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        try await fixture.hook("deleted", event: .sessionStart)
        try await fixture.model.setCustomTitle("旧标题", sessionID: "deleted")
        fixture.model.deleteSession("deleted")
        await assertAsyncThrows(try await fixture.model.setCustomTitle("不能重建", sessionID: "deleted")) {
            XCTAssertEqual($0 as? SessionTitleSaveError, .missingSession)
        }
        try await fixture.discover(["deleted"], manual: true)
        XCTAssertNil(try fixture.session("deleted").persisted.customTitle)
        XCTAssertNil(fixture.model.displayedSession)
    }
}

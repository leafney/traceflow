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
        try model.setCustomTitle(" 自定义标题 ", sessionID: "title")
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
        try model.setCustomTitle("另一个标题", sessionID: "title")
        expected = latest
        expected.persisted.customTitle = "另一个标题"
        XCTAssertEqual(try fixture.session("title"), expected)
        try model.resetCustomTitle(sessionID: "title")
        XCTAssertNil(try fixture.session("title").persisted.customTitle)
        XCTAssertEqual(model.displayedSession?.state, .attention)
        XCTAssertEqual(model.displayedSession?.displayTitle, "qa")
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
        try fixture.model.setCustomTitle("当前项", sessionID: "a")
        try fixture.model.setCustomTitle("非当前项", sessionID: "b")
        XCTAssertEqual(fixture.model.displayedSession?.id, "a")
        fixture.model.tick(now: visibleFrom.addingTimeInterval(10.3))
        XCTAssertEqual(fixture.model.displayedSession?.id, "b")
        try await fixture.hook("idle", event: .sessionStart)
        try fixture.model.setCustomTitle("待机项", sessionID: "idle")
        XCTAssertEqual(try fixture.session("idle").state, .idle)
        XCTAssertEqual(fixture.model.displayedSession?.id, "b")
    }

    func testFailedWriteDoesNotPublishCandidateAndInvalidTargetsDoNotCreateRecords() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        try await fixture.hook("title", event: .userPromptSubmit)
        try fixture.model.setCustomTitle("原标题", sessionID: "title")
        let before = try fixture.session("title")
        let display = fixture.model.displayedSession
        let file = TraceflowPaths.sessions()
        let bytes = try Data(contentsOf: file)
        XCTAssertThrowsError(try fixture.model.setCustomTitle(" \n ", sessionID: "title"))
        XCTAssertThrowsError(try fixture.model.setCustomTitle("有效", sessionID: "missing"))
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
        XCTAssertThrowsError(try fixture.model.setCustomTitle("不能落盘", sessionID: "title")) {
            XCTAssertEqual($0 as? SessionTitleSaveError, .writeFailed)
        }
        XCTAssertEqual(try fixture.session("title"), before)
        XCTAssertEqual(fixture.model.displayedSession, display)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("sessions.json")), bytes)
        XCTAssertFalse(fixture.model.sessionDataHealth.allowsSaving)
        XCTAssertThrowsError(try fixture.model.resetCustomTitle(sessionID: "title"))
    }
}

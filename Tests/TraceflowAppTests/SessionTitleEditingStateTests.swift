import AppKit
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class SessionTitleEditingStateTests: XCTestCase {
    func testInvalidSubmissionCancelAndBackgroundUpdatesPreserveDraft() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        try await fixture.hook("editor", event: .sessionStart)
        var editing: SessionTitleEditingState? = SessionTitleEditingState(model: fixture.model, session: try fixture.session("editor"))
        let file = TraceflowPaths.sessions()
        let before = try Data(contentsOf: file)
        editing?.draft = "一\n二"
        XCTAssertFalse(try XCTUnwrap(editing).save())
        XCTAssertFalse(try XCTUnwrap(editing).canSave)
        XCTAssertEqual(try Data(contentsOf: file), before)
        editing?.draft = "尚未保存的草稿"
        try await fixture.hook("editor", event: .userPromptSubmit)
        try await fixture.discover(["editor"])
        XCTAssertEqual(editing?.draft, "尚未保存的草稿")
        XCTAssertNil(try fixture.session("editor").persisted.customTitle)
        // Closing/cancel discards the edit transaction, without invoking a model write.
        editing = nil
        XCTAssertNil(try fixture.session("editor").persisted.customTitle)
        let reopened = SessionTitleEditingState(model: fixture.model, session: try fixture.session("editor"))
        reopened.draft = "新名称"
        XCTAssertTrue(reopened.save())
        let again = SessionTitleEditingState(model: fixture.model, session: try fixture.session("editor"))
        XCTAssertEqual(again.draft, "新名称")
        XCTAssertTrue(again.canRestore)
        XCTAssertTrue(again.restore())
        XCTAssertFalse(again.canRestore)
        XCTAssertNil(try fixture.session("editor").persisted.customTitle)
    }

    func testWriteFailureKeepsDraftAndMissingTargetOverridesOldError() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        try await fixture.hook("editor", event: .sessionStart)
        let editing = SessionTitleEditingState(model: fixture.model, session: try fixture.session("editor"))
        editing.draft = "保存失败仍保留"
        let directory = TraceflowPaths.sessions().deletingLastPathComponent()
        let backup = fixture.root.appendingPathComponent("data-backup")
        try FileManager.default.moveItem(at: directory, to: backup)
        try Data("blocked".utf8).write(to: directory)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: backup, to: directory)
        }
        XCTAssertFalse(editing.save())
        XCTAssertEqual(editing.draft, "保存失败仍保留")
        XCTAssertEqual(editing.message, SessionTitleSaveError.writeFailed.localizedDescription)
        XCTAssertFalse(editing.canSave)
        XCTAssertFalse(editing.canRestore)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backup, to: directory)
        fixture.model.retrySessionSave()
        fixture.model.deleteSession("editor")
        XCTAssertEqual(editing.message, "会话已不存在")
        XCTAssertFalse(editing.save())
        XCTAssertFalse(editing.restore())
        XCTAssertTrue(fixture.model.sessions.isEmpty)
    }
}

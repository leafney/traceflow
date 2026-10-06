import AppKit
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class SessionMarkerEditingTests: XCTestCase {
    func testAllImportPathsRetainColorsAndEditingKeepsSnapshotAndCycle() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        fixture.model.displayDuration = 10
        try await fixture.hook("a", event: .userPromptSubmit)
        let began = Date()
        try await fixture.hook("b", event: .userPromptSubmit)
        let before = try fixture.session("a")
        XCTAssertNotNil(before.persisted.markerColorHex)
        XCTAssertNotEqual(before.persisted.markerColorHex, try fixture.session("b").persisted.markerColorHex)
        try await fixture.model.setMarkerColor("#ABCDEF", sessionID: "a")
        var expected = before
        expected.persisted.markerColorHex = "#ABCDEF"
        XCTAssertEqual(try fixture.session("a"), expected)
        fixture.model.tick(now: began.addingTimeInterval(10.2))
        XCTAssertEqual(fixture.model.displayedSession?.id, "b")
        try await fixture.discover(["a", "auto"])
        try await fixture.discover(["a", "manual"], manual: true)
        XCTAssertEqual(try fixture.session("a").persisted.markerColorHex, "#ABCDEF")
        XCTAssertNotNil(try fixture.session("auto").persisted.markerColorHex)
        XCTAssertNotNil(try fixture.session("manual").persisted.markerColorHex)
        let restored = AppModel(defaults: fixture.defaults)
        XCTAssertEqual(restored.sessions.first { $0.id == "a" }?.persisted.markerColorHex, "#ABCDEF")
        // Explicitly allow duplicate manual colors.
        try await fixture.model.setMarkerColor("#ABCDEF", sessionID: "b")
        XCTAssertEqual(try fixture.session("b").persisted.markerColorHex, "#ABCDEF")
    }

    func testStartupFillsLegacyRecordsAndPersistsOnce() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        let date = Date(timeIntervalSince1970: 100)
        let legacy = PersistedSession(sessionID: "legacy", discoveredAt: date, lastUpdatedAt: date, rotationIndex: 1)
        try SessionStore(url: TraceflowPaths.sessions()).save([legacy])
        let restored = AppModel(defaults: fixture.defaults)
        let record = try XCTUnwrap(restored.sessions.first?.persisted)
        XCTAssertEqual(record.markerColorHex, "#477EE8")
        XCTAssertEqual(record.lastUpdatedAt, date)
        try await restored.flushSessionWrites()
        XCTAssertEqual(try SessionStore(url: TraceflowPaths.sessions()).load(), [record])
        XCTAssertEqual(AppModel(defaults: fixture.defaults).sessions.first?.persisted, record)
    }

    func testFailedColorSaveDoesNotPublishAndDeletedTargetsAreRejected() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        try await fixture.hook("a", event: .sessionStart)
        let before = try fixture.session("a")
        await assertAsyncThrows(try await fixture.model.setMarkerColor("bad", sessionID: "a"))
        let directory = TraceflowPaths.sessions().deletingLastPathComponent()
        let backup = fixture.root.appendingPathComponent("saved-data")
        try FileManager.default.moveItem(at: directory, to: backup)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: backup, to: directory)
        }
        try Data("blocked".utf8).write(to: directory)
        await assertAsyncThrows(try await fixture.model.setMarkerColor("#ABCDEF", sessionID: "a"))
        XCTAssertEqual(try fixture.session("a"), before)
        XCTAssertFalse(fixture.model.sessionDataHealth.allowsSaving)
        await assertAsyncThrows(try await fixture.model.setMarkerColor("#ABCDEF", sessionID: "missing"))
    }
}

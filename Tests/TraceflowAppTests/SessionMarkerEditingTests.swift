import AppKit
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class SessionMarkerEditingTests: XCTestCase {
    func testStartupClearsHistoricalColorsAndPersistsWithoutChangingMetadata() async throws {
        _ = NSApplication.shared
        let old = Date(timeIntervalSince1970: 100)
        let record = PersistedSession(sessionID: "old", projectPath: "/work/qa", customTitle: "保留标题",
            markerColorHex: "#123456", isIncludedInHUD: true, discoveredAt: old,
            lastUpdatedAt: old, lastActivityAt: old, settingsListSortAt: old, rotationIndex: 2)
        let fixture = try SessionIntegrationFixture(initialSessions: [record])
        defer { fixture.cleanUp() }
        var expected = record
        expected.markerColorHex = nil
        XCTAssertEqual(try fixture.session("old").persisted, expected)
        try await fixture.model.flushSessionWrites()
        XCTAssertEqual(try SessionStore(url: TraceflowPaths.sessions()).load(), [expected])
        let restored = AppModel(defaults: fixture.defaults)
        XCTAssertEqual(restored.sessions.first?.persisted, expected)
        try await restored.flushSessionWrites()
    }

    func testManualSyncClearsOldColorsRetainsRecentAndRevivesUpdatedHistory() async throws {
        _ = NSApplication.shared
        let old = Date(timeIntervalSince1970: 100)
        let records = ["old", "revived", "absent"].enumerated().map { index, id in
            PersistedSession(sessionID: id, discoveredAt: old, lastUpdatedAt: old, rotationIndex: index)
        }
        let fixture = try SessionIntegrationFixture(initialSessions: records)
        defer { fixture.cleanUp() }
        try await fixture.model.flushSessionWrites()
        for id in ["old", "absent"] { try await fixture.model.setMarkerColor("#123456", sessionID: id) }
        try await fixture.hook("recent", event: .sessionStart)
        try await fixture.model.setMarkerColor("#ABCDEF", sessionID: "recent")
        // Recolor after the Hook's cleanup, so the sync must clear it again.
        for id in ["old", "absent"] { try await fixture.model.setMarkerColor("#123456", sessionID: id) }
        let now = Date().addingTimeInterval(-1)
        try fixture.writeThreads([
            CodexThreadSummary(id: "old", name: nil, cwd: "/work/qa", createdAt: old, updatedAt: old, sourceKind: "cli"),
            CodexThreadSummary(id: "new-old", name: nil, cwd: "/work/qa", createdAt: old, updatedAt: old, sourceKind: "cli"),
            CodexThreadSummary(id: "revived", name: nil, cwd: "/work/qa", createdAt: old, updatedAt: now, sourceKind: "cli"),
            CodexThreadSummary(id: "new-recent", name: nil, cwd: "/work/qa", createdAt: now, updatedAt: now, sourceKind: "cli")
        ])
        fixture.model.syncCodexSessions()
        try await fixture.waitUntil { !fixture.model.isSyncingSessions }
        try await fixture.model.flushSessionWrites()
        for id in ["old", "new-old", "absent"] { XCTAssertNil(try fixture.session(id).persisted.markerColorHex) }
        XCTAssertEqual(try fixture.session("recent").persisted.markerColorHex, "#ABCDEF")
        let colors = try ["recent", "revived", "new-recent"].map { try XCTUnwrap(fixture.session($0).persisted.markerColorHex) }
        XCTAssertEqual(Set(colors).count, 3)
        let saved = try SessionStore(url: TraceflowPaths.sessions()).load()
        XCTAssertTrue(saved.filter { ["old", "new-old", "absent"].contains($0.id) }.allSatisfy { $0.markerColorHex == nil })
    }

    func testAutomaticDiscoveryClearsHistoryAbsentFromResponseAndHookRevivesIt() async throws {
        _ = NSApplication.shared
        let old = Date(timeIntervalSince1970: 100)
        let fixture = try SessionIntegrationFixture(initialSessions: [
            PersistedSession(sessionID: "old", discoveredAt: old, lastUpdatedAt: old, rotationIndex: 0)
        ])
        defer { fixture.cleanUp() }
        try await fixture.model.flushSessionWrites()
        try await fixture.model.setMarkerColor("#123456", sessionID: "old")
        try await fixture.discover(["recent"])
        XCTAssertNil(try fixture.session("old").persisted.markerColorHex)
        try await fixture.hook("old", event: .userPromptSubmit)
        XCTAssertNotNil(try fixture.session("old").persisted.markerColorHex)
        XCTAssertEqual(try fixture.session("old").state, .running)
        XCTAssertGreaterThan(try XCTUnwrap(fixture.session("old").persisted.lastActivityAt), old)
        // A colored Hook target still triggers cleanup of other historical records.
        try await fixture.model.setMarkerColor("#123456", sessionID: "old")
        let historical = PersistedSession(sessionID: "other-old", discoveredAt: old, lastUpdatedAt: old, rotationIndex: 9)
        // Import another historical record through the public manual sync entry.
        try fixture.writeThreads([CodexThreadSummary(id: historical.id, name: nil, cwd: "/work/qa",
            createdAt: old, updatedAt: old, sourceKind: "cli")])
        fixture.model.syncCodexSessions()
        try await fixture.waitUntil { !fixture.model.isSyncingSessions }
        try await fixture.model.flushSessionWrites()
        try await fixture.model.setMarkerColor("#111111", sessionID: historical.id)
        try await fixture.hook("old", event: .preToolUse)
        XCTAssertNil(try fixture.session(historical.id).persisted.markerColorHex)
        XCTAssertEqual(try fixture.session("old").persisted.markerColorHex, "#123456")
    }

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
        let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 60)
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

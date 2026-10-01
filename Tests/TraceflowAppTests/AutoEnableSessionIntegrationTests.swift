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

    private func withFixture(_ body: (SessionIntegrationFixture) async throws -> Void) async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
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

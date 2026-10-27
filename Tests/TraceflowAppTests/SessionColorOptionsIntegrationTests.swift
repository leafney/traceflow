import AppKit
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class SessionColorOptionsIntegrationTests: XCTestCase {
    func testSavedPresetAndCustomColorAppearWhenReopenedWithoutChangingOtherSession() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        try await fixture.hook("color-a", event: .userPromptSubmit)
        try await fixture.hook("color-b", event: .userPromptSubmit)
        let originalB = try fixture.session("color-b").persisted.markerColorHex
        let bOptions = SessionColorOptions.options(sessionID: "color-b", currentColor: originalB)
        let preset = SessionColorOptions.options(sessionID: "color-a", currentColor: nil)[2].hex
        try await fixture.model.setMarkerColor(preset, sessionID: "color-a")
        var options = SessionColorOptions.options(sessionID: "color-a", currentColor: try fixture.session("color-a").persisted.markerColorHex)
        XCTAssertEqual(options.filter(\.isSelected).map(\.hex), [preset])
        XCTAssertEqual(try fixture.session("color-b").persisted.markerColorHex, originalB)
        XCTAssertEqual(SessionColorOptions.options(sessionID: "color-b", currentColor: originalB), bOptions)

        let panel = NSColorPanel.shared
        let controller = fixture.model.sessionColorPanel
        defer { controller.close() }
        controller.open(sessionID: "color-a")
        let target = try XCTUnwrap(controller.target)
        panel.color = NSColor(srgbRed: 18.0 / 255, green: 52.0 / 255, blue: 86.0 / 255, alpha: 1)
        target.colorChanged(panel)
        try await fixture.model.flushSessionWrites()
        controller.close()
        let restored = AppModel(defaults: fixture.defaults)
        let saved = try XCTUnwrap(restored.sessions.first(where: { $0.id == "color-a" })?.persisted.markerColorHex)
        XCTAssertEqual(saved, "#123456")
        options = SessionColorOptions.options(sessionID: "color-a", currentColor: saved)
        XCTAssertEqual(options.first?.hex, "#123456")
        XCTAssertEqual(options.filter(\.isSelected).map(\.hex), ["#123456"])
        XCTAssertEqual(try fixture.session("color-b").persisted.markerColorHex, originalB)
    }

    func testFailedPresetSaveKeepsPreviousSelection() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        try await fixture.hook("color-a", event: .sessionStart)
        let previous = try XCTUnwrap(fixture.session("color-a").persisted.markerColorHex)
        let before = SessionColorOptions.options(sessionID: "color-a", currentColor: previous)
        let directory = TraceflowPaths.sessions().deletingLastPathComponent()
        let backup = fixture.root.appendingPathComponent("saved-data")
        try FileManager.default.moveItem(at: directory, to: backup)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: backup, to: directory)
        }
        try Data("blocked".utf8).write(to: directory)
        let next = try XCTUnwrap(before.first(where: { !$0.isSelected }))
        await assertAsyncThrows(try await fixture.model.setMarkerColor(next.hex, sessionID: "color-a"))
        let saved = try fixture.session("color-a").persisted.markerColorHex
        XCTAssertEqual(saved, previous)
        XCTAssertEqual(SessionColorOptions.options(sessionID: "color-a", currentColor: saved), before)
        XCTAssertNotNil(fixture.model.markerColorErrorMessage)
    }
}

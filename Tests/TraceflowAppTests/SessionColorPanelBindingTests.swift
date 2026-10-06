import AppKit
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class SessionColorPanelBindingTests: XCTestCase {
    func testPanelKeepsExplicitTargetAndRejectsRetiredActions() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        try await fixture.hook("a", event: .sessionStart)
        try await fixture.hook("b", event: .sessionStart)
        let controller = fixture.model.sessionColorPanel
        defer { controller.close() }
        let originalA = try fixture.session("a").persisted.markerColorHex
        controller.open(sessionID: "a")
        let panel = NSColorPanel.shared
        XCTAssertFalse(panel.showsAlpha)
        XCTAssertEqual(try fixture.session("a").persisted.markerColorHex, originalA, "装载颜色不能触发保存")
        let retiredTarget = try XCTUnwrap(controller.target)
        let retiredAction = #selector(SessionColorPanelTarget.colorChanged(_:))
        controller.open(sessionID: "b")
        panel.color = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        NSApplication.shared.sendAction(retiredAction, to: retiredTarget, from: panel)
        XCTAssertEqual(try fixture.session("a").persisted.markerColorHex, originalA)
        try sendPanelAction(panel, controller: controller)
        XCTAssertEqual(try fixture.session("b").persisted.markerColorHex, "#1A334D")
        controller.close()
        XCTAssertNil(controller.sessionID)
        XCTAssertEqual(try fixture.session("b").persisted.markerColorHex, "#1A334D")
        controller.open(sessionID: "b")
        XCTAssertEqual(SessionMarkerView.nsColor("#1A334D"), panel.color)
        fixture.model.deleteSession("b")
        XCTAssertNil(controller.sessionID)
        XCTAssertFalse(panel.isVisible)
    }

    func testFailedWriteClosesBindingAndRetainsSavedColor() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        try await fixture.hook("a", event: .sessionStart)
        let color = try fixture.session("a").persisted.markerColorHex
        let controller = fixture.model.sessionColorPanel
        defer { controller.close() }
        controller.open(sessionID: "a")
        let directory = TraceflowPaths.sessions().deletingLastPathComponent()
        let backup = fixture.root.appendingPathComponent("saved-data")
        try FileManager.default.moveItem(at: directory, to: backup)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: backup, to: directory)
        }
        try Data("blocked".utf8).write(to: directory)
        let panel = NSColorPanel.shared
        let target = try XCTUnwrap(controller.target)
        panel.color = .orange
        // NSColorPanel may send its action synchronously from the setter.
        // Replay the captured action as well: a closed binding must reject it.
        target.colorChanged(panel)
        XCTAssertNil(controller.sessionID)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(try fixture.session("a").persisted.markerColorHex, color)
        XCTAssertEqual(fixture.model.markerColorErrorMessage, "颜色保存失败，未更改会话颜色")
    }

    func testClosingSettingsEndsColorBinding() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        try await fixture.hook("a", event: .sessionStart)
        try fixture.writeThreads(["a"])
        fixture.model.openSettingsWindow()
        try await fixture.waitUntil { !fixture.model.isDiscoveringRecentSessions }
        fixture.model.sessionColorPanel.open(sessionID: "a")
        let settings = try XCTUnwrap(NSApplication.shared.windows.first {
            $0.title == "Traceflow 设置" && $0.isVisible
        })
        settings.close()
        XCTAssertNil(fixture.model.sessionColorPanel.sessionID)
        XCTAssertFalse(NSColorPanel.shared.isVisible)
    }

    private func sendPanelAction(_ panel: NSColorPanel, controller: SessionColorPanelController) throws {
        let action = #selector(SessionColorPanelTarget.colorChanged(_:))
        let target = try XCTUnwrap(controller.target)
        XCTAssertTrue(NSApplication.shared.sendAction(action, to: target, from: panel))
    }
}

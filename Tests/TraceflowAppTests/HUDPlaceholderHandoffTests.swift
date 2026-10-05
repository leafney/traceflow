import AppKit
import SwiftUI
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class HUDPlaceholderHandoffTests: XCTestCase {
    func testFirstSessionAndReturnToPlaceholderReplaceWindowInEveryLayout() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else { throw XCTSkip("需要桌面屏幕") }
        for layout in HUDLayoutMode.allCases {
            let fixture = try SessionIntegrationFixture()
            defer { fixture.cleanUp() }
            fixture.model.autoEnableNewSessions = true
            fixture.model.hudLayoutMode = layout
            fixture.model.previewTransparency(86)
            let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
            defer { controller.hide() }
            controller.show()
            let original = try XCTUnwrap(controller.window)
            original.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 100,
                                            y: screen.visibleFrame.midY - 100))
            let frame = original.frame
            let store = HUDPositionStore(defaults: fixture.defaults)
            let records = HUDLayoutMode.allCases.map { store.loadResult($0) }
            let placeholder = try hosted(original)
            try await fixture.hook("first", event: .userPromptSubmit)
            try fixture.model.setCustomTitle("-     -     -", sessionID: "first")
            try await fixture.waitUntil { controller.window !== original }
            let sessionPanel = try XCTUnwrap(controller.window)
            assertRetired(original)
            XCTAssertEqual(placeholder.displayedTitle, "Traceflow")
            XCTAssertEqual(try hosted(sessionPanel).displayedTitle, "-     -     -")
            XCTAssertEqual(sessionPanel.frame, frame)
            XCTAssertFalse(fixture.model.shouldAnimateDisplayChange)
            XCTAssertEqual(sessionPanel.animationBehavior, .none)
            XCTAssertEqual(HUDLayoutMode.allCases.map { store.loadResult($0) }, records)

            fixture.model.setIncluded(false, sessionID: "first")
            XCTAssertNil(fixture.model.displayedSession)
            // This synchronous boundary must not put the default title into the
            // old session surface while its replacement is still queued.
            XCTAssertEqual(try hosted(sessionPanel).displayedTitle, "-     -     -")
            try await fixture.waitUntil { controller.window !== sessionPanel }
            assertRetired(sessionPanel)
            let restored = try XCTUnwrap(controller.window)
            XCTAssertEqual(try hosted(restored).displayedTitle, "Traceflow")
            XCTAssertEqual(restored.frame, frame)
            XCTAssertEqual(HUDLayoutMode.allCases.map { store.loadResult($0) }, records)
        }
    }

    func testSessionChangesAndRenamesKeepWindowAndLatestSnapshot() async throws {
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        try await fixture.hook("a", event: .userPromptSubmit)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.window)
        let view = try hosted(panel)
        try await fixture.hook("b", event: .permissionRequest)
        XCTAssertEqual(fixture.model.displayedSession?.id, "b")
        XCTAssertTrue(fixture.model.shouldAnimateDisplayChange)
        XCTAssertEqual(view.presentation.displayedSession?.id, "b")
        try fixture.model.setCustomTitle("Traceflow", sessionID: "b")
        XCTAssertTrue(controller.window === panel)
        XCTAssertEqual(view.displayedTitle, "Traceflow")
        XCTAssertNotNil(view.presentation.displayedSession)
        try await fixture.hook("b", event: .userPromptSubmit)
        XCTAssertTrue(controller.window === panel)
        XCTAssertEqual(view.presentation.displayedSession?.state, fixture.model.displayedSession?.state)
        fixture.model.setIncluded(false, sessionID: "a")
        fixture.model.setIncluded(false, sessionID: "b")
        XCTAssertNil(fixture.model.displayedSession)
        XCTAssertEqual(view.presentation.displayedSession?.id, "b", "退场保留最后显示的 B，而非创建窗口时的 A")
        XCTAssertEqual(view.displayedTitle, "Traceflow")
        try await fixture.waitUntil { controller.window !== panel }
        XCTAssertNil(try hosted(XCTUnwrap(controller.window)).presentation.displayedSession)
    }

    func testLiveViewRemainsDynamicAndPlaceholderWindowDoesNotFollowModel() async throws {
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        let live = HUDView(model: fixture.model)
        let placeholder = HUDWindowPresentation(model: fixture.model, mode: .placeholder)
        XCTAssertEqual(live.displayedTitle, "Traceflow")
        try await fixture.hook("untitled", event: .userPromptSubmit)
        XCTAssertEqual(live.displayedTitle, "未命名会话")
        XCTAssertNil(placeholder.displayedSession)
        try fixture.model.setCustomTitle("-     -     -", sessionID: "untitled")
        XCTAssertEqual(live.displayedTitle, "-     -     -")
        fixture.model.setIncluded(false, sessionID: "untitled")
        XCTAssertEqual(live.displayedTitle, "Traceflow")
    }

    private func hosted(_ window: NSWindow) throws -> HUDView {
        let container = try XCTUnwrap(window.contentView as? HUDDragView)
        let hosts = container.subviews.compactMap { $0 as? NSHostingView<HUDView> }
        XCTAssertEqual(hosts.count, 1)
        return try XCTUnwrap(hosts.first).rootView
    }

    private func assertRetired(_ window: NSWindow, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(window.isVisible, file: file, line: line)
        XCTAssertNil(window.delegate, file: file, line: line)
        XCTAssertNil(window.contentView, file: file, line: line)
    }
}

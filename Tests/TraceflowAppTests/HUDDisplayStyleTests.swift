import AppKit
import SwiftUI
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class HUDDisplayStyleTests: XCTestCase {
    func testStyleReplacementPreservesAnchorsAndSettingsInEveryLayout() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        for layout in HUDLayoutMode.allCases {
            fixture.model.hudLayoutMode = layout
            fixture.model.hudDisplayStyle = .standard
            fixture.model.hudIconVisibilityMode = .alwaysShow
            let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
            controller.show()
            let original = try XCTUnwrap(controller.window)
            let frame = original.frame
            let record = HUDPositionStore(defaults: fixture.defaults).loadResult(layout)
            fixture.model.hudDisplayStyle = .medium
            try await fixture.waitUntil { controller.window !== original }
            let medium = try XCTUnwrap(controller.window)
            XCTAssertEqual(medium.frame.size, layout.isHorizontal ? CGSize(width: 238, height: 40) : CGSize(width: 40, height: 238))
            XCTAssertEqual(HUDBackgroundAppearance.referenceFrame(medium.frame, layout: layout), frame)
            fixture.model.hudDisplayStyle = .compact
            try await fixture.waitUntil { controller.window !== medium }
            let compact = try XCTUnwrap(controller.window)
            XCTAssertEqual(compact.frame.size, layout.isHorizontal ? CGSize(width: 138, height: 40) : CGSize(width: 40, height: 138))
            XCTAssertEqual(HUDBackgroundAppearance.referenceFrame(compact.frame, layout: layout), frame)
            XCTAssertFalse(original.isVisible)
            XCTAssertNil(original.contentView)
            fixture.model.previewTransparency(100)
            fixture.model.hudIconVisibilityMode = .alwaysHide
            fixture.model.isHUDPinned = true
            XCTAssertEqual(compact.frame.size, layout.isHorizontal ? CGSize(width: 138, height: 40) : CGSize(width: 40, height: 138))
            XCTAssertTrue(compact.ignoresMouseEvents)
            fixture.model.hudDisplayStyle = .standard
            try await fixture.waitUntil { controller.window !== compact }
            XCTAssertEqual(controller.window?.frame.size, layout.isHorizontal ? CGSize(width: 380, height: 40) : CGSize(width: 40, height: 380))
            XCTAssertEqual(HUDPositionStore(defaults: fixture.defaults).loadResult(layout), record)
            XCTAssertTrue(controller.window?.ignoresMouseEvents == true)
            controller.hide()
        }
        XCTAssertEqual(AppModel(defaults: fixture.defaults).hudDisplayStyle, .standard)
        fixture.model.hudDisplayStyle = .compact
        XCTAssertEqual(AppModel(defaults: fixture.defaults).hudDisplayStyle, .compact)
    }

    func testDragRapidHiddenAndPlaceholderChangesUseLatestStyle() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.autoEnableNewSessions = true
        let controller = HUDPanelController(model: model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        let original = try XCTUnwrap(controller.window)
        let drag = try XCTUnwrap(original.contentView as? HUDDragView)
        drag.dragStarted?()
        original.setFrameOrigin(CGPoint(x: original.frame.minX - 12, y: original.frame.minY - 12))
        let moved = original.frame
        model.hudDisplayStyle = .compact
        try await fixture.waitUntil { controller.window !== original }
        XCTAssertEqual(controller.window?.frame.maxX, moved.maxX)
        XCTAssertNil(drag.dragFinished)
        for style in [HUDDisplayStyle.standard, .compact, .standard, .compact] { model.hudDisplayStyle = style }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(controller.window?.frame.width, 138)
        let placeholder = try XCTUnwrap(controller.window)
        try await fixture.hook("visible", event: .userPromptSubmit)
        try await fixture.waitUntil { controller.window !== placeholder }
        XCTAssertEqual(controller.window?.frame.size, CGSize(width: 138, height: 40))
        let active = try XCTUnwrap(controller.window)
        model.setIncluded(false, sessionID: "visible")
        try await fixture.waitUntil { controller.window !== active }
        XCTAssertEqual(controller.window?.frame.size, CGSize(width: 138, height: 40))
        controller.hide()
        model.hudDisplayStyle = .standard
        model.hudDisplayStyle = .compact
        model.isHUDPinned = true
        controller.show()
        XCTAssertEqual(controller.window?.frame.width, 138)
        XCTAssertTrue(controller.window?.ignoresMouseEvents == true)
    }
}

import AppKit
import SwiftUI
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class HUDTitleRenderingTests: XCTestCase {
    func testProductionPanelClearsDefaultAndEditedTitlePixels() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("无桌面屏幕，不能验证生产透明浮窗") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        fixture.model.hudLayoutMode = .horizontalLeft
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        try await Task.sleep(nanoseconds: 300_000_000)
        for name in ["123------", "一段明显更长的标题用于检查旧字形", "Q", "Traceflow"] {
            try await fixture.hook("live-title", event: .userPromptSubmit)
            try fixture.model.setCustomTitle(name, sessionID: "live-title")
            try await assertProductionTitleMatchesFreshPanel(controller, fixture: fixture)
            try await fixture.hook("live-title", event: .interrupt)
            XCTAssertNil(fixture.model.displayedSession)
            try await assertProductionTitleMatchesFreshPanel(controller, fixture: fixture)
        }
    }

    private func assertProductionTitleMatchesFreshPanel(_ controller: HUDPanelController,
                                                        fixture: SessionIntegrationFixture) async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
        let actual = try captureTitle(controller)
        // A second production panel is only a reference. Never replace the tested
        // panel's hosting view, background, or native backing store.
        let reference = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { reference.hide() }
        reference.show()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(actual, try captureTitle(reference), "生产承载视图中不应残留默认名称或旧标题")
    }

    private func captureTitle(_ controller: HUDPanelController) throws -> Data {
        let container = try XCTUnwrap(controller.window?.contentView)
        let hosting = try XCTUnwrap(container.subviews.first { $0 is NSHostingView<HUDView> })
        hosting.layoutSubtreeIfNeeded()
        let layout = (hosting as! NSHostingView<HUDView>).rootView.model.hudLayoutMode
        let origin: CGFloat = layout.lightsAtLeadingEdge ? 104 : 40
        let rect = layout.isHorizontal
            ? NSRect(x: origin, y: 0, width: 275, height: 40)
            : NSRect(x: 0, y: hosting.isFlipped ? origin : hosting.bounds.height - origin - 275,
                     width: 40, height: 275)
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: rect))
        hosting.cacheDisplay(in: rect, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    func testPlaceholderAndSessionTitlesRemainExclusiveAfterRepeatedSwitches() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        XCTAssertEqual(HUDView(model: fixture.model).displayedTitle, "Traceflow")
        for layout in HUDLayoutMode.allCases {
            fixture.model.hudLayoutMode = layout
            let renderer = ImageRenderer(content: HUDView(model: fixture.model))
            for _ in 0..<2 {
                try await fixture.hook("title", event: .userPromptSubmit)
                try fixture.model.setCustomTitle("提示显示逻辑", sessionID: "title")
                XCTAssertNotNil(fixture.model.displayedSession)
                let session = try XCTUnwrap(fixture.model.displayedSession)
                XCTAssertEqual(session.persisted.projectName, "qa")
                XCTAssertEqual(HUDView(model: fixture.model).displayedTitle, session.sessionListTitle)
                XCTAssertEqual(HUDView(model: fixture.model).displayedTitle, "提示显示逻辑")
                XCTAssertNotEqual(HUDView(model: fixture.model).displayedTitle, session.displayTitle,
                                  "有会话时不能使用带项目名称的拼接标题")
                try await assertTitleMatchesFreshView(renderer, model: fixture.model, layout: layout)
                try await fixture.hook("title", event: .interrupt)
                XCTAssertNil(fixture.model.displayedSession)
                XCTAssertEqual(HUDView(model: fixture.model).displayedTitle, "Traceflow")
                try await assertTitleMatchesFreshView(renderer, model: fixture.model, layout: layout)
            }
        }
    }

    private func assertTitleMatchesFreshView(_ renderer: ImageRenderer<HUDView>, model: AppModel,
                                             layout: HUDLayoutMode) async throws {
        // Let SwiftUI publish and finish the maximum 0.2-second insertion.
        try await Task.sleep(nanoseconds: 300_000_000)
        let actual = try XCTUnwrap(renderer.cgImage)
        let expected = try XCTUnwrap(ImageRenderer(content: HUDView(model: model)).cgImage)
        // Compare only the title region so live light animation cannot affect results.
        let origin: CGFloat = layout.lightsAtLeadingEdge ? 104 : 40
        let rect = layout.isHorizontal
            ? CGRect(x: origin, y: 0, width: 275, height: 40)
            : CGRect(x: 0, y: origin, width: 40, height: 275)
        let actualTitle = try XCTUnwrap(actual.cropping(to: rect))
        let expectedTitle = try XCTUnwrap(expected.cropping(to: rect))
        XCTAssertEqual(try XCTUnwrap(actualTitle.dataProvider?.data) as Data,
                       try XCTUnwrap(expectedTitle.dataProvider?.data) as Data,
                       "旧默认标题或旧会话标题不应残留在当前标题下面")
    }
}

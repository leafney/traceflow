import AppKit
import SwiftUI
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class HUDTitleRenderingTests: XCTestCase {
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

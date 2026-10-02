import AppKit
import SwiftUI
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class HUDTitleRenderingTests: XCTestCase {
    func testHostedModelUsesDefaultAndEditedSessionTitles() async throws {
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
            XCTAssertFalse(fixture.model.shouldAnimateDisplayChange)
            try fixture.model.setCustomTitle(name, sessionID: "live-title")
            try await assertCurrentHostedTitle(controller, fixture: fixture)
            try await fixture.hook("live-title", event: .interrupt)
            XCTAssertNil(fixture.model.displayedSession)
            XCTAssertFalse(fixture.model.shouldAnimateDisplayChange)
            try await assertCurrentHostedTitle(controller, fixture: fixture)
        }
    }

    func testInterruptedSessionChangesPublishLatestHostedTitleInEveryLayout() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("无桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        for layout in HUDLayoutMode.allCases {
            fixture.model.hudLayoutMode = layout
            for transparency in [10.0, 100.0] {
                fixture.model.previewTransparency(transparency)
                let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
                controller.show()
                try await fixture.hook("a", event: .userPromptSubmit)
                XCTAssertEqual(fixture.model.displayedSession?.id, "a")
                try fixture.model.setCustomTitle("123------", sessionID: "a")
                try await Task.sleep(nanoseconds: 300_000_000)
                try await fixture.hook("b", event: .permissionRequest)
                XCTAssertEqual(fixture.model.displayedSession?.id, "b")
                XCTAssertTrue(fixture.model.shouldAnimateDisplayChange, "必须经过真实会话切换动画入口")
                // Queue C behind red B, then remove B before its transition ends.
                try await fixture.hook("c", event: .permissionRequest)
                fixture.model.setIncluded(false, sessionID: "b")
                XCTAssertEqual(fixture.model.displayedSession?.id, "c")
                XCTAssertTrue(fixture.model.shouldAnimateDisplayChange)
                try fixture.model.setCustomTitle("Q", sessionID: "c")
                try await assertCurrentHostedTitle(controller, fixture: fixture)
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try await assertCurrentHostedTitle(controller, fixture: fixture)
                for id in ["a", "b", "c"] { fixture.model.setIncluded(false, sessionID: id) }
                XCTAssertNil(fixture.model.displayedSession)
                try await assertCurrentHostedTitle(controller, fixture: fixture)
                controller.hide()
                // Re-include only idle sessions to start the next case at default.
                for id in ["a", "b", "c"] {
                    try await fixture.hook(id, event: .interrupt)
                    fixture.model.setIncluded(true, sessionID: id)
                }
            }
        }
    }

    func testScreenTitlesAfterLayoutInterruptAndDefaultBoundaries() async throws {
        _ = NSApplication.shared
        for color in [NSColor.white, .darkGray] {
            let screen = try HUDScreenFixture(color: color)
            defer { screen.close() }
            let fixture = try SessionIntegrationFixture()
            defer { fixture.cleanUp() }
            fixture.model.autoEnableNewSessions = true
            fixture.model.hudTitleColor = color == .white ? .black : .white
            fixture.model.previewTransparency(86)
            let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
            defer { controller.hide() }
            controller.show()
            for layout in HUDLayoutMode.allCases {
                fixture.model.hudLayoutMode = layout
                try await Task.sleep(nanoseconds: 50_000_000)
                try await fixture.hook("screen-a", event: .userPromptSubmit)
                try fixture.model.setCustomTitle("首个会话", sessionID: "screen-a")
                XCTAssertFalse(fixture.model.shouldAnimateDisplayChange)
                try await screen.assertSettled(controller, fixture: fixture,
                                               regions: [screenTitleRegion(layout)], compareFull: false)
                try await fixture.hook("screen-b", event: .permissionRequest)
                XCTAssertTrue(fixture.model.shouldAnimateDisplayChange)
                // Replace the hosting tree while the title transition is active.
                fixture.model.hudLayoutMode = layout == .horizontalLeft ? .horizontalRight : .horizontalLeft
                await Task.yield()
                try await screen.assertSettled(controller, fixture: fixture,
                                               regions: [screenTitleRegion(fixture.model.hudLayoutMode)],
                                               compareFull: false)
                for id in ["screen-a", "screen-b"] { fixture.model.setIncluded(false, sessionID: id) }
                XCTAssertNil(fixture.model.displayedSession)
                XCTAssertFalse(fixture.model.shouldAnimateDisplayChange)
                try await screen.assertSettled(controller, fixture: fixture)
                for id in ["screen-a", "screen-b"] {
                    try await fixture.hook(id, event: .interrupt)
                    fixture.model.setIncluded(true, sessionID: id)
                }
            }
        }
    }

    private func screenTitleRegion(_ layout: HUDLayoutMode) -> NSRect {
        let offset: CGFloat = layout.lightsAtLeadingEdge ? 104 : 0
        return layout.isHorizontal
            ? NSRect(x: offset + 7, y: 2, width: 260, height: 36)
            : NSRect(x: 2, y: offset + 7, width: 36, height: 260)
    }

    func testScreenAnimationUsesOnlySamplesCapturedInsideTransition() async throws {
        _ = NSApplication.shared
        let screen = try HUDScreenFixture(color: .white)
        defer { screen.close() }
        for layout in [HUDLayoutMode.horizontalLeft, .verticalTop] {
            var verified = false
            for _ in 0..<3 {
                let fixture = try SessionIntegrationFixture()
                defer { fixture.cleanUp() }
                fixture.model.autoEnableNewSessions = true
                fixture.model.hudLayoutMode = layout
                fixture.model.hudTitleColor = .black
                fixture.model.previewTransparency(100)
                let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
                defer { controller.hide() }
                controller.show()
                let panel = try XCTUnwrap(controller.window)
                screen.place(panel)
                try await fixture.hook("animation-a", event: .userPromptSubmit)
                try fixture.model.setCustomTitle("MMMMMM", sessionID: "animation-a")
                try await fixture.hook("animation-b", event: .userPromptSubmit)
                try fixture.model.setCustomTitle("MMMMMM", sessionID: "animation-b")
                try await Task.sleep(nanoseconds: 300_000_000)
                let before = try await screen.capture(panel, fixture: fixture)
                let began = ProcessInfo.processInfo.systemUptime
                try await fixture.hook("animation-b", event: .permissionRequest)
                XCTAssertTrue(fixture.model.shouldAnimateDisplayChange)
                try await Task.sleep(nanoseconds: 20_000_000)
                let sampleStart = ProcessInfo.processInfo.systemUptime - began
                let middle = try await screen.capture(panel, fixture: fixture)
                let sampleEnd = ProcessInfo.processInfo.systemUptime - began
                // Process launch cannot be assumed instantaneous. The whole capture
                // interval must be inside the product transition, or retry it.
                let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    ? 0.15 : HUDTitleTransition.maximumDuration
                guard sampleStart > 0, sampleEnd < duration else { continue }
                try await Task.sleep(nanoseconds: 300_000_000)
                let settled = try await screen.capture(panel, fixture: fixture)
                let title = screenTitleRegion(layout)
                before.assertSimilar(to: settled, points: panel.frame.size, regions: [title], compareFull: false)
                XCTAssertGreaterThan(middle.changedFraction(comparedTo: settled, points: panel.frame.size,
                                                           region: title), 0.005,
                                     "已确认采样位于动画内，相同标题应有位移或透明度变化")
                verified = true
                break
            }
            if !verified {
                throw XCTSkip("三次采样均未落在零点二秒动画内：采样不足，动画方向与观感待人工验收")
            }
        }
    }

    func testAuxiliaryOffscreenUntitledAndLiteralDefaultTitles() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        for layout in HUDLayoutMode.allCases {
            fixture.model.hudLayoutMode = layout
            let renderer = ImageRenderer(content: HUDView(model: fixture.model))
            try await fixture.hook("untitled", event: .userPromptSubmit)
            XCTAssertEqual(HUDView(model: fixture.model).displayedTitle, "未命名会话")
            for title in ["Traceflow", "较长的标题需要在变短后擦除", "Q"] {
                try fixture.model.setCustomTitle(title, sessionID: "untitled")
                XCTAssertEqual(HUDView(model: fixture.model).displayedTitle, title)
                try await Task.sleep(nanoseconds: 300_000_000)
                let expected = ImageRenderer(content: HUDView(model: fixture.model))
                try assertTitlePixelsEqual(renderer.cgImage, expected.cgImage, layout: layout)
            }
            try await fixture.hook("untitled", event: .interrupt)
            try fixture.model.resetCustomTitle(sessionID: "untitled")
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertEqual(HUDView(model: fixture.model).displayedTitle, "Traceflow")
            let expected = ImageRenderer(content: HUDView(model: fixture.model))
            try assertTitlePixelsEqual(renderer.cgImage, expected.cgImage, layout: layout)
        }
    }

    func testSamePanelLayoutChangesDuringSessionTransitionsKeepCurrentTitle() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        fixture.model.hudLayoutMode = .horizontalLeft
        fixture.model.previewTransparency(86)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        let window = try XCTUnwrap(controller.window)
        let container = try XCTUnwrap(window.contentView)
        var hosting = try XCTUnwrap(container.subviews.first { $0 is NSHostingView<HUDView> })
        for layout in [HUDLayoutMode.horizontalRight, .verticalTop, .verticalBottom, .horizontalLeft] {
            let previousHosting = hosting
            try await fixture.hook("layout-a", event: .userPromptSubmit)
            try fixture.model.setCustomTitle("123------", sessionID: "layout-a")
            try await Task.sleep(nanoseconds: 300_000_000)
            try await fixture.hook("layout-b", event: .userPromptSubmit)
            try fixture.model.setCustomTitle("Q", sessionID: "layout-b")
            try await fixture.hook("layout-b", event: .permissionRequest)
            XCTAssertEqual(fixture.model.displayedSession?.id, "layout-b")
            XCTAssertTrue(fixture.model.shouldAnimateDisplayChange)
            // Use the live observer while the 0.20-second session transition is in flight.
            fixture.model.hudLayoutMode = layout
            try await assertCurrentHostedTitle(controller, fixture: fixture)
            XCTAssertTrue(controller.window === window)
            XCTAssertTrue(window.contentView === container)
            hosting = try XCTUnwrap(container.subviews.first { $0 is NSHostingView<HUDView> })
            XCTAssertFalse(hosting === previousHosting)
            XCTAssertNil(previousHosting.superview)
            XCTAssertEqual(HUDView(model: fixture.model).displayedTitle, "Q")
            try await fixture.hook("layout-c", event: .permissionRequest)
            try fixture.model.setCustomTitle("Traceflow", sessionID: "layout-c")
            fixture.model.setIncluded(false, sessionID: "layout-b")
            XCTAssertEqual(fixture.model.displayedSession?.id, "layout-c")
            XCTAssertTrue(fixture.model.shouldAnimateDisplayChange, "布局切换后继续保留会话动画决策")
            try await assertCurrentHostedTitle(controller, fixture: fixture)
            for id in ["layout-a", "layout-b", "layout-c"] {
                fixture.model.setIncluded(false, sessionID: id)
            }
            XCTAssertNil(fixture.model.displayedSession)
            try await assertCurrentHostedTitle(controller, fixture: fixture)
            for id in ["layout-a", "layout-b", "layout-c"] {
                try await fixture.hook(id, event: .interrupt)
                fixture.model.setIncluded(true, sessionID: id)
            }
        }
    }

    private func assertCurrentHostedTitle(_ controller: HUDPanelController,
                                          fixture: SessionIntegrationFixture) async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
        let container = try XCTUnwrap(controller.window?.contentView)
        let hosts = container.subviews.compactMap { $0 as? NSHostingView<HUDView> }
        XCTAssertEqual(hosts.count, 1)
        let hosting = try XCTUnwrap(hosts.first)
        XCTAssertTrue(hosting.rootView.model === fixture.model)
        XCTAssertEqual(hosting.rootView.displayedTitle,
                       fixture.model.displayedSession?.sessionListTitle ?? "Traceflow")
    }

    func testAuxiliaryOffscreenPlaceholderAndSessionTitles() async throws {
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
        try assertTitlePixelsEqual(renderer.cgImage,
                                   ImageRenderer(content: HUDView(model: model)).cgImage, layout: layout)
    }

    private func assertTitlePixelsEqual(_ actualImage: CGImage?, _ expectedImage: CGImage?,
                                       layout: HUDLayoutMode) throws {
        let actual = try XCTUnwrap(actualImage)
        let expected = try XCTUnwrap(expectedImage)
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

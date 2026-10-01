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

    func testProductionPanelClearsInterruptedTransitionsInEveryLayout() async throws {
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
                try await assertProductionTitleMatchesFreshPanel(controller, fixture: fixture)
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try await assertProductionTitleMatchesFreshPanel(controller, fixture: fixture)
                for id in ["a", "b", "c"] { fixture.model.setIncluded(false, sessionID: id) }
                XCTAssertNil(fixture.model.displayedSession)
                try await assertProductionTitleMatchesFreshPanel(controller, fixture: fixture)
                controller.hide()
                // Re-include only idle sessions to start the next case at default.
                for id in ["a", "b", "c"] {
                    try await fixture.hook(id, event: .interrupt)
                    fixture.model.setIncluded(true, sessionID: id)
                }
            }
        }
    }

    func testScreenCompositePreservesSlideAndClearsDefault() async throws {
        _ = NSApplication.shared
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("缺少屏幕录制权限：屏幕合成与动画中间帧待人工验收；原生绘制测试不能替代")
        }
        let screen = try XCTUnwrap(NSScreen.main)
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        fixture.model.hudTitleColor = .black
        fixture.model.previewTransparency(100)
        let backdrop = NSWindow(contentRect: NSRect(x: screen.frame.midX - 250, y: screen.frame.midY - 250,
                                                    width: 500, height: 500),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.level = .floating
        defer { backdrop.orderOut(nil) }
        for layout in HUDLayoutMode.allCases {
            fixture.model.hudLayoutMode = layout
            let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
            defer { controller.hide() }
            controller.show()
            let panel = try XCTUnwrap(controller.window)
            panel.setFrameOrigin(NSPoint(x: backdrop.frame.minX + 40, y: backdrop.frame.minY + 40))
            for color in [NSColor.white, NSColor.darkGray] {
                backdrop.backgroundColor = color
                backdrop.orderFrontRegardless()
                panel.orderFrontRegardless()
                try await fixture.hook("screen-a", event: .userPromptSubmit)
                try fixture.model.setCustomTitle("MMMMMM", sessionID: "screen-a")
                try await Task.sleep(nanoseconds: 300_000_000)
                let before = try await captureScreenTitle(panel, layout: layout, fixture: fixture)
                try await fixture.hook("screen-b", event: .userPromptSubmit)
                try fixture.model.setCustomTitle("MMMMMM", sessionID: "screen-b")
                try await fixture.hook("screen-b", event: .permissionRequest)
                XCTAssertEqual(fixture.model.displayedSession?.id, "screen-b")
                XCTAssertTrue(fixture.model.shouldAnimateDisplayChange)
                try await Task.sleep(nanoseconds: 30_000_000)
                let middle = try await captureScreenTitle(panel, layout: layout, fixture: fixture)
                try await Task.sleep(nanoseconds: 300_000_000)
                let settled = try await captureScreenTitle(panel, layout: layout, fixture: fixture)
                // Same text on both sessions: only movement/opacity can change
                // the ink distribution, rather than different title glyphs.
                XCTAssertNotEqual(inkDistribution(middle, vertical: !layout.isHorizontal),
                                  inkDistribution(settled, vertical: !layout.isHorizontal),
                                  "会话切换必须保留可见的位移或透明度中间帧")
                XCTAssertEqual(before, settled, "动画结束后只能保留当前标题")
                for id in ["screen-a", "screen-b"] { fixture.model.setIncluded(false, sessionID: id) }
                try await Task.sleep(nanoseconds: 1_000_000_000)
                let defaultFrame = try await captureScreenTitle(panel, layout: layout, fixture: fixture)
                let reference = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
                reference.show()
                let referencePanel = try XCTUnwrap(reference.window)
                referencePanel.setFrameOrigin(panel.frame.origin)
                try await Task.sleep(nanoseconds: 300_000_000)
                let expectedDefault = try await captureScreenTitle(referencePanel, layout: layout, fixture: fixture)
                XCTAssertEqual(defaultFrame, expectedDefault)
                reference.hide()
                for id in ["screen-a", "screen-b"] {
                    try await fixture.hook(id, event: .interrupt)
                    fixture.model.setIncluded(true, sessionID: id)
                }
            }
            controller.hide()
        }
    }

    private func captureScreenTitle(_ panel: NSWindow, layout: HUDLayoutMode,
                                    fixture: SessionIntegrationFixture) async throws -> Data {
        let primary = try XCTUnwrap(NSScreen.screens.first)
        let frame = panel.frame
        let file = fixture.root.appendingPathComponent(UUID().uuidString + ".png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R\(Int(frame.minX)),\(Int(primary.frame.maxY - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))", file.path]
        try process.run()
        try await fixture.waitUntil { !process.isRunning }
        XCTAssertEqual(process.terminationStatus, 0)
        let image = try XCTUnwrap(NSImage(contentsOf: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let scale = CGFloat(image.width) / frame.width
        let origin: CGFloat = layout.lightsAtLeadingEdge ? 104 : 0
        // At 100% transparency the icon is collapsed; exclude capsule borders.
        let rect = layout.isHorizontal
            ? CGRect(x: (origin + 7) * scale, y: 2 * scale, width: 260 * scale, height: 36 * scale)
            : CGRect(x: 2 * scale, y: (origin + 7) * scale, width: 36 * scale, height: 260 * scale)
        let title = try XCTUnwrap(image.cropping(to: rect))
        let bitmap = NSBitmapImageRep(cgImage: title)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func inkDistribution(_ png: Data, vertical: Bool) -> [Int] {
        guard let bitmap = NSBitmapImageRep(data: png) else { return [] }
        var distribution = Array(repeating: 0, count: vertical ? bitmap.pixelsWide : bitmap.pixelsHigh)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                distribution[vertical ? x : y] += Int((1 - color.redComponent) * 255)
            }
        }
        return distribution
    }

    func testUntitledSessionAndLiteralDefaultNameKeepExclusiveContent() async throws {
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
        let model = try XCTUnwrap((hosting as? NSHostingView<HUDView>)?.rootView.model)
        let layout = model.hudLayoutMode
        let origin: CGFloat = layout.lightsAtLeadingEdge ? 104 : 40 * model.hudIconFraction
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

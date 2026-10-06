import AppKit
import SwiftUI
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class HUDLayoutControllerTests: XCTestCase {
    func testIconModeReversalStartsAtCurrentVisibleStateAndLatestChoiceWins() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.previewTransparency(0)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        let panel = try XCTUnwrap(controller.window)
        fixture.model.hudIconVisibilityMode = .alwaysHide
        try await Task.sleep(nanoseconds: 100_000_000)
        let fraction = fixture.model.hudIconFraction
        let frame = panel.frame
        fixture.model.hudIconVisibilityMode = .alwaysShow
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertEqual(panel.frame, frame, "反向过渡不能跳到旧动画终态")
            XCTAssertEqual(fixture.model.hudIconFraction, fraction)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(panel.frame.size, CGSize(width: 420, height: 40))
        XCTAssertEqual(fixture.model.hudIconFraction, 1)
        fixture.model.hudIconVisibilityMode = .automatic
        XCTAssertEqual(panel.frame.size, CGSize(width: 420, height: 40))
        XCTAssertEqual(fixture.model.hudIconFraction, 1)
        for mode in [HUDIconVisibilityMode.alwaysHide, .alwaysShow, .automatic, .alwaysHide] {
            fixture.model.hudIconVisibilityMode = mode
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(controller.window === panel)
        XCTAssertEqual(panel.frame.size, CGSize(width: 380, height: 40))
        XCTAssertEqual(fixture.model.hudIconFraction, 0)
        XCTAssertEqual(HUDPreferences(defaults: fixture.defaults).loadIconVisibilityMode(), .alwaysHide)
    }

    func testIconModeDuringDragDefersSizeAndPersistsOnlyNormalDrag() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.previewTransparency(0)
        for layout in HUDLayoutMode.allCases {
            fixture.model.hudLayoutMode = layout
            fixture.model.hudIconVisibilityMode = .alwaysShow
            let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
            controller.show()
            let panel = try XCTUnwrap(controller.window)
            let parts = try contentParts(panel)
            let store = HUDPositionStore(defaults: fixture.defaults)
            let saved = store.loadResult(layout)
            parts.container.dragStarted?()
            panel.setFrameOrigin(CGPoint(x: panel.frame.minX + 10, y: panel.frame.minY - 10))
            let dragged = panel.frame
            for mode in [HUDIconVisibilityMode.alwaysHide, .alwaysShow, .alwaysHide] {
                fixture.model.hudIconVisibilityMode = mode
                XCTAssertEqual(panel.frame, dragged)
                XCTAssertEqual(fixture.model.hudIconFraction, 1)
                XCTAssertEqual(store.loadResult(layout), saved)
            }
            XCTAssertEqual(HUDPreferences(defaults: fixture.defaults).loadIconVisibilityMode(), .alwaysHide)
            parts.container.dragFinished?(true)
            let committed = store.loadResult(layout)
            XCTAssertNotEqual(committed, saved, "正常拖动依然保存位置")
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertEqual(panel.frame.size, layout.isHorizontal ? CGSize(width: 380, height: 40) : CGSize(width: 40, height: 380))
            XCTAssertEqual(fixture.model.hudIconFraction, 0)
            XCTAssertEqual(store.loadResult(layout), committed, "尺寸动画不覆盖已保存的拖动位置")
            controller.hide()
        }
    }

    func testHiddenAndPinnedHUDKeepsLatestIconModeWhenShown() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.previewTransparency(100)
        fixture.model.isHUDPinned = true
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.window)
        for mode in [HUDIconVisibilityMode.alwaysShow, .alwaysHide, .alwaysShow] {
            controller.hide()
            fixture.model.hudIconVisibilityMode = mode
            XCTAssertFalse(panel.isVisible)
            controller.show()
            XCTAssertTrue(panel.isVisible)
            XCTAssertTrue(panel.ignoresMouseEvents)
            XCTAssertEqual(panel.frame.width, mode == .alwaysShow ? 420 : 380)
            XCTAssertEqual(fixture.model.hudIconFraction, mode == .alwaysShow ? 1 : 0)
        }
    }

    func testEveryIconModeSurvivesLayoutAndSessionWindowReplacement() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        for (mode, transparency, fraction) in [
            (HUDIconVisibilityMode.alwaysShow, 100.0, 1.0), (.alwaysHide, 0, 0.0),
            (.automatic, 79, 1.0), (.automatic, 80, 0.0)
        ] {
            fixture.model.previewTransparency(transparency)
            fixture.model.hudIconVisibilityMode = mode
            try await Task.sleep(nanoseconds: 300_000_000)
            for layout in HUDLayoutMode.allCases {
                fixture.model.hudLayoutMode = layout
                controller.switchLayout(to: layout)
                let placeholder = try XCTUnwrap(controller.window)
                let expectedSize = layout.isHorizontal
                    ? CGSize(width: fraction == 1 ? 420 : 380, height: 40)
                    : CGSize(width: 40, height: fraction == 1 ? 420 : 380)
                XCTAssertEqual(placeholder.frame.size, expectedSize)
                XCTAssertEqual(fixture.model.hudIconFraction, fraction)
                let records = HUDLayoutMode.allCases.map { HUDPositionStore(defaults: fixture.defaults).loadResult($0) }
                let id = mode.rawValue + "-" + String(Int(transparency)) + "-" + layout.rawValue
                try await fixture.hook(id, event: .userPromptSubmit)
                try await fixture.waitUntil { controller.window !== placeholder }
                let sessionPanel = try XCTUnwrap(controller.window)
                assertRetired(placeholder)
                XCTAssertEqual(sessionPanel.frame, placeholder.frame)
                XCTAssertEqual(sessionPanel.frame.size, expectedSize)
                XCTAssertEqual(fixture.model.hudIconFraction, fraction)
                XCTAssertFalse(sessionPanel.hasShadow)
                fixture.model.setIncluded(false, sessionID: id)
                try await fixture.waitUntil { controller.window !== sessionPanel }
                let restored = try XCTUnwrap(controller.window)
                assertRetired(sessionPanel)
                XCTAssertEqual(restored.frame.size, expectedSize)
                XCTAssertEqual(fixture.model.hudIconFraction, fraction)
                XCTAssertEqual(fixture.model.hudIconVisibilityMode, mode)
                XCTAssertEqual(HUDLayoutMode.allCases.map { HUDPositionStore(defaults: fixture.defaults).loadResult($0) }, records)
            }
        }
    }

    func testIconTransitionInterruptedByLayoutAndSessionUsesLatestTarget() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.previewTransparency(0)
        fixture.model.autoEnableNewSessions = true
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        fixture.model.hudIconVisibilityMode = .alwaysHide
        fixture.model.hudLayoutMode = .verticalTop
        controller.switchLayout(to: .verticalTop)
        XCTAssertEqual(controller.window?.frame.size, CGSize(width: 40, height: 380))
        XCTAssertEqual(fixture.model.hudIconFraction, 0)
        fixture.model.hudIconVisibilityMode = .alwaysShow
        let placeholder = try XCTUnwrap(controller.window)
        try await fixture.hook("transition", event: .userPromptSubmit)
        try await fixture.waitUntil { controller.window !== placeholder }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(controller.window?.frame.size, CGSize(width: 40, height: 420))
        XCTAssertEqual(fixture.model.hudIconFraction, 1)
        fixture.model.hudIconVisibilityMode = .alwaysHide
        fixture.model.setIncluded(false, sessionID: "transition")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(fixture.model.displayedSession)
        XCTAssertEqual(controller.window?.frame.size, CGSize(width: 40, height: 380))
        XCTAssertEqual(fixture.model.hudIconFraction, 0)
    }

    func testScreenCompositeForIconModesAndRapidLayoutChanges() async throws {
        _ = NSApplication.shared
        let screen = try HUDScreenFixture(color: .white)
        defer { screen.close() }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        try screen.preparePositions(defaults: fixture.defaults)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        for layout in HUDLayoutMode.allCases {
            fixture.model.hudLayoutMode = layout
            controller.switchLayout(to: layout)
            for (mode, transparency) in [(HUDIconVisibilityMode.automatic, 79.0), (.automatic, 80), (.alwaysShow, 100), (.alwaysHide, 0)] {
                fixture.model.previewTransparency(transparency)
                fixture.model.hudIconVisibilityMode = mode
                try await screen.assertSettled(controller, fixture: fixture)
            }
        }
        for layout in HUDLayoutMode.allCases {
            fixture.model.hudIconVisibilityMode = .alwaysShow
            fixture.model.hudLayoutMode = layout
            fixture.model.hudIconVisibilityMode = .alwaysHide
        }
        try await screen.assertSettled(controller, fixture: fixture)
    }

    func testInitialIconModeOverridesTransparencyAndPersistsWithoutJumpingAnimation() throws {
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        for (mode, transparency, fraction) in [
            (HUDIconVisibilityMode.alwaysShow, 100, 1.0), (.alwaysHide, 0, 0.0),
            (.automatic, 79, 1.0), (.automatic, 80, 0.0)
        ] {
            fixture.defaults.set(mode.rawValue, forKey: HUDPreferences.iconVisibilityKey)
            fixture.defaults.set(transparency, forKey: HUDPreferences.transparencyKey)
            let model = AppModel(defaults: fixture.defaults)
            XCTAssertEqual(model.hudIconVisibilityMode, mode)
            XCTAssertEqual(model.hudIconFraction, fraction)
            model.hudIconVisibilityMode = mode == .alwaysShow ? .alwaysHide : .alwaysShow
            XCTAssertEqual(model.hudIconFraction, fraction, "模型只保存模式，不能抢先改变动画比例")
            XCTAssertEqual(HUDPreferences(defaults: fixture.defaults).loadIconVisibilityMode(), model.hudIconVisibilityMode)
        }
    }

    func testIconModeUpdatesSameWindowAndKeepsBackgroundAndSavedPositionsInEveryLayout() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        let store = HUDPositionStore(defaults: fixture.defaults)
        for layout in HUDLayoutMode.allCases {
            fixture.model.hudLayoutMode = layout
            fixture.model.hudIconVisibilityMode = .automatic
            fixture.model.previewTransparency(100)
            let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
            controller.show()
            let panel = try XCTUnwrap(controller.window)
            let records = HUDLayoutMode.allCases.map { store.loadResult($0) }
            fixture.model.hudIconVisibilityMode = .alwaysShow
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertTrue(controller.window === panel)
            XCTAssertEqual(panel.frame.size, layout.isHorizontal ? CGSize(width: 420, height: 40) : CGSize(width: 40, height: 420))
            XCTAssertEqual(fixture.model.hudIconFraction, 1)
            XCTAssertEqual(try contentParts(panel).background.alphaValue, 0)
            fixture.model.previewTransparency(0)
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertEqual(fixture.model.hudIconFraction, 1)
            XCTAssertEqual(try contentParts(panel).background.alphaValue, 1)
            fixture.model.hudIconVisibilityMode = .alwaysHide
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertTrue(controller.window === panel)
            XCTAssertEqual(panel.frame.size, layout.isHorizontal ? CGSize(width: 380, height: 40) : CGSize(width: 40, height: 380))
            XCTAssertEqual(fixture.model.hudIconFraction, 0)
            XCTAssertFalse(panel.hasShadow)
            fixture.model.hudIconVisibilityMode = .automatic
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertEqual(fixture.model.hudIconFraction, 1)
            XCTAssertEqual(HUDLayoutMode.allCases.map { store.loadResult($0) }, records)
            controller.hide()
        }
    }

    func testPendingLayoutKeepsOldHostedGeometryUntilPanelReplacement() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.hudLayoutMode = .horizontalLeft
        fixture.model.previewTransparency(86)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        for target in [HUDLayoutMode.horizontalRight, .verticalTop, .verticalBottom, .horizontalLeft] {
            let oldPanel = try XCTUnwrap(controller.window)
            let oldHosting = try contentParts(oldPanel).hosting
            let previousLayout = oldHosting.rootView.layout
            let oldRenderer = ImageRenderer(content: oldHosting.rootView)
            let previousImage = try XCTUnwrap(oldRenderer.cgImage)
            XCTAssertEqual(oldPanel.animationBehavior, .none)

            fixture.model.hudLayoutMode = target
            // No yield: the model has changed but the queued replacement has
            // not run. This is the gap that settled-frame tests did not cover.
            XCTAssertTrue(controller.window === oldPanel)
            XCTAssertEqual(oldHosting.rootView.layout, previousLayout)
            let pending = try XCTUnwrap(ImageRenderer(content: oldHosting.rootView).cgImage)
            let previousPixels = try HUDScreenPixels(image: previousImage)
            let pendingPixels = try HUDScreenPixels(image: pending)
            XCTAssertEqual(pendingPixels.width, previousPixels.width)
            XCTAssertEqual(pendingPixels.height, previousPixels.height)
            XCTAssertEqual(pendingPixels.bytes, previousPixels.bytes,
                           "旧承载在交接前不能先绘制目标布局")

            controller.switchLayout(to: target)
            let current = try XCTUnwrap(controller.window)
            XCTAssertFalse(current === oldPanel)
            assertRetired(oldPanel)
            XCTAssertEqual(try contentParts(current).hosting.rootView.layout, target)
            XCTAssertEqual(current.animationBehavior, .none)
            XCTAssertEqual(current.frame.size, HUDBackgroundAppearance(86).size(target))
            await Task.yield()
            XCTAssertTrue(controller.window === current, "迟到观察回调不能再次替换窗口")
        }
    }

    func testPanelReplacementSwitchesLeftRightAndBackThroughObserver() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.hudLayoutMode = .horizontalLeft
        fixture.model.hudTitleColor = .white
        fixture.model.previewTransparency(86)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        var window = try XCTUnwrap(controller.window)
        var parts = try contentParts(window)
        for layout in [HUDLayoutMode.horizontalRight, .verticalTop, .verticalBottom, .horizontalLeft] {
            let previous = parts
            let previousWindow = window
            let previousNumber = window.windowNumber
            fixture.model.hudLayoutMode = layout
            try await Task.sleep(nanoseconds: 300_000_000)
            window = try XCTUnwrap(controller.window)
            assertRetired(previousWindow)
            XCTAssertFalse(window === previousWindow)
            XCTAssertNotEqual(window.windowNumber, previousNumber)
            parts = try contentParts(window)
            XCTAssertFalse(parts.container === previous.container)
            XCTAssertFalse(parts.hosting === previous.hosting)
            XCTAssertFalse(parts.background === previous.background)
            XCTAssertNil(previous.container.superview)
            XCTAssertNil(previous.container.window)
            XCTAssertEqual(window.frame.size, HUDBackgroundAppearance(86).size(layout))
            XCTAssertEqual(parts.hosting.frame, parts.container.bounds)
            XCTAssertNil(fixture.model.displayedSession)
            XCTAssertEqual(HUDView(model: fixture.model).displayedTitle, "Traceflow")
            try assertLightPositions(parts.hosting, layout: layout)
        }
    }

    func testScreenCompositeAfterPanelReplacementLayoutSwitch() async throws {
        _ = NSApplication.shared
        for backdropColor in [NSColor.white, .darkGray] {
            let screen = try HUDScreenFixture(color: backdropColor)
            defer { screen.close() }
            let fixture = try SessionIntegrationFixture()
            defer { fixture.cleanUp() }
            fixture.model.hudLayoutMode = .horizontalLeft
            fixture.model.hudTitleColor = backdropColor == .white ? .black : .white
            fixture.model.previewTransparency(86)
            try screen.preparePositions(defaults: fixture.defaults)
            let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
            defer { controller.hide() }
            controller.show()
            for layout in [HUDLayoutMode.horizontalRight, .horizontalLeft, .verticalTop,
                           .verticalBottom, .verticalTop, .horizontalRight] {
                let previous = fixture.model.hudLayoutMode
                fixture.model.hudLayoutMode = layout
                await Task.yield()
                try await screen.assertSettled(controller, fixture: fixture,
                                               regions: oldRegions(previous, size: controller.window!.frame.size))
            }
            for index in 0..<20 { fixture.model.hudLayoutMode = HUDLayoutMode.allCases[index % 4] }
            fixture.model.hudLayoutMode = .horizontalLeft
            await Task.yield()
            try await screen.assertSettled(controller, fixture: fixture)
            controller.hide()
            fixture.model.hudLayoutMode = .verticalBottom
            XCTAssertFalse(controller.window!.isVisible)
            controller.show()
            try await screen.assertSettled(controller, fixture: fixture)
            // Same-screen movement: the capture helper preserves this new origin.
            let oldOrigin = controller.window!.frame.origin
            controller.window!.setFrameOrigin(NSPoint(x: oldOrigin.x + 10, y: oldOrigin.y + 10))
            try await screen.assertSettled(controller, fixture: fixture)
        }
    }

    private func oldRegions(_ layout: HUDLayoutMode, size: NSSize) -> [NSRect] {
        // Both leading/trailing bands are checked; coordinates are screenshot-local.
        if layout.isHorizontal {
            return [NSRect(x: 0, y: 0, width: 104, height: size.height),
                    NSRect(x: max(0, size.width - 104), y: 0, width: 104, height: size.height),
                    NSRect(x: 0, y: 0, width: size.width, height: 40)]
        }
        return [NSRect(x: 0, y: 0, width: size.width, height: 104),
                NSRect(x: 0, y: max(0, size.height - 104), width: size.width, height: 104),
                NSRect(x: 0, y: 0, width: 40, height: size.height)]
    }

    func testScreenLayoutChangesAfterCrossScreenRoundTrip() async throws {
        _ = NSApplication.shared
        let first = try HUDScreenFixture(color: .white)
        defer { first.close() }
        guard let other = NSScreen.screens.first(where: { $0 !== NSScreen.main }) else {
            throw XCTSkip("跨屏回归需要第二块屏幕：待人工验收")
        }
        let second = try HUDScreenFixture(color: .white, screen: other)
        defer { second.close() }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.previewTransparency(86)
        fixture.model.hudTitleColor = .black
        fixture.model.hudLayoutMode = .horizontalLeft
        try first.preparePositions(defaults: fixture.defaults)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        let window = try XCTUnwrap(controller.window)
        try await first.assertSettled(controller, fixture: fixture)
        try second.place(controller)
        try await second.assertSettled(controller, fixture: fixture)
        try first.place(controller)
        try await first.assertSettled(controller, fixture: fixture)
        fixture.model.hudLayoutMode = .horizontalRight
        await Task.yield()
        try await first.assertSettled(controller, fixture: fixture)
        XCTAssertFalse(controller.window === window)
        assertRetired(window)
    }

    func testPanelReplacementCrossOrientationAtTransparencyBoundary() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.hudLayoutMode = .horizontalLeft
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        var window = try XCTUnwrap(controller.window)
        var parts = try contentParts(window)
        for transparency in [86.0, 10, 79, 80, 100] {
            fixture.model.previewTransparency(transparency)
            try await Task.sleep(nanoseconds: 300_000_000)
            for color in [HUDTitleColor.white, .black] {
                fixture.model.hudTitleColor = color
                for layout in [HUDLayoutMode.horizontalRight, .verticalTop, .verticalBottom, .horizontalLeft] {
                    let previous = parts
                    let previousWindow = window
                    let previousNumber = window.windowNumber
                    fixture.model.hudLayoutMode = layout
                    try await Task.sleep(nanoseconds: 300_000_000)
                    window = try XCTUnwrap(controller.window)
                    assertRetired(previousWindow)
                    XCTAssertFalse(window === previousWindow)
                    XCTAssertNotEqual(window.windowNumber, previousNumber)
                    parts = try contentParts(window)
                    XCTAssertFalse(parts.container === previous.container)
                    XCTAssertFalse(parts.hosting === previous.hosting)
                    XCTAssertFalse(parts.background === previous.background)
                    XCTAssertNil(previous.container.superview)
                    XCTAssertEqual(window.frame.size, HUDBackgroundAppearance(Int(transparency)).size(layout))
                    XCTAssertEqual(parts.hosting.frame, parts.container.bounds)
                    XCTAssertEqual(parts.background.alphaValue,
                                   HUDBackgroundAppearance(Int(transparency)).backgroundAlpha,
                                   accuracy: 0.001)
                    XCTAssertEqual(fixture.model.hudIconFraction, transparency >= 80 ? 0 : 1)
                    XCTAssertEqual(fixture.model.hudTitleColor, color)
                    XCTAssertEqual(fixture.model.hudBackgroundTransparency, Int(transparency))
                    try assertLightPositions(parts.hosting, layout: layout)
                }
            }
        }
    }

    func testQueuedAndInterleavedLayoutChangesKeepLatestPanel() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.hudLayoutMode = .horizontalLeft
        fixture.model.previewTransparency(86)
        fixture.model.isHUDPinned = true
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        var window = try XCTUnwrap(controller.window)
        var parts = try contentParts(window)
        for interleaved in [false, true] {
            let previousWindow = window
            let previousContainer = parts.container
            // Start each sequence on a different layout from its final selection.
            fixture.model.hudLayoutMode = .horizontalLeft
            controller.switchLayout(to: .horizontalLeft)
            for index in 0..<20 {
                fixture.model.hudLayoutMode = HUDLayoutMode.allCases[index % 4]
                if interleaved { try await Task.sleep(nanoseconds: 20_000_000) }
            }
            // ABA: a queued older horizontalRight must not win over the latest one.
            fixture.model.hudLayoutMode = .horizontalRight
            fixture.model.hudLayoutMode = .horizontalLeft
            fixture.model.hudLayoutMode = .horizontalRight
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertEqual(fixture.model.hudLayoutMode, .horizontalRight)
            window = try XCTUnwrap(controller.window)
            XCTAssertFalse(window === previousWindow)
            assertRetired(previousWindow)
            parts = try contentParts(window)
            XCTAssertFalse(parts.container === previousContainer)
            XCTAssertNil(previousContainer.superview)
            XCTAssertEqual(window.frame.size, NSSize(width: 380, height: 40))
            XCTAssertTrue(window.ignoresMouseEvents)
            XCTAssertTrue(fixture.model.isHUDPinned)
            try assertLightPositions(parts.hosting, layout: .horizontalRight)
        }
        let frame = window.frame
        let position = HUDPositionStore(defaults: fixture.defaults).loadResult(.horizontalRight)
        let finalContainer = parts.container
        fixture.model.hudLayoutMode = .horizontalRight
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(controller.window === window)
        controller.switchLayout(to: .verticalTop)
        XCTAssertTrue(controller.window === window, "过期回调不能创建窗口")
        XCTAssertEqual(window.frame, frame)
        XCTAssertTrue(try contentParts(window).container === finalContainer)
        XCTAssertEqual(HUDPositionStore(defaults: fixture.defaults).loadResult(.horizontalRight), position)
    }

    func testHiddenLayoutReplacesPanelWithoutShowingPanel() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.hudLayoutMode = .horizontalLeft
        fixture.model.previewTransparency(86)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        var window = try XCTUnwrap(controller.window)
        let initial = try contentParts(window)
        fixture.model.hudLayoutMode = .horizontalRight
        // A pending layout change must not make the subsequently hidden panel visible.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                controller.hide()
                continuation.resume()
            }
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(window.isVisible)
        fixture.model.hudLayoutMode = .verticalBottom
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(window.isVisible)
        let previousWindow = window
        window = try XCTUnwrap(controller.window)
        assertRetired(previousWindow)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(window.frame.size, NSSize(width: 40, height: 380))
        let hidden = try contentParts(window)
        XCTAssertFalse(hidden.container === initial.container)
        XCTAssertFalse(hidden.hosting === initial.hosting)
        XCTAssertNil(initial.container.superview)
        controller.show()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(try contentParts(window).container === hidden.container)
        try assertLightPositions(contentParts(window).hosting, layout: .verticalBottom)
    }

    func testDetachedPanelAndContentAreReleasedAndRepeatedLayoutDoesNotReplaceIt() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.hudLayoutMode = .horizontalLeft
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        weak var previousWindow = controller.window
        weak var previousContainer: HUDDragView? = try contentParts(try XCTUnwrap(controller.window)).container
        weak var previousHosting: NSHostingView<HUDView>? = try contentParts(try XCTUnwrap(controller.window)).hosting
        weak var previousBackground: HUDBackgroundView? = try contentParts(try XCTUnwrap(controller.window)).background
        fixture.model.hudLayoutMode = .horizontalRight
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(previousWindow, "旧面板必须释放")
        XCTAssertNil(previousContainer, "旧内容容器不能被控制器或异步工作长期持有")
        XCTAssertNil(previousHosting, "旧承载不能被控制器或异步工作长期持有")
        XCTAssertNil(previousBackground, "旧背景不能被控制器或异步工作长期持有")
        let current = try contentParts(try XCTUnwrap(controller.window))
        fixture.model.hudLayoutMode = .horizontalRight
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(try contentParts(try XCTUnwrap(controller.window)).container === current.container)
    }

    func testShowImmediatelyAppliesPendingLayoutBeforeDisplayingWindow() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.hudLayoutMode = .horizontalLeft
        fixture.model.previewTransparency(86)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        var window = try XCTUnwrap(controller.window)
        let original = try contentParts(window)
        controller.hide()
        fixture.model.hudLayoutMode = .verticalBottom
        // No yield: the observer's queued switch has not run.
        controller.show()
        let previousWindow = window
        window = try XCTUnwrap(controller.window)
        XCTAssertFalse(window === previousWindow)
        assertRetired(previousWindow)
        let displayed = try contentParts(window)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.frame.size, NSSize(width: 40, height: 380))
        XCTAssertEqual(displayed.hosting.frame, displayed.container.bounds)
        XCTAssertFalse(displayed.container === original.container)
        XCTAssertNil(original.container.superview)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(try contentParts(window).container === displayed.container,
                      "迟到的布局回调不能再次替换已显示的内容容器")
    }

    func testReplacementPanelReconnectsInteractionAndTransparency() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.hudLayoutMode = .horizontalLeft
        fixture.model.previewTransparency(86)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        var window = try XCTUnwrap(controller.window)
        let original = try contentParts(window)

        fixture.model.hudLayoutMode = .verticalTop
        controller.switchLayout(to: .verticalTop)
        let previousWindow = window
        window = try XCTUnwrap(controller.window)
        XCTAssertFalse(window === previousWindow)
        assertRetired(previousWindow)
        XCTAssertNil(original.container.canBeginDrag)
        XCTAssertNil(original.container.dragStarted)
        XCTAssertNil(original.container.dragFinished)
        let replacement = try contentParts(window)
        XCTAssertFalse(replacement.container === original.container)
        XCTAssertNotNil(replacement.container.canBeginDrag)
        XCTAssertNotNil(replacement.container.dragStarted)
        XCTAssertNotNil(replacement.container.dragFinished)
        XCTAssertEqual(replacement.container.canBeginDrag?(), true)

        let store = HUDPositionStore(defaults: fixture.defaults)
        let before = store.loadResult(.verticalTop)
        replacement.container.dragStarted?()
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 12, y: window.frame.minY - 12))
        replacement.container.dragFinished?(true)
        XCTAssertNotEqual(store.loadResult(.verticalTop), before,
                          "替换后的容器完成拖动时必须保存新位置")

        fixture.model.previewTransparency(55)
        XCTAssertEqual(replacement.background.alphaValue,
                       HUDBackgroundAppearance(55).backgroundAlpha, accuracy: 0.001)
        XCTAssertFalse(window.hasShadow)

        fixture.model.isHUDPinned = true
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertEqual(replacement.container.canBeginDrag?(), false)
        fixture.model.isHUDPinned = false
        XCTAssertFalse(window.ignoresMouseEvents)
        XCTAssertEqual(replacement.container.canBeginDrag?(), true)
    }

    func testReplacementPreservesWindowPolicyFocusAndStoredPositions() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        // Initialize layout records before comparing: seeding remains intentional.
        for layout in HUDLayoutMode.allCases {
            fixture.model.hudLayoutMode = layout
            controller.switchLayout(to: layout)
        }
        let store = HUDPositionStore(defaults: fixture.defaults)
        let stored = HUDLayoutMode.allCases.map { store.loadResult($0) }
        let settings = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
                                styleMask: [.titled], backing: .buffered, defer: false)
        settings.isReleasedWhenClosed = false
        settings.makeKeyAndOrderFront(nil)
        defer { settings.close() }
        let keyWindow = NSApp.keyWindow
        controller.show()
        for layout in HUDLayoutMode.allCases {
            let old = try XCTUnwrap(controller.window)
            fixture.model.hudLayoutMode = layout
            controller.switchLayout(to: layout)
            let current = try XCTUnwrap(controller.window)
            XCTAssertFalse(old === current)
            assertRetired(old)
            XCTAssertTrue(current.isVisible)
            XCTAssertFalse(current.canBecomeKey)
            XCTAssertFalse(current.canBecomeMain)
            XCTAssertTrue(NSApp.keyWindow === keyWindow)
            XCTAssertEqual(NSApp.windows.filter { $0 is NonActivatingPanel && $0.isVisible }.count, 1)
            XCTAssertEqual(current.level, .floating)
            XCTAssertEqual(current.collectionBehavior, [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary])
            XCTAssertFalse(current.isOpaque)
            XCTAssertEqual(current.backgroundColor, .clear)
            XCTAssertFalse(current.hidesOnDeactivate)
            XCTAssertFalse(current.isMovableByWindowBackground)
            XCTAssertEqual(current.animationBehavior, .none)
            XCTAssertFalse(current.hasShadow)
            XCTAssertEqual(HUDLayoutMode.allCases.map { store.loadResult($0) }, stored)
        }
    }

    func testTransparencyChangesNeverEnableSystemShadow() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        for layout in HUDLayoutMode.allCases {
            let fixture = try SessionIntegrationFixture()
            defer { fixture.cleanUp() }
            fixture.model.hudLayoutMode = layout
            fixture.model.previewTransparency(86)
            let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
            defer { controller.hide() }
            let original = try XCTUnwrap(controller.window)
            XCTAssertFalse(original.hasShadow)

            for value in [10, 55, 86, 99, 100, 86, 10] {
                fixture.model.previewTransparency(Double(value))
                let current = try XCTUnwrap(controller.window)
                XCTAssertTrue(current === original, "透明度更新不能替换窗口")
                XCTAssertFalse(current.hasShadow, "透明度\(value)不能重新开启系统阴影")
                XCTAssertEqual(try contentParts(current).background.alphaValue,
                               HUDBackgroundAppearance(value).backgroundAlpha, accuracy: 0.001)
            }
        }
    }

    private func assertRetired(_ window: NSWindow, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(window.isVisible, file: file, line: line)
        XCTAssertNil(window.contentView, file: file, line: line)
        XCTAssertNil(window.delegate, file: file, line: line)
    }

    private func contentParts(_ window: NSWindow) throws
        -> (container: HUDDragView, hosting: NSHostingView<HUDView>, background: HUDBackgroundView) {
        let container = try XCTUnwrap(window.contentView as? HUDDragView)
        let hosts = container.subviews.compactMap { $0 as? NSHostingView<HUDView> }
        let backgrounds = container.subviews.compactMap { $0 as? HUDBackgroundView }
        XCTAssertEqual(hosts.count, 1, "同一容器只能有一个HUD承载")
        XCTAssertEqual(backgrounds.count, 1, "同一容器只能有一个HUD背景")
        return (container, try XCTUnwrap(hosts.first), try XCTUnwrap(backgrounds.first))
    }

    private func assertLightPositions(_ hosting: NSView, layout: HUDLayoutMode) throws {
        // Public native-view geometry is auxiliary evidence, not screen capture.
        let lights = hosting.subviews.filter { $0.frame.size == NSSize(width: 26, height: 26) }
        XCTAssertEqual(lights.count, 3)
        let centers = lights.map { hosting.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), from: $0) }
        let length = layout.isHorizontal ? hosting.bounds.width : hosting.bounds.height
        for center in centers {
            let position = layout.isHorizontal ? center.x : (hosting.isFlipped ? center.y : length - center.y)
            if layout.lightsAtLeadingEdge { XCTAssertLessThan(position, 104) }
            else { XCTAssertGreaterThan(position, length - 104) }
        }
    }

    func testInitialIconVisibilityChangesAtEightyPercent() {
        let domain = "HUDIconThreshold.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(79, forKey: HUDPreferences.transparencyKey)
        XCTAssertEqual(AppModel(defaults: defaults).hudIconFraction, 1)
        defaults.set(80, forKey: HUDPreferences.transparencyKey)
        XCTAssertEqual(AppModel(defaults: defaults).hudIconFraction, 0)
    }

    func testSwitchCancelsDragAndRejectsLateFinishWithoutSaving() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let domain = "HUDLayoutController.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = AppModel(defaults: defaults)
        let controller = HUDPanelController(model: model, defaults: defaults)
        let store = HUDPositionStore(defaults: defaults)
        let before = store.loadResult(.horizontalRight)
        let dragView = try XCTUnwrap(controller.window?.contentView as? HUDDragView)
        dragView.dragStarted?()
        controller.window?.setFrameOrigin(CGPoint(x: 700, y: 300))
        model.hudLayoutMode = .verticalTop
        controller.switchLayout(to: .verticalTop)
        let target = try XCTUnwrap(controller.window?.frame)
        dragView.dragFinished?(true)
        XCTAssertEqual(controller.window?.frame, target)
        XCTAssertEqual(store.loadResult(.horizontalRight), before)
        XCTAssertEqual(target.size, CGSize(width: 40, height: 420))
        controller.hide()
    }

    func testLatestLayoutWinsAndPinAndTransparencySurvive() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let domain = "HUDLayoutPinned.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: HUDPreferences.pinnedKey)
        defaults.set(100, forKey: HUDPreferences.transparencyKey)
        let model = AppModel(defaults: defaults)
        let controller = HUDPanelController(model: model, defaults: defaults)
        model.hudLayoutMode = .verticalTop
        model.hudLayoutMode = .horizontalLeft
        controller.switchLayout(to: .verticalTop)
        controller.switchLayout(to: .horizontalLeft)
        XCTAssertEqual(controller.window?.frame.size, CGSize(width: 380, height: 40))
        XCTAssertEqual(model.hudIconFraction, 0)
        XCTAssertTrue(controller.window?.ignoresMouseEvents == true)
        XCTAssertEqual(model.hudBackgroundTransparency, 100)
        controller.hide()
    }

    func testSwitchToUnavailableDisplayStartsNewRetry() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let domain = "HUDLayoutRetry.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = AppModel(defaults: defaults)
        let controller = HUDPanelController(model: model, defaults: defaults)
        let store = HUDPositionStore(defaults: defaults)
        let absent = HUDPositionRecord(version: 3, displayUUID: UUID().uuidString, legacyDisplayID: nil, displayName: nil, pixelWidth: nil, pixelHeight: nil, relativeX: 0.4, relativeY: 0.6)
        store.save(absent, for: .verticalTop)
        model.hudLayoutMode = .verticalTop
        controller.switchLayout(to: .verticalTop)
        XCTAssertTrue(controller.isRetryingPosition)
        XCTAssertEqual(store.load(.verticalTop), absent)
        model.hudLayoutMode = .horizontalRight
        controller.switchLayout(to: .horizontalRight)
        XCTAssertFalse(controller.isRetryingPosition)
        XCTAssertEqual(store.load(.verticalTop), absent)
        controller.hide()
    }
}

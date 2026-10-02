import AppKit
import SwiftUI
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class HUDLayoutControllerTests: XCTestCase {
    func testSamePanelSwitchesLeftRightAndBackThroughObserver() async throws {
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
        let window = try XCTUnwrap(controller.window)
        let container = try XCTUnwrap(window.contentView)
        var hosting = try soleHosting(container)
        let background = try XCTUnwrap(container.subviews.first { $0 is HUDBackgroundView })
        for layout in [HUDLayoutMode.horizontalRight, .verticalTop, .verticalBottom, .horizontalLeft] {
            let previous = hosting
            fixture.model.hudLayoutMode = layout
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertTrue(controller.window === window)
            XCTAssertTrue(window.contentView === container)
            hosting = try soleHosting(container)
            XCTAssertFalse(hosting === previous)
            XCTAssertNil(previous.superview)
            XCTAssertTrue(background.superview === container)
            XCTAssertEqual(window.frame.size, HUDBackgroundAppearance(86).size(layout))
            XCTAssertEqual(hosting.frame, container.bounds)
            XCTAssertNil(fixture.model.displayedSession)
            XCTAssertEqual(HUDView(model: fixture.model).displayedTitle, "Traceflow")
            try assertLightPositions(hosting, layout: layout)
        }
    }

    func testScreenCompositeAfterSamePanelLayoutSwitch() async throws {
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
        second.place(window)
        try await second.assertSettled(controller, fixture: fixture)
        first.place(window)
        try await first.assertSettled(controller, fixture: fixture)
        fixture.model.hudLayoutMode = .horizontalRight
        await Task.yield()
        try await first.assertSettled(controller, fixture: fixture)
        XCTAssertTrue(controller.window === window)
    }

    func testSamePanelCrossOrientationAtTransparencyBoundary() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.hudLayoutMode = .horizontalLeft
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        let window = try XCTUnwrap(controller.window)
        let container = try XCTUnwrap(window.contentView)
        var hosting = try soleHosting(container)
        for transparency in [86.0, 10, 79, 80, 100] {
            fixture.model.previewTransparency(transparency)
            try await Task.sleep(nanoseconds: 300_000_000)
            for color in [HUDTitleColor.white, .black] {
                fixture.model.hudTitleColor = color
                for layout in [HUDLayoutMode.horizontalRight, .verticalTop, .verticalBottom, .horizontalLeft] {
                    let previous = hosting
                    fixture.model.hudLayoutMode = layout
                    try await Task.sleep(nanoseconds: 300_000_000)
                    XCTAssertTrue(controller.window === window)
                    XCTAssertTrue(window.contentView === container)
                    hosting = try soleHosting(container)
                    XCTAssertFalse(hosting === previous)
                    XCTAssertNil(previous.superview)
                    XCTAssertEqual(window.frame.size, HUDBackgroundAppearance(Int(transparency)).size(layout))
                    XCTAssertEqual(hosting.frame, container.bounds)
                    XCTAssertEqual(fixture.model.hudIconFraction, transparency >= 80 ? 0 : 1)
                    XCTAssertEqual(fixture.model.hudTitleColor, color)
                    XCTAssertEqual(fixture.model.hudBackgroundTransparency, Int(transparency))
                    try assertLightPositions(hosting, layout: layout)
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
        let window = try XCTUnwrap(controller.window)
        let container = try XCTUnwrap(window.contentView)
        var hosting = try soleHosting(container)
        for interleaved in [false, true] {
            let previous = hosting
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
            XCTAssertTrue(controller.window === window)
            hosting = try soleHosting(container)
            XCTAssertFalse(hosting === previous)
            XCTAssertNil(previous.superview)
            XCTAssertEqual(window.frame.size, NSSize(width: 380, height: 40))
            XCTAssertTrue(window.ignoresMouseEvents)
            XCTAssertTrue(fixture.model.isHUDPinned)
            try assertLightPositions(hosting, layout: .horizontalRight)
        }
        let frame = window.frame
        let position = HUDPositionStore(defaults: fixture.defaults).loadResult(.horizontalRight)
        fixture.model.hudLayoutMode = .horizontalRight
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(window.frame, frame)
        XCTAssertTrue(try soleHosting(container) === hosting)
        XCTAssertEqual(HUDPositionStore(defaults: fixture.defaults).loadResult(.horizontalRight), position)
    }

    func testHiddenLayoutReplacesContentWithoutShowingPanel() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.hudLayoutMode = .horizontalLeft
        fixture.model.previewTransparency(86)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        let window = try XCTUnwrap(controller.window)
        let container = try XCTUnwrap(window.contentView)
        let initialHosting = try soleHosting(container)
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
        XCTAssertEqual(window.frame.size, NSSize(width: 40, height: 380))
        let hiddenHosting = try soleHosting(container)
        XCTAssertFalse(hiddenHosting === initialHosting)
        XCTAssertNil(initialHosting.superview)
        controller.show()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(controller.window === window)
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(try soleHosting(container) === hiddenHosting)
        try assertLightPositions(soleHosting(try XCTUnwrap(window.contentView)), layout: .verticalBottom)
    }

    func testDetachedHostingIsReleasedAndRepeatedLayoutDoesNotReplaceIt() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要可用桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.hudLayoutMode = .horizontalLeft
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        let container = try XCTUnwrap(controller.window?.contentView)
        weak var previous: NSHostingView<HUDView>? = try soleHosting(container)
        fixture.model.hudLayoutMode = .horizontalRight
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(previous, "旧承载不能被控制器或异步工作长期持有")
        let current = try soleHosting(container)
        fixture.model.hudLayoutMode = .horizontalRight
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(try soleHosting(container) === current)
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
        let window = try XCTUnwrap(controller.window)
        let container = try XCTUnwrap(window.contentView)
        let original = try soleHosting(container)
        controller.hide()
        fixture.model.hudLayoutMode = .verticalBottom
        // No yield: the observer's queued switch has not run.
        controller.show()
        let displayed = try soleHosting(container)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.frame.size, NSSize(width: 40, height: 380))
        XCTAssertEqual(displayed.frame, container.bounds)
        XCTAssertFalse(displayed === original)
        XCTAssertNil(original.superview)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(try soleHosting(container) === displayed,
                      "迟到的布局回调不能再次替换已显示的承载")
    }


    private func soleHosting(_ container: NSView) throws -> NSHostingView<HUDView> {
        let hosts = container.subviews.compactMap { $0 as? NSHostingView<HUDView> }
        XCTAssertEqual(hosts.count, 1, "同一容器只能有一个HUD承载")
        return try XCTUnwrap(hosts.first)
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

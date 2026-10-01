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
        let hosting = try soleHosting(container)
        for layout in [HUDLayoutMode.horizontalLeft, .horizontalRight, .horizontalLeft] {
            fixture.model.hudLayoutMode = layout
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertTrue(controller.window === window)
            XCTAssertTrue(window.contentView === container)
            XCTAssertTrue(try soleHosting(container) === hosting)
            XCTAssertEqual(window.frame.size, NSSize(width: 380, height: 40))
            XCTAssertEqual(hosting.frame, container.bounds)
            XCTAssertNil(fixture.model.displayedSession)
            XCTAssertEqual(HUDView(model: fixture.model).displayedTitle, "Traceflow")
            try assertLightPositions(hosting, layout: layout)
        }
    }

    func testScreenCompositeAfterSamePanelLayoutSwitch() async throws {
        _ = NSApplication.shared
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("缺少屏幕录制权限：同窗口布局切换残影待实屏验收")
        }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.hudLayoutMode = .horizontalLeft
        fixture.model.hudTitleColor = .white
        fixture.model.previewTransparency(86)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        let panel = try XCTUnwrap(controller.window)
        for layout in [HUDLayoutMode.horizontalRight, .horizontalLeft, .verticalTop, .verticalBottom] {
            fixture.model.hudLayoutMode = layout
            try await Task.sleep(nanoseconds: 300_000_000)
            // Capture normal WindowServer output before any auxiliary cacheDisplay.
            let actual = try await captureWindow(panel, fixture: fixture)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let persistent = try await captureWindow(panel, fixture: fixture)
            let reference = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
            reference.show()
            let cleanPanel = try XCTUnwrap(reference.window)
            cleanPanel.setFrameOrigin(panel.frame.origin)
            try await Task.sleep(nanoseconds: 300_000_000)
            let expected = try await captureWindow(cleanPanel, fixture: fixture)
            reference.hide()
            XCTAssertEqual(actual, expected, "正常屏幕合成不应保留旧布局")
            XCTAssertEqual(persistent, expected, "一秒后不应存在持续残影")
        }
    }

    private func captureWindow(_ window: NSWindow, fixture: SessionIntegrationFixture) async throws -> Data {
        let file = fixture.root.appendingPathComponent(UUID().uuidString + ".png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), file.path]
        try process.run()
        try await fixture.waitUntil { !process.isRunning }
        XCTAssertEqual(process.terminationStatus, 0)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: file)))
        return try XCTUnwrap(bitmap.tiffRepresentation)
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

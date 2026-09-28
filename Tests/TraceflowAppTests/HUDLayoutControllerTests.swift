import AppKit
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class HUDLayoutControllerTests: XCTestCase {
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

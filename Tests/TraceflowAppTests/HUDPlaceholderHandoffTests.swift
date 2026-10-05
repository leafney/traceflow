import AppKit
import Combine
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
            XCTAssertFalse(original.hasShadow)
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
            XCTAssertFalse(sessionPanel.hasShadow)
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
            XCTAssertFalse(restored.hasShadow)
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

    func testRapidModeChangesAndCombinedLayoutApplyOnlyFinalCombination() async throws {
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        try await fixture.hook("a", event: .userPromptSubmit)
        fixture.model.setIncluded(false, sessionID: "a")
        fixture.model.hudLayoutMode = .horizontalLeft
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        let original = try XCTUnwrap(controller.window)
        fixture.model.setIncluded(true, sessionID: "a")
        XCTAssertEqual(try hosted(original).displayedTitle, "Traceflow")
        fixture.model.setIncluded(false, sessionID: "a")
        await drainQueue()
        XCTAssertTrue(controller.window === original, "同轮 nil → A → nil 不应更换默认窗口")

        fixture.model.setIncluded(true, sessionID: "a")
        fixture.model.hudLayoutMode = .verticalBottom
        controller.show()
        let combined = try XCTUnwrap(controller.window)
        XCTAssertFalse(combined === original)
        XCTAssertEqual(try hosted(combined).layout, .verticalBottom)
        XCTAssertEqual(try hosted(combined).presentation.displayedSession?.id, "a")
        await drainQueue()
        XCTAssertTrue(controller.window === combined)
        fixture.model.setIncluded(false, sessionID: "a")
        fixture.model.setIncluded(true, sessionID: "a")
        await drainQueue()
        XCTAssertTrue(controller.window === combined, "同轮 A → nil → A 不应更换会话窗口")
        XCTAssertEqual(try hosted(combined).presentation.displayedSession?.id, "a")
        try await fixture.hook("b", event: .userPromptSubmit)
        fixture.model.setIncluded(false, sessionID: "b")
        fixture.model.setIncluded(false, sessionID: "a")
        XCTAssertNil(fixture.model.displayedSession)
        fixture.model.setIncluded(true, sessionID: "b")
        await drainQueue()
        XCTAssertTrue(controller.window === combined, "同轮 A → nil → B 保留会话窗口")
        XCTAssertEqual(try hosted(combined).presentation.displayedSession?.id, "b")
    }

    func testHiddenBoundaryAndImmediateShowKeepFramePinAndFocus() async throws {
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        try await fixture.hook("a", event: .userPromptSubmit)
        fixture.model.isHUDPinned = true
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        let original = try XCTUnwrap(controller.window)
        fixture.model.setIncluded(false, sessionID: "a")
        await drainQueue()
        let hidden = try XCTUnwrap(controller.window)
        XCTAssertFalse(hidden === original)
        XCTAssertFalse(hidden.isVisible)
        XCTAssertTrue(hidden.ignoresMouseEvents)
        let screen = try XCTUnwrap(NSScreen.main)
        hidden.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 100, y: screen.visibleFrame.midY - 100))
        let frame = hidden.frame
        let settings = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
                                styleMask: [.titled], backing: .buffered, defer: false)
        settings.isReleasedWhenClosed = false
        settings.makeKeyAndOrderFront(nil)
        defer { settings.close() }
        let key = NSApp.keyWindow
        fixture.model.setIncluded(true, sessionID: "a")
        controller.show()
        let shown = try XCTUnwrap(controller.window)
        XCTAssertFalse(shown === hidden)
        XCTAssertTrue(shown.isVisible)
        XCTAssertTrue(shown.ignoresMouseEvents)
        XCTAssertEqual(shown.frame, frame, "show 不得恢复旧存储位置覆盖文字交接的当前位置")
        XCTAssertTrue(NSApp.keyWindow === key)
        XCTAssertEqual(NSApp.windows.filter { $0 is NonActivatingPanel && $0.isVisible }.count, 1)
        await drainQueue()
        XCTAssertTrue(controller.window === shown)
    }

    func testBoundaryDuringDragKeepsDraggedFrameAndRejectsLateFinish() async throws {
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        fixture.model.previewTransparency(86)
        try await fixture.hook("a", event: .userPromptSubmit)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        let old = try XCTUnwrap(controller.window)
        let drag = try XCTUnwrap(old.contentView as? HUDDragView)
        let store = HUDPositionStore(defaults: fixture.defaults)
        let records = HUDLayoutMode.allCases.map { store.loadResult($0) }
        drag.dragStarted?()
        old.setFrameOrigin(NSPoint(x: old.frame.minX - 50, y: old.frame.minY + 50))
        let frame = old.frame
        fixture.model.setIncluded(false, sessionID: "a")
        await drainQueue()
        let current = try XCTUnwrap(controller.window)
        XCTAssertFalse(current === old)
        XCTAssertEqual(current.frame, frame)
        XCTAssertNil(drag.canBeginDrag)
        XCTAssertNil(drag.dragStarted)
        XCTAssertNil(drag.dragFinished)
        drag.dragFinished?(true)
        XCTAssertEqual(current.frame, frame)
        XCTAssertEqual(HUDLayoutMode.allCases.map { store.loadResult($0) }, records)
        let newDrag = try XCTUnwrap(current.contentView as? HUDDragView)
        XCTAssertEqual(newDrag.canBeginDrag?(), true)
        newDrag.dragStarted?()
        current.setFrameOrigin(NSPoint(x: frame.minX - 12, y: frame.minY))
        newDrag.dragFinished?(true)
        XCTAssertNotEqual(HUDLayoutMode.allCases.map { store.loadResult($0) }, records,
                          "新窗口正常完成拖动仍必须保存位置")
    }

    func testBoundaryFinishesTransparencySizeTransitionAndKeepsAnchor() async throws {
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        fixture.model.hudLayoutMode = .horizontalRight
        fixture.model.previewTransparency(10)
        try await fixture.hook("a", event: .userPromptSubmit)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        let old = try XCTUnwrap(controller.window)
        let frame = old.frame
        let store = HUDPositionStore(defaults: fixture.defaults)
        let records = HUDLayoutMode.allCases.map { store.loadResult($0) }
        fixture.model.previewTransparency(86)
        fixture.model.setIncluded(false, sessionID: "a")
        await drainQueue()
        let current = try XCTUnwrap(controller.window)
        XCTAssertFalse(current === old)
        XCTAssertEqual(current.frame.size, NSSize(width: 380, height: 40))
        XCTAssertEqual(current.frame.maxX, frame.maxX, accuracy: 0.01)
        XCTAssertEqual(fixture.model.hudIconFraction, 0)
        let background = try XCTUnwrap(current.contentView?.subviews.first { $0 is HUDBackgroundView })
        XCTAssertEqual(background.alphaValue, HUDBackgroundAppearance(86).backgroundAlpha, accuracy: 0.001)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(current.frame.maxX, frame.maxX, accuracy: 0.01)
        fixture.model.previewTransparency(10)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(current.frame, frame)
        XCTAssertEqual(HUDLayoutMode.allCases.map { store.loadResult($0) }, records)
    }

    func testBoundaryKeepsMissingScreenRetryDeadlineAndPositionRecord() async throws {
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        try await fixture.hook("a", event: .userPromptSubmit)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        let store = HUDPositionStore(defaults: fixture.defaults)
        let absent = HUDPositionRecord(version: 3, displayUUID: UUID().uuidString,
                                       legacyDisplayID: nil, displayName: nil,
                                       pixelWidth: nil, pixelHeight: nil, relativeX: 0.4, relativeY: 0.6)
        store.save(absent, for: .verticalTop)
        fixture.model.hudLayoutMode = .verticalTop
        controller.switchLayout(to: .verticalTop)
        XCTAssertTrue(controller.isRetryingPosition)
        let deadline = try XCTUnwrap(controller.positionRetryDeadline)
        let old = try XCTUnwrap(controller.window)
        let frame = old.frame
        fixture.model.setIncluded(false, sessionID: "a")
        await drainQueue()
        XCTAssertFalse(controller.window === old)
        XCTAssertEqual(controller.window?.frame, frame)
        XCTAssertTrue(controller.isRetryingPosition)
        XCTAssertEqual(controller.positionRetryDeadline, deadline)
        XCTAssertEqual(store.load(.verticalTop), absent)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(controller.positionRetryDeadline, deadline)
        XCTAssertEqual(store.load(.verticalTop), absent)
        XCTAssertEqual(try hosted(XCTUnwrap(controller.window)).displayedTitle, "Traceflow")
    }

    func testBoundaryReleasesOldPanelContentAndPresentation() async throws {
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        try await fixture.hook("a", event: .userPromptSubmit)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        weak var panel = controller.window
        weak var container = controller.window?.contentView
        weak var hosting = controller.window?.contentView?.subviews.first { $0 is NSHostingView<HUDView> }
        weak var background = controller.window?.contentView?.subviews.first { $0 is HUDBackgroundView }
        weak var presentation = try hosted(XCTUnwrap(controller.window)).presentation
        fixture.model.setIncluded(false, sessionID: "a")
        await drainQueue()
        XCTAssertNil(panel)
        XCTAssertNil(container)
        XCTAssertNil(hosting)
        XCTAssertNil(background)
        XCTAssertNil(presentation, "快照订阅不能形成旧内容对象循环引用")
    }

    func testStableBoundaryPreservesUnclampedReferenceAtScreenEdge() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        fixture.model.hudLayoutMode = .horizontalLeft
        fixture.model.previewTransparency(10)
        try await fixture.hook("a", event: .userPromptSubmit)
        let id = try XCTUnwrap((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value)
        let uuid = try XCTUnwrap(CGDisplayCreateUUIDFromDisplayID(id)).takeRetainedValue()
        let store = HUDPositionStore(defaults: fixture.defaults)
        let record = HUDPositionRecord(version: 3, displayUUID: CFUUIDCreateString(nil, uuid) as String,
                                       legacyDisplayID: id, displayName: screen.localizedName,
                                       pixelWidth: nil, pixelHeight: nil, relativeX: 0.98, relativeY: 0.5,
                                       anchorX: 0.98, anchorY: 0.5)
        store.save(record, for: .horizontalLeft)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        let old = try XCTUnwrap(controller.window)
        let frame = old.frame
        XCTAssertEqual(frame.maxX, screen.visibleFrame.maxX, accuracy: 0.01)
        fixture.model.setIncluded(false, sessionID: "a")
        await drainQueue()
        XCTAssertEqual(controller.window?.frame, frame)
        fixture.model.previewTransparency(86)
        try await Task.sleep(nanoseconds: 250_000_000)
        let compact = try XCTUnwrap(controller.window?.frame)
        XCTAssertEqual(compact.width, 380)
        XCTAssertEqual(compact.maxX, screen.visibleFrame.maxX, accuracy: 0.01,
                       "不能用夹紧后的展示 frame 覆盖原参考位置，导致缩小时远离屏幕边缘")
        XCTAssertEqual(store.load(.horizontalLeft), record)
    }

    func testBoundaryPreservesFrameOnSecondScreen() async throws {
        let main = try XCTUnwrap(NSScreen.main)
        guard let second = NSScreen.screens.first(where: { $0 !== main }) else {
            throw XCTSkip("跨屏位置回归需要第二块屏幕")
        }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        try await fixture.hook("a", event: .userPromptSubmit)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        let old = try XCTUnwrap(controller.window)
        old.setFrameOrigin(NSPoint(x: second.visibleFrame.midX - 210, y: second.visibleFrame.midY))
        let frame = old.frame
        let store = HUDPositionStore(defaults: fixture.defaults)
        let records = HUDLayoutMode.allCases.map { store.loadResult($0) }
        fixture.model.setIncluded(false, sessionID: "a")
        await drainQueue()
        let current = try XCTUnwrap(controller.window)
        XCTAssertFalse(current === old)
        XCTAssertEqual(current.frame, frame)
        XCTAssertTrue(second.visibleFrame.contains(current.frame))
        XCTAssertEqual(HUDLayoutMode.allCases.map { store.loadResult($0) }, records)
    }

    func testScreenFirstShortTitleHandoffWithoutLayoutChangeOrMovement() async throws {
        _ = NSApplication.shared
        let screen = try HUDScreenFixture(color: .white)
        defer { screen.close() }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        fixture.model.hudTitleColor = .black
        fixture.model.hudLayoutMode = .horizontalRight
        fixture.model.previewTransparency(86)
        // Prepare a real, idle session with the diagnostic short title before
        // the tested default surface exists. The next real hook makes it visible.
        try await fixture.hook("short", event: .userPromptSubmit)
        try fixture.model.setCustomTitle("-     -     -", sessionID: "short")
        try await fixture.hook("short", event: .interrupt)
        XCTAssertNil(fixture.model.displayedSession)
        try screen.preparePositions(defaults: fixture.defaults)
        let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        try await Task.sleep(nanoseconds: 300_000_000)
        let original = try XCTUnwrap(controller.window)
        let frame = original.frame
        let originalNumber = original.windowNumber
        let defaultPixels = try screen.captureNow(original)
        var eventTime: Double?
        let observer = fixture.model.$displayedSession.dropFirst().sink { session in
            if session != nil, eventTime == nil { eventTime = ProcessInfo.processInfo.systemUptime }
        }
        defer { observer.cancel() }
        let hook = Task { try await fixture.hook("short", event: .userPromptSubmit) }
        defer { hook.cancel() }
        let timeout = ProcessInfo.processInfo.systemUptime + 8
        var samples: [(number: Int, began: Double, ended: Double, pixels: HUDScreenPixels)] = []
        while ProcessInfo.processInfo.systemUptime < timeout {
            try await Task.sleep(nanoseconds: 5_000_000)
            guard let eventTime else { continue }
            let began = ProcessInfo.processInfo.systemUptime - eventTime
            if began >= 0.2 { break }
            let current = try XCTUnwrap(controller.window)
            let pixels = try screen.captureNow(current)
            let ended = ProcessInfo.processInfo.systemUptime - eventTime
            XCTAssertEqual(current.frame, frame)
            samples.append((current.windowNumber, began, ended, pixels))
        }
        try await hook.value
        let current = try XCTUnwrap(controller.window)
        let newNumber = current.windowNumber
        XCTAssertNotEqual(newNumber, originalNumber)
        XCTAssertEqual(current.frame, frame)
        XCTAssertEqual(try hosted(current).displayedTitle, "-     -     -")
        // Capture at 300ms and 1s after the actual model event, not after hook
        // polling completes. No layout change, move, or forced draw is allowed.
        let occurred = try XCTUnwrap(eventTime)
        for target in [0.3, 1.0] {
            let remaining = target - (ProcessInfo.processInfo.systemUptime - occurred)
            if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
            let began = ProcessInfo.processInfo.systemUptime - occurred
            let pixels = try screen.captureNow(try XCTUnwrap(controller.window))
            samples.append((newNumber, began, ProcessInfo.processInfo.systemUptime - occurred, pixels))
        }
        current.orderOut(nil)
        defer { controller.window?.orderFrontRegardless() }
        let reference = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
        defer { reference.hide() }
        let clean = try XCTUnwrap(reference.window)
        clean.setFrame(frame, display: false)
        clean.orderFrontRegardless()
        try await Task.sleep(nanoseconds: 300_000_000)
        let expected = try screen.captureNow(clean)
        try await Task.sleep(nanoseconds: 300_000_000)
        let calibration = try screen.captureNow(clean)
        let region = NSRect(x: 0, y: 0, width: 268, height: 40)
        expected.assertSimilar(to: calibration, points: frame.size, regions: [region], compareFull: false)
        for sample in samples {
            print("标题交接采样：旧窗口=\(originalNumber) 新窗口=\(newNumber) 当前=\(sample.number) 开始=\(sample.began) 结束=\(sample.ended)")
            XCTAssertTrue(sample.number == originalNumber || sample.number == newNumber)
            sample.pixels.assertSimilar(to: sample.number == originalNumber ? defaultPixels : expected,
                                        points: frame.size, regions: [region], compareFull: false)
        }
        guard samples.filter({ $0.number == newNumber && $0.ended < 0.2 }).count >= 2 else {
            throw XCTSkip("稳定画面已比较，但交接前两百毫秒内无至少两帧新窗口采样：瞬间验收不足")
        }
    }

    private func drainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
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

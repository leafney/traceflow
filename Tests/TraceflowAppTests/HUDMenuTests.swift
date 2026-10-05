import AppKit
import Combine
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class HUDMenuTests: XCTestCase {
    func testInstalledMenuUsesCurrentWindowAfterTitleModeHandoff() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        fixture.model.autoEnableNewSessions = true
        let delegate = AppDelegate(model: fixture.model, defaults: fixture.defaults)
        delegate.installHUDControls()
        defer {
            delegate.panelController?.hide()
            if let item = delegate.statusItem { NSStatusBar.system.removeStatusItem(item) }
        }
        let menu = try XCTUnwrap(delegate.statusItem?.menu)
        fixture.model.isHUDVisible = true
        fixture.model.isHUDPinned = true
        let original = try XCTUnwrap(delegate.panelController?.window)
        try await fixture.hook("first", event: .userPromptSubmit)
        try await fixture.waitUntil { delegate.panelController?.window !== original }
        let session = try XCTUnwrap(delegate.panelController?.window)
        menu.update()
        XCTAssertFalse(original.isVisible)
        XCTAssertNil(original.contentView)
        XCTAssertTrue(session.isVisible)
        XCTAssertTrue(session.ignoresMouseEvents)
        XCTAssertEqual(menu.items[0].state, .on)
        XCTAssertEqual(menu.items[1].state, .on)
        fixture.model.setIncluded(false, sessionID: "first")
        try await fixture.waitUntil { delegate.panelController?.window !== session }
        let placeholder = try XCTUnwrap(delegate.panelController?.window)
        menu.performActionForItem(at: 0)
        menu.performActionForItem(at: 1)
        // Menu observers intentionally refresh after Published commits; wait
        // for that existing asynchronous path rather than asserting in willSet.
        try await fixture.waitUntil { menu.items[0].state == .off && menu.items[1].state == .off }
        menu.update()
        XCTAssertFalse(placeholder.isVisible)
        XCTAssertFalse(placeholder.ignoresMouseEvents)
        XCTAssertEqual(menu.items[0].state, .off)
        XCTAssertEqual(menu.items[1].state, .off)
    }

    func testInstalledStatusMenuTracksSettingsAndWindow() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要桌面屏幕") }
        let domain = "HUDInstalledMenu.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(false, forKey: "hudVisible")
        let model = AppModel(defaults: defaults)
        let delegate = AppDelegate(model: model, defaults: defaults)
        delegate.installHUDControls()
        defer {
            delegate.panelController?.hide()
            if let item = delegate.statusItem { NSStatusBar.system.removeStatusItem(item) }
        }
        let menu = try XCTUnwrap(delegate.statusItem?.menu)
        var panel = try XCTUnwrap(delegate.panelController?.window)
        menu.update()
        XCTAssertEqual(menu.items[0].state, .off)
        XCTAssertFalse(panel.isVisible)

        // The settings controls bind to these properties; exercise the same path.
        model.isHUDVisible = true
        model.isHUDPinned = true
        model.hudLayoutMode = .verticalTop
        let updated = expectation(description: "窗口布局和菜单状态已更新")
        DispatchQueue.main.async { updated.fulfill() }
        await fulfillment(of: [updated], timeout: 2)
        let previousPanel = panel
        panel = try XCTUnwrap(delegate.panelController?.window)
        XCTAssertFalse(panel === previousPanel)
        XCTAssertFalse(previousPanel.isVisible)
        XCTAssertNil(previousPanel.contentView)
        menu.update()
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertEqual(panel.frame.size, CGSize(width: 40, height: 420))
        XCTAssertEqual(menu.items[0].state, .on)
        XCTAssertEqual(menu.items[1].state, .on)
        XCTAssertEqual(menu.items[2].submenu?.items.map(\.state), [.off, .off, .on, .off])

        menu.performActionForItem(at: 0)
        menu.performActionForItem(at: 1)
        XCTAssertFalse(model.isHUDVisible)
        XCTAssertFalse(model.isHUDPinned)
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(panel.ignoresMouseEvents)
    }

    func testActionsShareStateAndRepeatedLayoutDoesNotPublish() async throws {
        _ = NSApplication.shared
        let domain = "HUDMenuActions.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = AppModel(defaults: defaults)
        let delegate = AppDelegate(model: model)
        let menu = delegate.makeMenu()
        delegate.observeHUDState(panel: nil)
        let children = try XCTUnwrap(menu.items[2].submenu?.items)
        var visibilityChanges = 0
        var layoutChanges = 0
        let visibility = model.$isHUDVisible.dropFirst().sink { _ in visibilityChanges += 1 }
        let layout = model.$hudLayoutMode.dropFirst().sink { _ in layoutChanges += 1 }
        defer { visibility.cancel(); layout.cancel() }

        menu.performActionForItem(at: 0)
        XCTAssertFalse(model.isHUDVisible)
        XCTAssertEqual(visibilityChanges, 1)
        menu.performActionForItem(at: 1)
        XCTAssertTrue(model.isHUDPinned)
        menu.items[2].submenu?.performActionForItem(at: 0)
        menu.items[2].submenu?.performActionForItem(at: 3)
        menu.items[2].submenu?.performActionForItem(at: 3)
        XCTAssertEqual(model.hudLayoutMode, .verticalBottom)
        XCTAssertEqual(layoutChanges, 2)
        let refreshed = expectation(description: "最新模型值已刷新到菜单")
        DispatchQueue.main.async { refreshed.fulfill() }
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertEqual(menu.items[0].state, .off)
        XCTAssertEqual(menu.items[1].state, .on)
        XCTAssertEqual(children.map(\.state), [.off, .off, .off, .on])

        // Settings binds directly to these same properties.
        model.isHUDPinned = false
        model.hudLayoutMode = .verticalTop
        delegate.menuNeedsUpdate(menu)
        XCTAssertEqual(menu.items[1].state, .off)
        XCTAssertEqual(children.map(\.state), [.off, .off, .on, .off])
        let reloaded = AppModel(defaults: defaults)
        let restartDelegate = AppDelegate(model: reloaded)
        let restartMenu = restartDelegate.makeMenu()
        XCTAssertEqual(restartMenu.items[0].state, .off)
        XCTAssertEqual(restartMenu.items[1].state, .off)
        XCTAssertEqual(restartMenu.items[2].submenu?.items.map(\.state), [.off, .off, .on, .off])
    }

    func testHiddenWindowKeepsPinAndReceivesLatestLayout() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要桌面屏幕") }
        let domain = "HUDMenuWindow.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(false, forKey: "hudVisible")
        let model = AppModel(defaults: defaults)
        let panel = HUDPanelController(model: model, defaults: defaults)
        defer { panel.hide() }
        let delegate = AppDelegate(model: model)
        let menu = delegate.makeMenu()
        delegate.observeHUDState(panel: panel)
        menu.performActionForItem(at: 1)
        menu.items[2].submenu?.performActionForItem(at: 0)
        menu.items[2].submenu?.performActionForItem(at: 3)
        let switched = expectation(description: "布局异步切换完成")
        DispatchQueue.main.async { switched.fulfill() }
        await fulfillment(of: [switched], timeout: 2)
        XCTAssertFalse(panel.window?.isVisible == true)
        XCTAssertTrue(panel.window?.ignoresMouseEvents == true)
        XCTAssertEqual(panel.window?.frame.size, CGSize(width: 40, height: 420))
        XCTAssertEqual(model.hudLayoutMode, .verticalBottom)
        menu.performActionForItem(at: 0)
        XCTAssertTrue(panel.window?.isVisible == true)
        XCTAssertTrue(panel.window?.ignoresMouseEvents == true)
        menu.performActionForItem(at: 0)
        XCTAssertFalse(panel.window?.isVisible == true)
    }

    func testInitialMenuStructureAndCheckmarks() throws {
        _ = NSApplication.shared
        let domain = "HUDMenuStructure.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let delegate = AppDelegate(model: AppModel(defaults: defaults))
        let menu = delegate.makeMenu()

        XCTAssertEqual(menu.items.map(\.title), ["显示 HUD", "钉住 HUD", "HUD 布局", "设置…", "", "退出 Traceflow"])
        XCTAssertEqual(menu.items[0].state, .on)
        XCTAssertEqual(menu.items[1].state, .off)
        XCTAssertEqual(menu.items[3].keyEquivalent, "")
        XCTAssertEqual(menu.items[5].keyEquivalent, "q")
        let parent = menu.items[2]
        XCTAssertEqual(parent.state, .off)
        let children = try XCTUnwrap(parent.submenu?.items)
        XCTAssertEqual(children.map(\.title), ["横向左", "横向右", "竖向上", "竖向下"])
        XCTAssertEqual(children.map(\.state), [.off, .on, .off, .off])
        XCTAssertTrue(children.allSatisfy { $0.target === delegate && $0.action != nil })
        XCTAssertEqual(children.map { $0.representedObject as? String }, HUDLayoutMode.allCases.map(\.rawValue))
    }
}

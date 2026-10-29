import AppKit
import XCTest
@testable import TraceflowApp

@MainActor
final class MenuWindowControllerTests: XCTestCase {
    func testStatusItemOpensAndClosesMenuWindow() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("需要桌面屏幕") }
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        let delegate = AppDelegate(model: fixture.model, defaults: fixture.defaults)
        delegate.installHUDControls()
        defer {
            delegate.menuWindowController?.closeImmediately()
            delegate.panelController?.hide()
            if let item = delegate.statusItem { NSStatusBar.system.removeStatusItem(item) }
        }
        let controller = try XCTUnwrap(delegate.menuWindowController)
        XCTAssertNil(delegate.statusItem?.menu)
        controller.show()
        XCTAssertTrue(controller.isVisible)
        controller.requestDismiss()
        XCTAssertFalse(controller.isVisible)
    }
    func testPanelClickOutsideEditorRequestsSave() throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let controller = MenuWindowController(model: fixture.model, statusItem: item)
        controller.editingArea = CGRect(x: 10, y: 20, width: 200, height: 30)
        var requests = 0
        controller.clickedOutsideEditor = { requests += 1 }
        controller.handlePanelClick(at: CGPoint(x: 30, y: 30))
        XCTAssertEqual(requests, 0)
        controller.handlePanelClick(at: CGPoint(x: 30, y: 80))
        XCTAssertEqual(requests, 1)
        controller.editingArea = nil
        controller.handlePanelClick(at: CGPoint(x: 30, y: 80))
        XCTAssertEqual(requests, 1)
    }

}

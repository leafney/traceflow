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
}

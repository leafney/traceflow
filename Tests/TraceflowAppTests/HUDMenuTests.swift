import AppKit
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class HUDMenuTests: XCTestCase {
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

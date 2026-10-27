import AppKit
import XCTest
@testable import TraceflowApp

@MainActor
final class MenuEditingCoordinatorTests: XCTestCase {
    func testSaveBeforeActionAndInvalidDraftKeepsEditing() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        try await fixture.hook("menu-editor", event: .sessionStart)
        let coordinator = MenuEditingCoordinator(model: fixture.model)
        coordinator.begin(try fixture.session("menu-editor"))
        coordinator.editing?.draft = " "
        var actions = 0
        coordinator.performAfterSaving { actions += 1 }
        try await fixture.waitUntil { coordinator.focusGeneration > 0 }
        XCTAssertEqual(actions, 0)
        XCTAssertNotNil(coordinator.editing)
        XCTAssertEqual(coordinator.editing?.draft, " ")
        coordinator.editing?.draft = "新的会话标题"
        coordinator.performAfterSaving { actions += 1 }
        try await fixture.waitUntil { actions == 1 }
        XCTAssertNil(coordinator.editing)
        XCTAssertEqual(try fixture.session("menu-editor").persisted.customTitle, "新的会话标题")
    }

    func testRestoreWinsOverPendingBlurSave() async throws {
        _ = NSApplication.shared
        let fixture = try SessionIntegrationFixture()
        defer { fixture.cleanUp() }
        try await fixture.hook("menu-editor", event: .sessionStart)
        try await fixture.model.setCustomTitle("自定义标题", sessionID: "menu-editor")
        let coordinator = MenuEditingCoordinator(model: fixture.model)
        coordinator.begin(try fixture.session("menu-editor"))
        coordinator.editing?.draft = "尚未保存"
        coordinator.scheduleBlurSave()
        coordinator.restore()
        try await fixture.waitUntil { coordinator.editing == nil }
        XCTAssertNil(try fixture.session("menu-editor").persisted.customTitle)
    }
}

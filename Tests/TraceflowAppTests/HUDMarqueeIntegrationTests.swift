import AppKit
import XCTest
import TraceflowCore
@testable import TraceflowApp

@MainActor
final class HUDMarqueeIntegrationTests: XCTestCase {
    private func fixture() async throws -> SessionIntegrationFixture {
        let fixture = try SessionIntegrationFixture()
        fixture.model.autoEnableNewSessions = true
        try await fixture.hook("a", event: .userPromptSubmit)
        try await fixture.model.setCustomTitle(String(repeating: "修复 login 状态 ", count: 8), sessionID: "a")
        try await fixture.hook("b", event: .userPromptSubmit)
        try await fixture.model.setCustomTitle(String(repeating: "第二个会话 title ", count: 8), sessionID: "b")
        return fixture
    }

    func testIndependentResumeReducedMotionSleepAndOldWindowCallbacks() async throws {
        let fixture = try await fixture()
        defer { fixture.cleanUp() }
        var now = 0.0
        let coordinator = HUDMarqueeCoordinator(clock: { now }, automaticTicks: false, observeSystem: false)
        let a = try fixture.session("a"), b = try fixture.session("b")
        let token = coordinator.beginWindow(layout: .horizontalRight, style: .medium, session: a)
        XCTAssertNil(coordinator.state.activeSessionID)
        coordinator.setVisible(true, generation: token)
        now = 2
        coordinator.update(session: b, generation: token)
        XCTAssertEqual(coordinator.state.sample("a", now: now).offset, -40, accuracy: 0.001)
        now = 3
        coordinator.update(session: a, generation: token)
        XCTAssertEqual(coordinator.currentFrame?.offset ?? 0, -40, accuracy: 0.001)
        XCTAssertEqual(coordinator.state.sample("b", now: now).offset, -20, accuracy: 0.001)
        now = 4
        coordinator.setReduceMotion(true)
        let frozen = coordinator.state.records["a"]!.phase
        XCTAssertEqual(coordinator.currentFrame?.offset, 0)
        now = 100
        coordinator.setReduceMotion(false)
        XCTAssertEqual(coordinator.state.sample("a", now: now).phase, frozen, accuracy: 0.00001)
        coordinator.setSleeping(system: true)
        coordinator.setSleeping(screen: true)
        now = 200
        coordinator.setSleeping(system: false)
        XCTAssertNil(coordinator.state.activeSessionID)
        coordinator.setSleeping(screen: false)
        XCTAssertEqual(coordinator.state.sample("a", now: now).phase, frozen, accuracy: 0.00001)
        let next = coordinator.beginWindow(layout: .verticalTop, style: .medium, session: a)
        coordinator.setVisible(true, generation: next)
        XCTAssertEqual(coordinator.state.sample("a", now: now).phase, frozen, accuracy: 0.00001)
        coordinator.retire(generation: token)
        coordinator.setVisible(false, generation: token)
        coordinator.update(session: b, generation: token)
        XCTAssertEqual(coordinator.state.activeSessionID, "a")
        coordinator.setVisible(false, generation: next)
        now = 1000
        XCTAssertEqual(coordinator.state.sample("a", now: now).phase, frozen, accuracy: 0.00001)
    }

    func testOutgoingViewFreezesAndPreviewCannotTakeOwnership() async throws {
        let fixture = try await fixture()
        defer { fixture.cleanUp() }
        var now = 0.0
        let coordinator = HUDMarqueeCoordinator(clock: { now }, automaticTicks: false, observeSystem: false)
        let a = try fixture.session("a"), b = try fixture.session("b")
        let token = coordinator.beginWindow(layout: .horizontalLeft, style: .medium, session: a)
        let old = HUDMarqueeNSView(title: a.sessionListTitle, vertical: false, color: .black)
        old.bind(coordinator: coordinator, generation: token, sessionID: a.id, title: a.sessionListTitle)
        coordinator.setVisible(true, generation: token)
        now = 2
        coordinator.update(session: b, generation: token)
        XCTAssertEqual(old.offset, -40, accuracy: 0.001)
        now = 10
        coordinator.renderFrame()
        XCTAssertEqual(old.offset, -40, accuracy: 0.001)
        let preview = HUDMarqueeNSView(title: b.sessionListTitle, vertical: false, color: .black)
        preview.bind(coordinator: coordinator, generation: nil, sessionID: b.id, title: b.sessionListTitle)
        XCTAssertEqual(preview.offset, 0)
        XCTAssertEqual(coordinator.state.activeSessionID, "b")
        coordinator.update(session: a, generation: token)
        now = 11
        coordinator.renderFrame()
        XCTAssertEqual(old.offset, -40, accuracy: 0.001, "快速 A→B→A 时，退场中的旧 A 不能跟随新的 A 继续滚动")
        let newA = HUDMarqueeNSView(title: a.sessionListTitle, vertical: false, color: .black)
        newA.bind(coordinator: coordinator, generation: token, sessionID: a.id, title: a.sessionListTitle)
        XCTAssertEqual(newA.offset, -60, accuracy: 0.001)
    }

    func testOnlyCurrentAttachedPresentationMayUpdateBackingScale() async throws {
        let fixture = try await fixture()
        defer { fixture.cleanUp() }
        var now = 0.0
        let coordinator = HUDMarqueeCoordinator(clock: { now }, automaticTicks: false, observeSystem: false)
        let a = try fixture.session("a"), b = try fixture.session("b")
        let token = coordinator.beginWindow(layout: .verticalTop, style: .medium, session: a)
        let oldRevision = coordinator.contentRevision
        let old = HUDMarqueeNSView(title: a.sessionListTitle, vertical: true, color: .black)
        old.bind(coordinator: coordinator, generation: token, sessionID: a.id, title: a.sessionListTitle,
                 contentRevision: oldRevision)
        coordinator.setVisible(true, generation: token)
        now = 2
        coordinator.update(session: b, generation: token)
        now = 3
        coordinator.update(session: a, generation: token)
        let revision = coordinator.contentRevision
        coordinator.updateBackingScale(1, generation: token, contentRevision: revision, sessionID: a.id, title: a.sessionListTitle)
        let record = coordinator.state.records[a.id]
        let layout = coordinator.currentFrame!.layout
        now = 4
        // The old view still has the same window token, ID and title, but is an earlier display of A.
        coordinator.updateBackingScale(2, generation: token, contentRevision: oldRevision, sessionID: a.id, title: a.sessionListTitle)
        old.viewDidMoveToWindow()
        old.viewDidChangeBackingProperties()
        let detachedCurrent = HUDMarqueeNSView(title: a.sessionListTitle, vertical: true, color: .black)
        detachedCurrent.bind(coordinator: coordinator, generation: token, sessionID: a.id, title: a.sessionListTitle,
                             contentRevision: revision)
        detachedCurrent.viewDidMoveToWindow()
        detachedCurrent.viewDidChangeBackingProperties()
        for invalid in [CGFloat.nan, .infinity, 0, -1] {
            coordinator.updateBackingScale(invalid, generation: token, contentRevision: revision,
                                           sessionID: a.id, title: a.sessionListTitle)
        }
        XCTAssertTrue(coordinator.currentFrame!.layout === layout)
        XCTAssertEqual(coordinator.currentFrame?.layout.backingScale, 1)
        XCTAssertEqual(coordinator.state.records[a.id], record, "旧回调及非法缩放不能修改进度或活动时钟")
        let phase = coordinator.state.sample(a.id, now: now).phase
        coordinator.updateBackingScale(2, generation: token, contentRevision: revision, sessionID: a.id, title: a.sessionListTitle)
        XCTAssertEqual(coordinator.currentFrame?.layout.backingScale, 2)
        XCTAssertEqual(coordinator.state.sample(a.id, now: now).phase, phase, accuracy: 0.00001)
        XCTAssertEqual(coordinator.state.activeSessionID, a.id)
    }

    func testReleasingVisibleControllerStopsApplicationOwnedClock() async throws {
        let fixture = try await fixture()
        defer { fixture.cleanUp() }
        fixture.model.hudDisplayStyle = .medium
        weak var weakController: HUDPanelController?
        autoreleasepool {
            let controller = HUDPanelController(model: fixture.model, defaults: fixture.defaults)
            weakController = controller
            controller.show()
            XCTAssertTrue(fixture.model.hudMarquee.isTicking)
        }
        XCTAssertNil(weakController)
        XCTAssertFalse(fixture.model.hudMarquee.isTicking)
        XCTAssertNil(fixture.model.hudMarquee.state.activeSessionID)
    }

    func testWindowReplacementsHideAndModeChangesRetainProgress() async throws {
        let fixture = try await fixture()
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.hudDisplayStyle = .medium
        let coordinator = model.hudMarquee
        let controller = HUDPanelController(model: model, defaults: fixture.defaults)
        defer { controller.hide() }
        controller.show()
        try await fixture.waitUntil { coordinator.state.activeSessionID != nil }
        let id = try XCTUnwrap(coordinator.state.activeSessionID)
        controller.hide()
        let phase = try XCTUnwrap(coordinator.state.records[id]?.phase)
        XCTAssertGreaterThan(phase, 0)
        XCTAssertFalse(coordinator.isTicking)
        let previous = controller.window
        model.hudLayoutMode = .verticalTop
        try await fixture.waitUntil { controller.window !== previous }
        XCTAssertNil(coordinator.state.activeSessionID)
        XCTAssertEqual(coordinator.state.records[id]?.phase, phase)
        XCTAssertEqual(controller.window?.frame.size, CGSize(width: 40, height: 244))
        controller.show()
        XCTAssertEqual(coordinator.state.activeSessionID, id)
        model.hudDisplayStyle = .compact
        try await fixture.waitUntil { !coordinator.isTicking }
        let paused = try XCTUnwrap(coordinator.state.records[id]?.phase)
        model.hudDisplayStyle = .medium
        try await fixture.waitUntil { coordinator.state.activeSessionID == id }
        let resumed = try XCTUnwrap(coordinator.state.records[id])
        XCTAssertGreaterThanOrEqual(resumed.phase, paused)
        XCTAssertLessThan((resumed.phase - paused) * resumed.cycleLength, 2, "真实窗口首次绘制可能重新配置屏幕缩放，但不能重置或补算隐藏时间")
        controller.hide()
        model.deleteSession(id)
        XCTAssertNil(coordinator.state.records[id])
        XCTAssertNil(AppModel(defaults: fixture.defaults).hudMarquee.state.activeSessionID)
    }
}

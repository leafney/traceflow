import XCTest
@testable import TraceflowCore

final class CarouselSchedulerTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000)

    func testIdleIncludedSessionNeverEntersRotation() {
        var scheduler = CarouselScheduler()
        let decision = scheduler.updateSessions([session("a", 0), session("b", 1, state: .running)], now: base)

        XCTAssertEqual(decision?.sessionID, "b")
        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(5), displayDuration: 5))
    }

    func testAllIdleShowsPlaceholderOnlyOnce() {
        var scheduler = CarouselScheduler()
        let sessions = [session("a", 0), session("b", 1)]

        XCTAssertEqual(scheduler.updateSessions(sessions, now: base)?.reason, .placeholder)
        XCTAssertNil(scheduler.updateSessions(sessions, now: base.addingTimeInterval(1)))
        XCTAssertNil(scheduler.currentSessionID)
    }

    func testFirstActiveSessionImmediatelyLeavesPlaceholder() {
        var scheduler = CarouselScheduler()
        var a = session("a", 0)
        _ = scheduler.updateSessions([a], now: base)
        a.state = .running
        _ = scheduler.updateSessions([a], now: base.addingTimeInterval(1), updateExistingStates: false)

        let decision = scheduler.reportStateChange(sessionID: "a", newState: .running, stateChanged: true, now: base.addingTimeInterval(1))

        XCTAssertEqual(decision?.sessionID, "a")
        XCTAssertEqual(decision?.reason, .initial)
        XCTAssertEqual(decision?.animated, false)
    }

    func testCurrentIdleImmediatelySelectsNextActiveSession() {
        var scheduler = CarouselScheduler()
        let a = session("a", 0, state: .running)
        let b = session("b", 1, state: .completed)
        _ = scheduler.updateSessions([a, b], now: base)

        let decision = scheduler.reportStateChange(sessionID: "a", newState: .idle, stateChanged: true, now: base.addingTimeInterval(1))

        XCTAssertEqual(decision?.sessionID, "b")
        XCTAssertEqual(scheduler.displayedSince, base.addingTimeInterval(1))
    }

    func testRedPreemptsAndQueuedRedWinsAfterCurrentIdles() {
        var scheduler = CarouselScheduler()
        let a = session("a", 0, state: .running)
        let b = session("b", 1, state: .running)
        let c = session("c", 2, state: .running)
        _ = scheduler.updateSessions([a, b, c], now: base)

        XCTAssertEqual(
            scheduler.reportStateChange(sessionID: "b", newState: .attention, stateChanged: true, now: base.addingTimeInterval(1))?.reason,
            .redPreemption
        )
        XCTAssertNil(scheduler.reportStateChange(sessionID: "c", newState: .attention, stateChanged: true, now: base.addingTimeInterval(2)))

        let decision = scheduler.reportStateChange(sessionID: "b", newState: .idle, stateChanged: true, now: base.addingTimeInterval(3))
        XCTAssertEqual(decision?.sessionID, "c")
        XCTAssertEqual(decision?.reason, .selectionChanged)
    }

    func testNormalEventCannotPreemptCurrentRed() {
        var scheduler = CarouselScheduler()
        let a = session("a", 0, state: .attention)
        let b = session("b", 1)
        _ = scheduler.updateSessions([a, b], now: base)

        XCTAssertNil(scheduler.reportStateChange(sessionID: "b", newState: .running, stateChanged: true, now: base.addingTimeInterval(1)))
        XCTAssertEqual(scheduler.currentSessionID, "a")
    }

    func testRepeatedStateDoesNotResetDisplayedSinceOrQueue() {
        var scheduler = CarouselScheduler()
        let a = session("a", 0, state: .running)
        let b = session("b", 1)
        _ = scheduler.updateSessions([a, b], now: base)

        XCTAssertNil(scheduler.reportStateChange(sessionID: "b", newState: .running, stateChanged: true, now: base.addingTimeInterval(1)))
        XCTAssertNil(scheduler.reportStateChange(sessionID: "b", newState: .running, stateChanged: false, now: base.addingTimeInterval(2)))
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(5), displayDuration: 5)?.sessionID, "b")
    }

    func testClosingCurrentUsesPlaceholderAndIdleReenableStaysPlaceholder() {
        var scheduler = CarouselScheduler()
        var a = session("a", 0, state: .running)
        var b = session("b", 1)
        _ = scheduler.updateSessions([a, b], now: base)

        a.persisted.isIncludedInHUD = false
        XCTAssertEqual(scheduler.updateSessions([a, b], now: base.addingTimeInterval(1))?.reason, .placeholder)
        a.persisted.isIncludedInHUD = true
        XCTAssertEqual(scheduler.updateSessions([a, b], now: base.addingTimeInterval(2))?.sessionID, "a")

        a.persisted.isIncludedInHUD = false
        b.persisted.isIncludedInHUD = true
        b.state = .running
        XCTAssertEqual(scheduler.updateSessions([a, b], now: base.addingTimeInterval(3))?.sessionID, "b")
    }

    func testOneEligibleSessionDoesNotAnimateToItself() {
        var scheduler = CarouselScheduler()
        _ = scheduler.updateSessions([session("a", 0, state: .running)], now: base)

        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(5), displayDuration: 5))
        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(10), displayDuration: 5))
    }

    private func session(_ id: String, _ index: Int, state: SessionRuntimeState = .idle) -> SessionSnapshot {
        SessionSnapshot(
            persisted: PersistedSession(sessionID: id, isIncludedInHUD: true, discoveredAt: base, lastUpdatedAt: base, rotationIndex: index),
            state: state
        )
    }
}

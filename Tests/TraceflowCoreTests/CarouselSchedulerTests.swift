import XCTest
@testable import TraceflowCore

final class CarouselSchedulerTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000)

    func testIdleIncludedSessionNeverEntersRotation() {
        var scheduler = CarouselScheduler()
        let decision = scheduler.updateSessions([session("a", 0), session("b", 1, state: .running)], now: base)

        XCTAssertEqual(decision?.sessionID, "b")
        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(5)))
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
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(5))?.sessionID, "b")
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

        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(5)))
        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(10)))
    }

    func testYellowPreemptsGreenAndInterruptedGreenReturnsWithFullCycle() {
        var scheduler = CarouselScheduler()
        scheduler.updateTimingConfiguration(.init(mode: .byState))
        _ = scheduler.updateSessions([session("green", 0, state: .running), session("yellow", 1)], now: base)
        let decision = scheduler.reportStateChange(sessionID: "yellow", newState: .completed, stateChanged: true, now: base.addingTimeInterval(1))
        XCTAssertEqual(decision?.reason, .yellowPreemption)
        XCTAssertEqual(decision?.cycle?.durationSnapshot, 4)
        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(5)))
        let resumed = scheduler.advance(now: base.addingTimeInterval(5.2))
        XCTAssertEqual(resumed?.sessionID, "green")
        XCTAssertEqual(resumed?.reason, .greenQueue)
        XCTAssertEqual(resumed?.cycle?.durationSnapshot, 2)
    }

    func testQueuedColorsDrainRedThenYellowThenGreen() {
        var scheduler = CarouselScheduler()
        _ = scheduler.updateSessions([session("current", 0, state: .attention), session("green", 1), session("yellow", 2), session("red", 3)], now: base)
        _ = scheduler.reportStateChange(sessionID: "green", newState: .running, stateChanged: true, now: base.addingTimeInterval(1))
        _ = scheduler.reportStateChange(sessionID: "yellow", newState: .completed, stateChanged: true, now: base.addingTimeInterval(2))
        _ = scheduler.reportStateChange(sessionID: "red", newState: .attention, stateChanged: true, now: base.addingTimeInterval(3))
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(5))?.sessionID, "red")
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(10.2))?.sessionID, "yellow")
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(15.6))?.sessionID, "green")
    }

    func testCurrentRedDemotionYieldsToQueuedRed() {
        var scheduler = CarouselScheduler()
        _ = scheduler.updateSessions([session("a", 0, state: .attention), session("b", 1)], now: base)
        _ = scheduler.reportStateChange(sessionID: "b", newState: .attention, stateChanged: true, now: base.addingTimeInterval(1))
        let decision = scheduler.reportStateChange(sessionID: "a", newState: .running, stateChanged: true, now: base.addingTimeInterval(2))
        XCTAssertEqual(decision?.sessionID, "b")
        let resumed = scheduler.advance(now: base.addingTimeInterval(7.2))
        XCTAssertEqual(resumed?.sessionID, "a")
        XCTAssertEqual(resumed?.reason, .greenQueue)
    }

    func testPreemptionMatrix() {
        let cases: [(SessionRuntimeState, SessionRuntimeState, Bool)] = [
            (.attention, .attention, false), (.attention, .completed, false), (.attention, .running, false),
            (.completed, .attention, true), (.completed, .completed, false), (.completed, .running, false),
            (.running, .attention, true), (.running, .completed, true), (.running, .running, false)
        ]
        for (current, incoming, preempts) in cases {
            var scheduler = CarouselScheduler()
            _ = scheduler.updateSessions([session("a", 0, state: current), session("b", 1)], now: base)
            let decision = scheduler.reportStateChange(sessionID: "b", newState: incoming, stateChanged: true, now: base.addingTimeInterval(1))
            XCTAssertEqual(decision?.sessionID == "b", preempts, "\(current) / \(incoming)")
        }
    }

    func testEnablingActiveYellowPreemptsGreen() {
        var scheduler = CarouselScheduler()
        let green = session("a", 0, state: .running)
        var yellow = session("b", 1, state: .completed)
        yellow.persisted.isIncludedInHUD = false
        _ = scheduler.updateSessions([green, yellow], now: base)
        yellow.persisted.isIncludedInHUD = true
        let decision = scheduler.updateSessions([green, yellow], now: base.addingTimeInterval(1))
        XCTAssertEqual(decision?.sessionID, "b")
        XCTAssertEqual(decision?.reason, .yellowPreemption)
    }

    private func session(_ id: String, _ index: Int, state: SessionRuntimeState = .idle) -> SessionSnapshot {
        SessionSnapshot(
            persisted: PersistedSession(sessionID: id, isIncludedInHUD: true, discoveredAt: base, lastUpdatedAt: base, rotationIndex: index),
            state: state
        )
    }
}

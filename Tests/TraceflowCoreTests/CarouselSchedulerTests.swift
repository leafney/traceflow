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

    func testYellowWaitsForGreenProtectionAndInterruptedGreenReturnsWithFullCycle() {
        var scheduler = CarouselScheduler()
        scheduler.updateTimingConfiguration(.init(mode: .byState))
        _ = scheduler.updateSessions([session("green", 0, state: .running), session("yellow", 1)], now: base)
        let decision = scheduler.reportStateChange(sessionID: "yellow", newState: .completed, stateChanged: true, now: base.addingTimeInterval(1))
        XCTAssertNil(decision)
        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(1.9)))
        let yellow = scheduler.advance(now: base.addingTimeInterval(2))
        XCTAssertEqual(yellow?.reason, .yellowAfterProtection)
        XCTAssertEqual(yellow?.cycle?.durationSnapshot, 4)
        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(6)))
        let resumed = scheduler.advance(now: base.addingTimeInterval(6.2))
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
            (.running, .attention, true), (.running, .completed, false), (.running, .running, false)
        ]
        for (current, incoming, preempts) in cases {
            var scheduler = CarouselScheduler()
            _ = scheduler.updateSessions([session("a", 0, state: current), session("b", 1)], now: base)
            let decision = scheduler.reportStateChange(sessionID: "b", newState: incoming, stateChanged: true, now: base.addingTimeInterval(1))
            XCTAssertEqual(decision?.sessionID == "b", preempts, "\(current) / \(incoming)")
        }
    }

    func testEnablingActiveYellowWaitsForGreenProtection() {
        var scheduler = CarouselScheduler()
        let green = session("a", 0, state: .running)
        var yellow = session("b", 1, state: .completed)
        yellow.persisted.isIncludedInHUD = false
        _ = scheduler.updateSessions([green, yellow], now: base)
        yellow.persisted.isIncludedInHUD = true
        let decision = scheduler.updateSessions([green, yellow], now: base.addingTimeInterval(1))
        XCTAssertNil(decision)
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(2.5))?.sessionID, "b")
    }

    func testUniformGreenProtectionUsesHalfOfEachConfiguredDuration() {
        for duration in [3.0, 5.0, 10.0] {
            var scheduler = CarouselScheduler()
            scheduler.updateTimingConfiguration(.init(mode: .uniform, uniformDuration: duration))
            _ = scheduler.updateSessions([session("green", 0, state: .running), session("yellow", 1)], now: base)
            XCTAssertNil(scheduler.reportStateChange(sessionID: "yellow", newState: .completed, stateChanged: true, now: base.addingTimeInterval(0.5)))
            XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(duration / 2 - 0.01)))
            XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(duration / 2))?.sessionID, "yellow")
        }
    }

    func testYellowArrivingAfterProtectionPreemptsImmediately() {
        var scheduler = CarouselScheduler()
        scheduler.updateTimingConfiguration(.init(mode: .uniform, uniformDuration: 10))
        _ = scheduler.updateSessions([session("green", 0, state: .running), session("yellow", 1)], now: base)
        let decision = scheduler.reportStateChange(sessionID: "yellow", newState: .completed, stateChanged: true, now: base.addingTimeInterval(7))
        XCTAssertEqual(decision?.sessionID, "yellow")
        XCTAssertEqual(decision?.reason, .yellowPreemption)
    }

    func testOlderQueuedYellowWinsWhenNewYellowArrivesAfterProtection() {
        var scheduler = CarouselScheduler()
        scheduler.updateTimingConfiguration(.init(mode: .uniform, uniformDuration: 10))
        _ = scheduler.updateSessions([session("green", 0, state: .running), session("first", 1), session("second", 2)], now: base)
        XCTAssertNil(scheduler.reportStateChange(sessionID: "first", newState: .completed, stateChanged: true, now: base.addingTimeInterval(1)))
        let decision = scheduler.reportStateChange(sessionID: "second", newState: .completed, stateChanged: true, now: base.addingTimeInterval(5.1))
        XCTAssertEqual(decision?.sessionID, "first")
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(15.4))?.sessionID, "second")
    }

    func testCurrentGreenTurnsYellowImmediatelyDuringProtection() {
        var scheduler = CarouselScheduler()
        scheduler.updateTimingConfiguration(.init(mode: .byState))
        _ = scheduler.updateSessions([session("green", 0, state: .running)], now: base)
        let decision = scheduler.reportStateChange(sessionID: "green", newState: .completed, stateChanged: true, now: base.addingTimeInterval(0.5))
        XCTAssertEqual(decision?.sessionID, "green")
        XCTAssertEqual(decision?.cycle?.runtimeState, .completed)
        XCTAssertEqual(decision?.cycle?.durationSnapshot, 4)
    }

    func testRedStillPreemptsProtectedGreen() {
        var scheduler = CarouselScheduler()
        scheduler.updateTimingConfiguration(.init(mode: .uniform, uniformDuration: 10))
        _ = scheduler.updateSessions([session("green", 0, state: .running), session("yellow", 1), session("red", 2)], now: base)
        XCTAssertNil(scheduler.reportStateChange(sessionID: "yellow", newState: .completed, stateChanged: true, now: base.addingTimeInterval(1)))
        let decision = scheduler.reportStateChange(sessionID: "red", newState: .attention, stateChanged: true, now: base.addingTimeInterval(2))
        XCTAssertEqual(decision?.reason, .redPreemption)
        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(5)))
    }

    func testQueuedRedWinsWhenYellowArrivesBeforeNextTick() {
        var scheduler = schedulerWithQueuedRedAndCurrentGreen()
        let decision = scheduler.reportStateChange(
            sessionID: "yellow",
            newState: .completed,
            stateChanged: true,
            now: base.addingTimeInterval(2.1)
        )
        XCTAssertEqual(decision?.sessionID, "red")
        XCTAssertEqual(decision?.reason, .redQueue)
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(7.4))?.sessionID, "yellow")
    }

    func testQueuedRedPreemptsAtNextTickWithoutWaitingForCurrentDeadline() {
        var scheduler = schedulerWithQueuedRedAndCurrentGreen()
        let decision = scheduler.advance(now: base.addingTimeInterval(2.1))
        XCTAssertEqual(decision?.sessionID, "red")
        XCTAssertEqual(decision?.reason, .redQueue)
        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(2.1)))
    }

    func testYellowQueueKeepsArrivalOrderAndRepeatedStateDoesNotMoveIt() {
        var scheduler = CarouselScheduler()
        scheduler.updateTimingConfiguration(.init(mode: .uniform, uniformDuration: 10))
        _ = scheduler.updateSessions([session("green", 0, state: .running), session("first", 1), session("second", 2)], now: base)
        XCTAssertNil(scheduler.reportStateChange(sessionID: "first", newState: .completed, stateChanged: true, now: base.addingTimeInterval(1)))
        XCTAssertNil(scheduler.reportStateChange(sessionID: "second", newState: .completed, stateChanged: true, now: base.addingTimeInterval(2)))
        XCTAssertNil(scheduler.reportStateChange(sessionID: "first", newState: .completed, stateChanged: false, now: base.addingTimeInterval(3)))
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(5))?.sessionID, "first")
        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(5)))
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(15.2))?.sessionID, "second")
    }

    func testYellowRemovedBeforeProtectionDoesNotInterruptGreen() {
        var scheduler = CarouselScheduler()
        scheduler.updateTimingConfiguration(.init(mode: .uniform, uniformDuration: 10))
        var yellow = session("yellow", 1)
        let green = session("green", 0, state: .running)
        _ = scheduler.updateSessions([green, yellow], now: base)
        XCTAssertNil(scheduler.reportStateChange(sessionID: "yellow", newState: .completed, stateChanged: true, now: base.addingTimeInterval(1)))
        yellow.state = .completed
        yellow.persisted.isIncludedInHUD = false
        _ = scheduler.updateSessions([green, yellow], now: base.addingTimeInterval(2), updateExistingStates: false)
        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(5)))
        XCTAssertEqual(scheduler.currentSessionID, "green")
    }

    func testCurrentCycleKeepsOriginalProtectionAfterSettingsChange() {
        var scheduler = CarouselScheduler()
        scheduler.updateTimingConfiguration(.init(mode: .uniform, uniformDuration: 10))
        _ = scheduler.updateSessions([session("green", 0, state: .running), session("yellow", 1)], now: base)
        scheduler.updateTimingConfiguration(.init(mode: .uniform, uniformDuration: 3))
        XCTAssertNil(scheduler.reportStateChange(sessionID: "yellow", newState: .completed, stateChanged: true, now: base.addingTimeInterval(1)))
        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(1.5)))
        let decision = scheduler.advance(now: base.addingTimeInterval(5))
        XCTAssertEqual(decision?.sessionID, "yellow")
        XCTAssertEqual(decision?.cycle?.durationSnapshot, 3)
    }

    func testProtectionStartsAfterTitleTransition() {
        var scheduler = CarouselScheduler()
        scheduler.updateTimingConfiguration(.init(mode: .byState))
        _ = scheduler.updateSessions([session("first", 0, state: .completed), session("green", 1, state: .running), session("yellow", 2)], now: base)
        let greenDecision = scheduler.advance(now: base.addingTimeInterval(4))
        XCTAssertEqual(greenDecision?.sessionID, "green")
        XCTAssertEqual(greenDecision?.cycle?.visibleFrom, base.addingTimeInterval(4 + HUDTitleTransition.maximumDuration))
        XCTAssertNil(scheduler.reportStateChange(sessionID: "yellow", newState: .completed, stateChanged: true, now: base.addingTimeInterval(5)))
        let protectionEnd = base.addingTimeInterval(6 + HUDTitleTransition.maximumDuration)
        XCTAssertNil(scheduler.advance(now: protectionEnd.addingTimeInterval(-0.01)))
        XCTAssertEqual(scheduler.advance(now: protectionEnd)?.sessionID, "yellow")
    }

    func testOldProtectionCannotSwitchAfterCurrentGreenChangesState() {
        var scheduler = CarouselScheduler()
        scheduler.updateTimingConfiguration(.init(mode: .uniform, uniformDuration: 10))
        _ = scheduler.updateSessions([session("green", 0, state: .running), session("yellow", 1)], now: base)
        XCTAssertNil(scheduler.reportStateChange(sessionID: "yellow", newState: .completed, stateChanged: true, now: base.addingTimeInterval(1)))
        let decision = scheduler.reportStateChange(sessionID: "green", newState: .attention, stateChanged: true, now: base.addingTimeInterval(2))
        XCTAssertEqual(decision?.sessionID, "green")
        XCTAssertEqual(decision?.cycle?.runtimeState, .attention)
        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(5)))
    }

    private func session(_ id: String, _ index: Int, state: SessionRuntimeState = .idle) -> SessionSnapshot {
        SessionSnapshot(
            persisted: PersistedSession(sessionID: id, isIncludedInHUD: true, discoveredAt: base, lastUpdatedAt: base, rotationIndex: index),
            state: state
        )
    }

    private func schedulerWithQueuedRedAndCurrentGreen() -> CarouselScheduler {
        var scheduler = CarouselScheduler()
        let current = session("current", 0, state: .attention)
        let red = session("red", 1)
        let yellow = session("yellow", 2)
        _ = scheduler.updateSessions([current, red, yellow], now: base)
        _ = scheduler.reportStateChange(sessionID: "red", newState: .attention, stateChanged: true, now: base.addingTimeInterval(1))
        // A session-list refresh can update the state mirror before the current
        // display cycle is reconciled. The queued red must retain priority.
        var changedCurrent = current
        changedCurrent.state = .running
        var changedRed = red
        changedRed.state = .attention
        _ = scheduler.updateSessions([changedCurrent, changedRed, yellow], now: base.addingTimeInterval(2))
        return scheduler
    }
}

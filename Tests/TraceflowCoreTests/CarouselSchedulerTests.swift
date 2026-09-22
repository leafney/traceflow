import XCTest
@testable import TraceflowCore

final class CarouselSchedulerTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000)

    func testIdleSessionsRotateFairly() {
        var scheduler = CarouselScheduler()
        XCTAssertEqual(scheduler.updateSessions([session("a", 0), session("b", 1)], now: base)?.sessionID, "a")
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(5), displayDuration: 5)?.sessionID, "b")
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(10), displayDuration: 5)?.sessionID, "a")
    }

    func testRedPreemptsButSecondRedWaits() {
        var scheduler = CarouselScheduler()
        _ = scheduler.updateSessions([session("a", 0), session("b", 1), session("c", 2)], now: base)
        let first = scheduler.reportStateChange(sessionID: "b", newState: .attention, stateChanged: true, now: base.addingTimeInterval(1))
        XCTAssertEqual(first?.reason, .redPreemption)
        XCTAssertEqual(first?.sessionID, "b")
        XCTAssertNil(scheduler.reportStateChange(sessionID: "c", newState: .attention, stateChanged: true, now: base.addingTimeInterval(2)))
        XCTAssertNil(scheduler.advance(now: base.addingTimeInterval(5), displayDuration: 5))
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(6), displayDuration: 5)?.sessionID, "c")
    }

    func testNormalChangesQueueAndDeduplicate() {
        var scheduler = CarouselScheduler()
        _ = scheduler.updateSessions([session("a", 0), session("b", 1)], now: base)
        XCTAssertNil(scheduler.reportStateChange(sessionID: "b", newState: .running, stateChanged: true, now: base))
        XCTAssertNil(scheduler.reportStateChange(sessionID: "b", newState: .completed, stateChanged: true, now: base))
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(5), displayDuration: 5)?.sessionID, "b")
        XCTAssertEqual(scheduler.advance(now: base.addingTimeInterval(10), displayDuration: 5)?.sessionID, "a")
    }

    func testUncheckingCurrentMovesAndEmptyShowsPlaceholder() {
        var scheduler = CarouselScheduler()
        var a = session("a", 0)
        let b = session("b", 1)
        _ = scheduler.updateSessions([a, b], now: base)
        a.persisted.isIncludedInHUD = false
        XCTAssertEqual(scheduler.updateSessions([a, b], now: base)?.sessionID, "b")
        var excludedB = b
        excludedB.persisted.isIncludedInHUD = false
        XCTAssertEqual(scheduler.updateSessions([a, excludedB], now: base)?.reason, .placeholder)
    }

    func testEnablingFirstSessionFromEmptySelectionDisplaysIt() {
        var scheduler = CarouselScheduler()
        var a = session("a", 0)
        a.persisted.isIncludedInHUD = false
        XCTAssertEqual(scheduler.updateSessions([a], now: base)?.reason, .placeholder)

        a.persisted.isIncludedInHUD = true
        let decision = scheduler.updateSessions([a], now: base.addingTimeInterval(1))

        XCTAssertEqual(decision?.sessionID, "a")
        XCTAssertEqual(decision?.reason, .selectionChanged)
    }

    func testClosingCurrentProjectMovesToEnabledSessionInAnotherProject() {
        var scheduler = CarouselScheduler()
        var a = session("a", 0)
        var b = session("b", 1)
        let c = session("c", 2)
        _ = scheduler.updateSessions([a, b, c], now: base)

        a.persisted.isIncludedInHUD = false
        b.persisted.isIncludedInHUD = false
        let decision = scheduler.updateSessions([a, b, c], now: base.addingTimeInterval(1))

        XCTAssertEqual(decision?.sessionID, "c")
        XCTAssertEqual(decision?.reason, .selectionChanged)
    }

    private func session(_ id: String, _ index: Int, state: SessionRuntimeState = .idle) -> SessionSnapshot {
        SessionSnapshot(
            persisted: PersistedSession(sessionID: id, isIncludedInHUD: true, discoveredAt: base, lastUpdatedAt: base, rotationIndex: index),
            state: state
        )
    }
}

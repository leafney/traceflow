import XCTest
@testable import TraceflowCore

final class CarouselTimingTests: XCTestCase {
    func testDurationsAndInvalidUniformValue() {
        for value in [3.0, 5.0, 10.0] {
            let config = CarouselTimingConfiguration(mode: .uniform, uniformDuration: value)
            for state in [SessionRuntimeState.attention, .completed, .running] {
                XCTAssertEqual(config.duration(for: state), value)
            }
        }
        XCTAssertEqual(CarouselTimingConfiguration(mode: .uniform, uniformDuration: 7).duration(for: .running), 5)
        XCTAssertNil(CarouselTimingConfiguration().duration(for: .idle))
        let priority = CarouselTimingConfiguration(mode: .byState)
        XCTAssertEqual(priority.duration(for: .attention), 6)
        XCTAssertEqual(priority.duration(for: .completed), 4)
        XCTAssertEqual(priority.duration(for: .running), 2)
    }

    func testExistingCycleKeepsTimingWhenConfigurationChanges() {
        let now = Date(timeIntervalSince1970: 1_000)
        var scheduler = CarouselScheduler()
        scheduler.updateTimingConfiguration(.init(mode: .uniform, uniformDuration: 10))
        let sessions = ["a", "b"].enumerated().map { index, id in
            SessionSnapshot(persisted: PersistedSession(sessionID: id, isIncludedInHUD: true, discoveredAt: now, lastUpdatedAt: now, rotationIndex: index), state: .running)
        }
        _ = scheduler.updateSessions(sessions, now: now)
        let original = scheduler.currentCycle
        scheduler.updateTimingConfiguration(.init(mode: .byState))
        XCTAssertEqual(scheduler.currentCycle, original)
        XCTAssertNil(scheduler.advance(now: now.addingTimeInterval(9)))
        let next = scheduler.advance(now: now.addingTimeInterval(10))
        XCTAssertEqual(next?.cycle?.durationSnapshot, 2)
        XCTAssertEqual(next?.cycle?.visibleFrom, now.addingTimeInterval(10 + HUDTitleTransition.maximumDuration))
    }
}

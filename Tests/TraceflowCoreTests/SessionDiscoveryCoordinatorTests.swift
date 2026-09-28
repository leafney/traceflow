import XCTest
@testable import TraceflowCore

final class SessionDiscoveryCoordinatorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)

    func testOpenPollCloseAndReopen() {
        var coordinator = SessionDiscoveryCoordinator()
        XCTAssertEqual(coordinator.openSettings(now: start), .automatic)
        XCTAssertNil(coordinator.poll(now: start.addingTimeInterval(20), isSettingsVisible: true))
        XCTAssertNil(coordinator.finish(now: start))
        XCTAssertNil(coordinator.poll(now: start.addingTimeInterval(14), isSettingsVisible: true))
        XCTAssertNil(coordinator.poll(now: start.addingTimeInterval(15), isSettingsVisible: false))
        XCTAssertEqual(coordinator.openSettings(now: start.addingTimeInterval(16)), .automatic)
        XCTAssertNil(coordinator.finish(now: start.addingTimeInterval(16)))
        XCTAssertEqual(coordinator.poll(now: start.addingTimeInterval(31), isSettingsVisible: true), .automatic)
    }

    func testManualWaitsForAutomaticAndRunsOnlyOnce() {
        var coordinator = SessionDiscoveryCoordinator()
        XCTAssertEqual(coordinator.openSettings(now: start), .automatic)
        XCTAssertNil(coordinator.requestManual())
        XCTAssertNil(coordinator.requestManual())
        XCTAssertEqual(coordinator.finish(now: start.addingTimeInterval(2)), .manual)
        XCTAssertNil(coordinator.poll(now: start.addingTimeInterval(20), isSettingsVisible: true))
        XCTAssertNil(coordinator.finish(now: start.addingTimeInterval(22)))
        XCTAssertEqual(coordinator.poll(now: start.addingTimeInterval(37), isSettingsVisible: true), .automatic)
    }

    func testSuppressionExpiresOrClearsAndIsNotPersisted() {
        var coordinator = SessionDiscoveryCoordinator()
        coordinator.suppress(["a", "b"], now: start)
        XCTAssertFalse(coordinator.permitsAutomaticImport("a", now: start.addingTimeInterval(599)))
        XCTAssertTrue(coordinator.permitsAutomaticImport("a", now: start.addingTimeInterval(600)))
        XCTAssertFalse(coordinator.permitsAutomaticImport("b", now: start.addingTimeInterval(599)))
        coordinator.clearSuppression()
        XCTAssertTrue(coordinator.permitsAutomaticImport("b", now: start))

        var afterRestart = SessionDiscoveryCoordinator()
        XCTAssertTrue(afterRestart.permitsAutomaticImport("a", now: start))
    }
}

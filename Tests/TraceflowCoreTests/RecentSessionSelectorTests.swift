import XCTest
@testable import TraceflowCore

final class RecentSessionSelectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testWindowBoundaryAndUnknownOrFutureTime() {
        let sessions = [
            session("recent", age: 599.999),
            session("boundary", age: 600),
            session("future", age: -1),
            session("unknown", age: nil),
            session("new", age: 0),
        ]

        XCTAssertEqual(RecentSessionSelector.select(from: sessions, now: now).map(\.id), ["new", "recent"])
    }

    func testCrossProjectEnabledSessionsAndStableTieBreakWithoutLimit() {
        var sessions = (0..<120).map { index in
            session(String(format: "%03d", index), age: 30, project: index.isMultiple(of: 2) ? "A" : "B", included: index.isMultiple(of: 3))
        }
        sessions.append(session("latest", age: 1, project: "C", included: true))

        let selected = RecentSessionSelector.select(from: sessions.reversed(), now: now)

        XCTAssertEqual(selected.count, 121)
        XCTAssertEqual(selected.first?.id, "latest")
        XCTAssertEqual(selected.dropFirst().map(\.id), (0..<120).map { String(format: "%03d", $0) })
        XCTAssertTrue(selected.first?.persisted.isIncludedInHUD == true)
    }

    private func session(_ id: String, age: TimeInterval?, project: String = "A", included: Bool = false) -> SessionSnapshot {
        let persisted = PersistedSession(
            sessionID: id,
            projectName: project,
            isIncludedInHUD: included,
            discoveredAt: now,
            lastUpdatedAt: now,
            lastActivityAt: age.map { now.addingTimeInterval(-$0) },
            rotationIndex: 0
        )
        return SessionSnapshot(persisted: persisted)
    }
}

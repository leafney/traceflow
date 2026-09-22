import XCTest
@testable import TraceflowCore

final class SessionProjectGrouperTests: XCTestCase {
    func testGroupsSameNormalizedPathAndSortsNewestSessionFirst() {
        let groups = SessionProjectGrouper.groups(from: [
            snapshot("old", path: "/a/demo/", sort: 10, rotation: 1),
            snapshot("new", path: "/a/other/../demo", sort: 20, rotation: 2),
        ])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, "/a/demo")
        XCTAssertEqual(groups[0].sessions.map(\.id), ["new", "old"])
    }

    func testKeepsSameNamedProjectsAtDifferentPathsSeparate() {
        let groups = SessionProjectGrouper.groups(from: [
            snapshot("a", path: "/a/demo", sort: 10),
            snapshot("b", path: "/b/demo", sort: 20),
        ])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.displayName)), ["demo"])
        XCTAssertEqual(Set(groups.map(\.id)), ["/a/demo", "/b/demo"])
    }

    func testGroupsMissingPathsAsUnknownProject() {
        let groups = SessionProjectGrouper.groups(from: [
            snapshot("a", path: nil, sort: 10),
            snapshot("b", path: "  ", sort: 20),
        ])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, SessionProjectGrouper.unknownProjectKey)
        XCTAssertEqual(groups[0].displayName, "未知项目")
        XCTAssertNil(groups[0].projectPath)
    }

    func testNewestSessionMovesItsProjectToTop() {
        let groups = SessionProjectGrouper.groups(from: [
            snapshot("older-project", path: "/work/older", sort: 20),
            snapshot("new-session", path: "/work/latest", sort: 30),
            snapshot("old-session", path: "/work/latest", sort: 10),
        ])

        XCTAssertEqual(groups.map(\.displayName), ["latest", "older"])
        XCTAssertEqual(groups[0].sessions.map(\.id), ["new-session", "old-session"])
    }

    func testUsesStableFallbackSortKeys() {
        let groups = SessionProjectGrouper.groups(from: [
            snapshot("a", path: "/work/demo", sort: 10, rotation: 1),
            snapshot("b", path: "/work/demo", sort: 10, rotation: 2),
            snapshot("c", path: "/work/demo", sort: 10, rotation: 2),
        ])

        XCTAssertEqual(groups[0].sessions.map(\.id), ["b", "c", "a"])
    }

    func testComputesNonePartialAndAllSelectionStates() {
        let none = SessionProjectGrouper.groups(from: [snapshot("a", included: false)])[0]
        let partial = SessionProjectGrouper.groups(from: [snapshot("a", included: false), snapshot("b", included: true)])[0]
        let all = SessionProjectGrouper.groups(from: [snapshot("a", included: true), snapshot("b", included: true)])[0]

        XCTAssertEqual(none.selectionState, .none)
        XCTAssertEqual(partial.selectionState, .partial)
        XCTAssertEqual(all.selectionState, .all)
        XCTAssertEqual(partial.enabledCount, 1)
        XCTAssertEqual(partial.totalCount, 2)
    }

    private func snapshot(
        _ id: String,
        path: String? = "/work/app",
        sort: TimeInterval = 10,
        rotation: Int = 0,
        included: Bool = false
    ) -> SessionSnapshot {
        let date = Date(timeIntervalSince1970: sort)
        return SessionSnapshot(persisted: PersistedSession(
            sessionID: id,
            projectPath: path,
            projectName: path.flatMap { TitleBuilder.projectName(from: $0) },
            isIncludedInHUD: included,
            discoveredAt: date,
            lastUpdatedAt: date,
            settingsListSortAt: date,
            rotationIndex: rotation
        ))
    }
}

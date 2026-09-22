import XCTest
@testable import TraceflowCore

final class CodexAppServerClientTests: XCTestCase {
    func testDecodesThreadListWithoutReadingPreviewOrTurns() throws {
        let result: [String: Any] = [
            "data": [[
                "id": "thread-1",
                "name": "修复登录问题",
                "cwd": "/work/sample",
                "createdAt": 100,
                "updatedAt": 200,
                "preview": "不应保存的用户消息",
                "turns": [["id": "turn-1"]],
            ]],
            "nextCursor": "next-page",
        ]

        let page = try CodexThreadListPage.decode(from: result)

        XCTAssertEqual(page.nextCursor, "next-page")
        XCTAssertEqual(page.threads, [
            CodexThreadSummary(
                id: "thread-1",
                name: "修复登录问题",
                cwd: "/work/sample",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200)
            ),
        ])
    }

    func testRejectsMalformedThreadList() {
        XCTAssertThrowsError(try CodexThreadListPage.decode(from: ["data": [["id": "missing-fields"]]]))
    }

    func testImportAddsThreadsAndPreservesExistingHUDSelection() {
        let existing = PersistedSession(
            sessionID: "existing",
            projectPath: "/old/path",
            projectName: "path",
            isIncludedInHUD: false,
            discoveredAt: Date(timeIntervalSince1970: 10),
            lastUpdatedAt: Date(timeIntervalSince1970: 20),
            rotationIndex: 3
        )
        let threads = [
            CodexThreadSummary(
                id: "existing",
                name: "更新后的名称",
                cwd: "/new/project",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 30)
            ),
            CodexThreadSummary(
                id: "new",
                name: nil,
                cwd: "/work/new-project",
                createdAt: Date(timeIntervalSince1970: 40),
                updatedAt: Date(timeIntervalSince1970: 50)
            ),
        ]

        let result = CodexThreadImporter.merge(threads, into: [existing], nextRotationIndex: 4)

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertEqual(result.nextRotationIndex, 5)
        XCTAssertEqual(result.sessions.first?.sessionID, "existing")
        XCTAssertEqual(result.sessions.first?.isIncludedInHUD, false)
        XCTAssertEqual(result.sessions.first?.codexThreadName, "更新后的名称")
        XCTAssertEqual(result.sessions.first?.settingsListSortAt, Date(timeIntervalSince1970: 30))
        XCTAssertEqual(result.sessions.last?.projectName, "new-project")
        XCTAssertEqual(result.sessions.last?.isIncludedInHUD, false)
        XCTAssertEqual(result.sessions.last?.settingsListSortAt, Date(timeIntervalSince1970: 50))
    }

    func testRepeatedImportPreservesSelectionAndExistingSortDate() {
        let originalSortDate = Date(timeIntervalSince1970: 15)
        let existing = PersistedSession(
            sessionID: "existing",
            isIncludedInHUD: true,
            discoveredAt: Date(timeIntervalSince1970: 10),
            lastUpdatedAt: Date(timeIntervalSince1970: 20),
            settingsListSortAt: originalSortDate,
            rotationIndex: 0
        )
        let thread = CodexThreadSummary(
            id: "existing",
            name: "名称",
            cwd: "/work/app",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let result = CodexThreadImporter.merge([thread], into: [existing], nextRotationIndex: 1)

        XCTAssertEqual(result.sessions.first?.isIncludedInHUD, true)
        XCTAssertEqual(result.sessions.first?.settingsListSortAt, originalSortDate)
        XCTAssertEqual(result.sessions.first?.lastUpdatedAt, Date(timeIntervalSince1970: 100))
    }

    func testOfficialSourcesExcludeInternalThreads() {
        XCTAssertEqual(SessionSourcePolicy.allowedAppServerKinds, ["cli", "vscode", "appServer"])
        for internalSource in ["exec", "unknown", "subAgent", "subAgentReview", "subAgentOther"] {
            XCTAssertFalse(SessionSourcePolicy.isAllowedAppServerKind(internalSource))
            XCTAssertTrue(SessionSourcePolicy.isInternalHookSource(internalSource))
        }
        XCTAssertTrue(SessionSourcePolicy.isAllowedAppServerKind(nil))
        XCTAssertFalse(SessionSourcePolicy.isInternalHookSource(nil))
    }

    func testImportDefensivelyFiltersExplicitInternalSources() {
        let official = CodexThreadSummary(id: "official", name: nil, cwd: "/work/app", createdAt: .now, updatedAt: .now, sourceKind: "cli")
        let internalThread = CodexThreadSummary(id: "internal", name: nil, cwd: "/work/app", createdAt: .now, updatedAt: .now, sourceKind: "subAgentReview")
        let result = CodexThreadImporter.merge([official, internalThread], into: [], nextRotationIndex: 0)
        XCTAssertEqual(result.sessions.map(\.sessionID), ["official"])
        XCTAssertEqual(result.addedCount, 1)
    }
}

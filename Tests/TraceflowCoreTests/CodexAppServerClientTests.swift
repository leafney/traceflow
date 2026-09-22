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
        XCTAssertEqual(result.sessions.last?.projectName, "new-project")
        XCTAssertEqual(result.sessions.last?.isIncludedInHUD, true)
    }
}

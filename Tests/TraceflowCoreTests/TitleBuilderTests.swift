import XCTest
@testable import TraceflowCore

final class TitleBuilderTests: XCTestCase {
    func testCustomTitlePriorityAndDefaultFallbackPreserveHUDProject() {
        let date = Date(timeIntervalSince1970: 123)
        let persisted = PersistedSession(
            sessionID: "session", projectName: "项目", codexThreadName: "原始名称",
            customTitle: " 自定义 👨‍👩‍👧‍👦 ", discoveredAt: date, lastUpdatedAt: date, rotationIndex: 0
        )
        var snapshot = SessionSnapshot(persisted: persisted, conversationSummary: "输入摘要")
        XCTAssertEqual(snapshot.sessionListTitle, "自定义 👨‍👩‍👧‍👦")
        XCTAssertEqual(snapshot.defaultConversationTitle, "输入摘要")
        XCTAssertEqual(snapshot.displayTitle, "项目 · 自定义 👨‍👩‍👧‍👦")
        snapshot.persisted.customTitle = nil
        XCTAssertEqual(snapshot.sessionListTitle, "输入摘要")
        snapshot.persisted.customTitle = " \n "
        snapshot.conversationSummary = " \n "
        XCTAssertEqual(snapshot.defaultConversationTitle, "原始名称")
        XCTAssertEqual(snapshot.sessionListTitle, "原始名称")
        snapshot.persisted.codexThreadName = nil
        XCTAssertNil(snapshot.effectiveConversationTitle)
        XCTAssertEqual(snapshot.sessionListTitle, "未命名会话")
        XCTAssertEqual(snapshot.displayTitle, "项目")
        snapshot.persisted.projectName = nil
        XCTAssertEqual(snapshot.displayTitle, "未知会话")
    }

    func testBuildsAndFallsBackTitle() {
        XCTAssertEqual(TitleBuilder.displayTitle(projectName: "traceflow", conversationSummary: "实现状态跟踪"), "traceflow · 实现状态跟踪")
        XCTAssertEqual(TitleBuilder.displayTitle(projectName: nil, conversationSummary: "实现状态跟踪"), "实现状态跟踪")
        XCTAssertEqual(TitleBuilder.displayTitle(projectName: "traceflow", conversationSummary: nil), "traceflow")
        XCTAssertEqual(TitleBuilder.displayTitle(projectName: nil, conversationSummary: nil), "未知会话")
    }

    func testCleansMarkdownAndLimitsSummary() {
        XCTAssertEqual(TitleBuilder.summary(from: "\n##   实现   状态跟踪\n详情"), "实现 状态跟踪")
        XCTAssertEqual(TitleBuilder.summary(from: "- " + String(repeating: "长", count: 40))?.count, 30)
        XCTAssertNil(TitleBuilder.summary(from: "\n  \n"))
    }

    func testProjectNameUsesLastComponent() {
        XCTAssertEqual(TitleBuilder.projectName(from: "/work/traceflow/"), "traceflow")
    }
}

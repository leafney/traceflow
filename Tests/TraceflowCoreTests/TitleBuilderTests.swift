import XCTest
@testable import TraceflowCore

final class TitleBuilderTests: XCTestCase {
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

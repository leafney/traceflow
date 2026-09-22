import XCTest
@testable import TraceflowCore

final class SessionEventLogFormatterTests: XCTestCase {
    func testFormatsAcceptedTransitionWithStableFieldOrder() {
        XCTAssertEqual(
            SessionEventLogFormatter.stateTransition(
                event: .userPromptSubmit,
                oldState: .completed,
                newState: .running,
                projectName: "traceflow",
                sessionID: "abc123",
                title: "优化 HUD 灯光"
            ),
            "event=UserPromptSubmit state=completed->running project=\"traceflow\" session_id=\"abc123\" title=\"优化 HUD 灯光\""
        )
    }

    func testQuotesEmptyProjectAndTitle() {
        XCTAssertEqual(
            SessionEventLogFormatter.stateTransition(
                event: .stop,
                oldState: .running,
                newState: .completed,
                projectName: "",
                sessionID: "session-1",
                title: ""
            ),
            "event=Stop state=running->completed project=\"\" session_id=\"session-1\" title=\"\""
        )
    }

    func testEscapesQuotesBackslashesAndControlCharactersWithoutPhysicalLineBreaks() {
        let line = SessionEventLogFormatter.stateTransition(
            event: .permissionRequest,
            oldState: .running,
            newState: .attention,
            projectName: "项目\"甲\\乙",
            sessionID: "one\ntwo\rthree\tfour",
            title: "第一行\n第二行\u{0001}"
        )

        XCTAssertEqual(
            line,
            "event=PermissionRequest state=running->attention project=\"项目\\\"甲\\\\乙\" session_id=\"one\\ntwo\\rthree\\tfour\" title=\"第一行\\n第二行\\u{0001}\""
        )
        XCTAssertFalse(line.contains("\n"))
        XCTAssertFalse(line.contains("\r"))
    }
}

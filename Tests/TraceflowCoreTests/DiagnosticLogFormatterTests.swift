import XCTest
@testable import TraceflowCore

final class DiagnosticLogFormatterTests: XCTestCase {
    func testEscapesExternalFieldsAndDoesNotIncludePrompt() {
        let payload = HookPayload(sessionID: "one\ntwo", eventName: .preToolUse, turnID: "turn", toolName: "ask\"user", toolUseID: String(repeating: "x", count: 140), prompt: "绝密选项内容")
        let envelope = HookEnvelope(eventID: "event", capturedUptimeNanoseconds: 42, forwardedAt: .now, payload: payload)
        let line = DiagnosticLogFormatter.event(stage: "forwarder.received", envelope: envelope)
        XCTAssertFalse(line.contains("\n"))
        XCTAssertTrue(line.contains("session_id=\"one\\ntwo\""))
        XCTAssertTrue(line.contains("…[truncated]"))
        XCTAssertFalse(line.contains("绝密选项内容"))
    }

    func testPayloadToolFieldsRoundTrip() throws {
        let payload = HookPayload(sessionID: "session", eventName: .postToolUse, toolName: "request_user_input", toolUseID: "tool-1")
        let decoded = try JSONDecoder().decode(HookPayload.self, from: JSONEncoder().encode(payload))
        XCTAssertEqual(decoded.toolName, "request_user_input")
        XCTAssertEqual(decoded.toolUseID, "tool-1")
    }
}

import XCTest
@testable import TraceflowCore

final class SessionStateMachineTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000)

    func testEventMappingAndFirstSummary() {
        var machine = makeMachine()
        var result = machine.apply(envelope(.userPromptSubmit, uptime: 1, prompt: "# 第一次输入"), now: base)
        XCTAssertEqual(machine.snapshot.state, .running)
        XCTAssertEqual(machine.snapshot.conversationSummary, "第一次输入")
        XCTAssertTrue(result.stateChanged)

        result = machine.apply(envelope(.permissionRequest, uptime: 2), now: base)
        XCTAssertEqual(machine.snapshot.state, .attention)
        XCTAssertTrue(result.stateChanged)

        _ = machine.apply(envelope(.postToolUse, uptime: 3), now: base)
        XCTAssertEqual(machine.snapshot.state, .running)
        _ = machine.apply(envelope(.stop, uptime: 4), now: base)
        XCTAssertEqual(machine.snapshot.state, .completed)
        _ = machine.apply(envelope(.interrupt, uptime: 5), now: base)
        XCTAssertEqual(machine.snapshot.state, .idle)

        _ = machine.apply(envelope(.userPromptSubmit, uptime: 6, prompt: "第二次输入"), now: base)
        XCTAssertEqual(machine.snapshot.conversationSummary, "第一次输入")
    }

    func testCompactionDuplicateAndOldEventAreRejected() {
        var machine = makeMachine()
        let compact = envelope(.sessionStart, uptime: 1, source: "compact")
        XCTAssertEqual(machine.apply(compact, now: base).rejection, .ignoredCompaction)

        let event = envelope(.userPromptSubmit, uptime: 10, id: "same")
        XCTAssertTrue(machine.apply(event, now: base).accepted)
        XCTAssertEqual(machine.apply(event, now: base).rejection, .duplicate)
        XCTAssertEqual(machine.apply(envelope(.stop, uptime: 9), now: base).rejection, .outOfOrder)
    }

    func testCompletionExpiresAtTenMinutes() {
        var machine = makeMachine()
        _ = machine.apply(envelope(.stop, uptime: 1), now: base)
        XCTAssertFalse(machine.expireCompletion(now: base.addingTimeInterval(599)))
        XCTAssertTrue(machine.expireCompletion(now: base.addingTimeInterval(600)))
        XCTAssertEqual(machine.snapshot.state, .idle)
    }

    func testSessionEndKeepsSessionButIdlesIt() {
        var machine = makeMachine()
        _ = machine.apply(envelope(.permissionRequest, uptime: 1), now: base)
        _ = machine.apply(envelope(.sessionEnd, uptime: 2), now: base)
        XCTAssertEqual(machine.snapshot.persisted.sessionID, "s1")
        XCTAssertEqual(machine.snapshot.state, .idle)
    }

    private func makeMachine() -> SessionStateMachine {
        let persisted = PersistedSession(sessionID: "s1", discoveredAt: base, lastUpdatedAt: base, rotationIndex: 0)
        return SessionStateMachine(snapshot: SessionSnapshot(persisted: persisted))
    }

    private func envelope(
        _ event: HookEventName,
        uptime: UInt64,
        id: String = UUID().uuidString,
        source: String? = nil,
        prompt: String? = nil
    ) -> HookEnvelope {
        HookEnvelope(
            eventID: id,
            capturedUptimeNanoseconds: uptime,
            forwardedAt: base,
            payload: HookPayload(sessionID: "s1", cwd: "/work/traceflow", eventName: event, source: source, prompt: prompt)
        )
    }
}

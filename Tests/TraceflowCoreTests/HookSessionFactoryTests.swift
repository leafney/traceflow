import XCTest
@testable import TraceflowCore

final class HookSessionFactoryTests: XCTestCase {
    func testNewHookSessionIsExcludedAndUsesDiscoveryTimeForSettingsSort() {
        let now = Date(timeIntervalSince1970: 123)

        let session = HookSessionFactory.makePersistedSession(
            sessionID: "new-session",
            cwd: "/work/example",
            now: now,
            rotationIndex: 7
        )

        XCTAssertFalse(session.isIncludedInHUD)
        XCTAssertEqual(session.settingsListSortAt, now)
        XCTAssertEqual(session.projectName, "example")
        XCTAssertEqual(session.rotationIndex, 7)
    }

    func testLaterHookEventsDoNotChangeSettingsSortTime() {
        let discoveredAt = Date(timeIntervalSince1970: 123)
        let persisted = HookSessionFactory.makePersistedSession(
            sessionID: "new-session",
            cwd: "/work/example",
            now: discoveredAt,
            rotationIndex: 0
        )
        var machine = SessionStateMachine(snapshot: SessionSnapshot(persisted: persisted))
        let later = Date(timeIntervalSince1970: 456)
        let envelope = HookEnvelope(
            eventID: "event",
            capturedUptimeNanoseconds: 1,
            forwardedAt: later,
            payload: HookPayload(sessionID: "new-session", cwd: "/work/example", eventName: .userPromptSubmit)
        )

        _ = machine.apply(envelope, now: later)

        XCTAssertEqual(machine.snapshot.persisted.lastUpdatedAt, later)
        XCTAssertEqual(machine.snapshot.persisted.settingsListSortAt, discoveredAt)
    }
}

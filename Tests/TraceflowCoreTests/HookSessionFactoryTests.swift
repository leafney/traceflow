import XCTest
@testable import TraceflowCore

final class HookSessionFactoryTests: XCTestCase {
    func testNewHookSessionCanBeIncludedWithoutChangingDiscoveryMetadata() {
        let now = Date(timeIntervalSince1970: 123)
        let session = HookSessionFactory.makePersistedSession(
            sessionID: "enabled-session", cwd: "/work/example", now: now,
            rotationIndex: 7, isIncludedInHUD: true
        )

        XCTAssertTrue(session.isIncludedInHUD)
        XCTAssertEqual(session.projectName, "example")
        XCTAssertEqual(session.lastActivityAt, now)
        XCTAssertEqual(session.settingsListSortAt, now)
        XCTAssertEqual(session.rotationIndex, 7)
    }

    func testLaterHookEventsPreserveBothIncludedAndExcludedSelections() {
        let discoveredAt = Date(timeIntervalSince1970: 123)
        let later = Date(timeIntervalSince1970: 456)
        for included in [false, true] {
            let persisted = HookSessionFactory.makePersistedSession(
                sessionID: "session", cwd: "/work/example", now: discoveredAt,
                rotationIndex: 0, isIncludedInHUD: included
            )
            var machine = SessionStateMachine(snapshot: SessionSnapshot(persisted: persisted))
            let envelope = HookEnvelope(
                eventID: "event", capturedUptimeNanoseconds: 1, forwardedAt: later,
                payload: HookPayload(sessionID: "session", cwd: "/work/example", eventName: .userPromptSubmit)
            )

            let result = machine.apply(envelope, now: later)

            XCTAssertTrue(result.accepted)
            XCTAssertEqual(machine.snapshot.persisted.isIncludedInHUD, included)
            XCTAssertEqual(machine.snapshot.persisted.lastUpdatedAt, later)
            XCTAssertEqual(machine.snapshot.persisted.settingsListSortAt, discoveredAt)
        }
    }

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

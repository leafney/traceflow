import XCTest
@testable import TraceflowCore

final class SessionStoreTests: XCTestCase {
    func testRoundTripsPersistedFieldsOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SessionStore(url: directory.appendingPathComponent("sessions.json"))
        let date = Date(timeIntervalSince1970: 123)
        let session = PersistedSession(sessionID: "s1", projectPath: "/work/app", projectName: "app", isIncludedInHUD: false, discoveredAt: date, lastUpdatedAt: date, rotationIndex: 4)
        try store.save([session])
        XCTAssertEqual(try store.load(), [session])
        let text = try String(contentsOf: directory.appendingPathComponent("sessions.json"))
        XCTAssertFalse(text.contains("conversationSummary"))
        XCTAssertFalse(text.contains("runtimeState"))
        try? FileManager.default.removeItem(at: directory)
    }

    func testCorruptFileIsNotOverwrittenOnLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("sessions.json")
        try Data("bad".utf8).write(to: url)
        let store = SessionStore(url: url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try String(contentsOf: url), "bad")
        try? FileManager.default.removeItem(at: directory)
    }
}

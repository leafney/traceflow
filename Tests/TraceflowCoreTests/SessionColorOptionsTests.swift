import XCTest
@testable import TraceflowCore

final class SessionColorOptionsTests: XCTestCase {
    func testStableVectorsAndDistinctOptions() {
        let vectors = [
            "session-a": ["#D77B23", "#1597A4", "#598C6C", "#67B7A0", "#597344", "#5587A6"],
            "session-b": ["#67B7A0", "#E4A665", "#477EE8", "#E16F7F", "#C46182", "#6C7FE8"],
            "": ["#A68140", "#597344", "#E16F7F", "#E4A665", "#7869B5", "#477EE8"]
        ]
        for (id, expected) in vectors {
            let options = SessionColorOptions.options(sessionID: id, currentColor: nil)
            XCTAssertEqual(options.map(\.hex), expected)
            XCTAssertEqual(Set(options.map(\.hex)).count, 6)
            XCTAssertFalse(options.contains(where: \.isSelected))
            XCTAssertEqual(options, SessionColorOptions.options(sessionID: id, currentColor: nil))
        }
        XCTAssertNotEqual(vectors["session-a"], vectors["session-b"])
    }

    func testCurrentColorSelectionAndReplacement() {
        let base = SessionColorOptions.options(sessionID: "session-a", currentColor: nil)
        let existing = SessionColorOptions.options(sessionID: "session-a", currentColor: " #1597a4 ")
        XCTAssertEqual(existing.map(\.hex), base.map(\.hex))
        XCTAssertEqual(existing.map(\.isSelected), [false, true, false, false, false, false])
        let custom = SessionColorOptions.options(sessionID: "session-a", currentColor: "#123456")
        XCTAssertEqual(custom.map(\.hex), ["#123456", "#1597A4", "#598C6C", "#67B7A0", "#597344", "#5587A6"])
        XCTAssertEqual(custom.map(\.isSelected), [true, false, false, false, false, false])
        XCTAssertEqual(SessionColorOptions.options(sessionID: "session-a", currentColor: "invalid"), base)
        XCTAssertEqual(Set(custom.map(\.hex)).count, 6)
    }
    func testSelectionMarkContrastForLightAndDarkColors() {
        XCTAssertTrue(SessionColorOptions.usesDarkSelectionMark(for: "#FFFFFF"))
        XCTAssertTrue(SessionColorOptions.usesDarkSelectionMark(for: "#E4A665"))
        XCTAssertTrue(SessionColorOptions.usesDarkSelectionMark(for: "#67B7A0"))
        XCTAssertFalse(SessionColorOptions.usesDarkSelectionMark(for: "#000000"))
        XCTAssertFalse(SessionColorOptions.usesDarkSelectionMark(for: "#303080"))
        XCTAssertFalse(SessionColorOptions.usesDarkSelectionMark(for: "invalid"))
    }

}

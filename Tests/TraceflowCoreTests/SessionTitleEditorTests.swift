import XCTest
@testable import TraceflowCore

final class SessionTitleEditorTests: XCTestCase {
    func testRejectsEmptyAndInternalControls() {
        for raw in ["", " \n\t "] {
            XCTAssertThrowsError(try SessionTitleEditor.normalizedTitle(raw)) {
                XCTAssertEqual($0 as? SessionTitleValidationError, .empty)
            }
        }
        for raw in ["一\n二", "一\r二", "一\t二", "一\u{2028}二", "一\u{0000}二"] {
            XCTAssertThrowsError(try SessionTitleEditor.normalizedTitle(raw)) {
                XCTAssertEqual($0 as? SessionTitleValidationError, .multipleLinesOrControls)
            }
        }
    }

    func testPreservesMarkdownSpacesAndLongTitlesAfterTrimming() throws {
        let title = "## 标题  " + String(repeating: "长", count: 40)
        XCTAssertEqual(try SessionTitleEditor.normalizedTitle(" \n" + title + "\n "), title)
    }

    func testLengthUsesCharactersIncludingCombinedEmoji() throws {
        for character in ["中", "👨‍👩‍👧‍👦", "e\u{301}"] {
            let valid = String(repeating: character, count: 100)
            XCTAssertEqual(try SessionTitleEditor.normalizedTitle(valid), valid)
            XCTAssertThrowsError(try SessionTitleEditor.normalizedTitle(valid + character)) {
                XCTAssertEqual($0 as? SessionTitleValidationError, .tooLong)
            }
        }
    }
}

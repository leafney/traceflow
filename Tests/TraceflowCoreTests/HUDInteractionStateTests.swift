import XCTest
@testable import TraceflowCore

final class HUDInteractionStateTests: XCTestCase {
    func testRestoredPinBlocksDragBeforeFirstDisplay() {
        var interaction = HUDInteractionState(isPinned: true)

        XCTAssertTrue(interaction.ignoresMouseEvents)
        XCTAssertFalse(interaction.canBeginDrag)
        XCTAssertFalse(interaction.beginDrag())
        XCTAssertFalse(interaction.isDragging)
    }

    func testPinDuringDragCancelsItAndDoesNotCommitLateMouseUp() {
        var interaction = HUDInteractionState(isPinned: false)
        XCTAssertTrue(interaction.beginDrag())
        XCTAssertTrue(interaction.isDragging)

        XCTAssertTrue(interaction.setPinned(true))
        XCTAssertFalse(interaction.isDragging)
        XCTAssertFalse(interaction.finishDrag())
        XCTAssertTrue(interaction.ignoresMouseEvents)

        XCTAssertFalse(interaction.setPinned(false))
        XCTAssertFalse(interaction.finishDrag())
        XCTAssertTrue(interaction.beginDrag())
        XCTAssertTrue(interaction.finishDrag())
    }

    func testPinWithoutDragDoesNotRequestCancellation() {
        var interaction = HUDInteractionState(isPinned: false)

        XCTAssertFalse(interaction.setPinned(true))
        XCTAssertTrue(interaction.ignoresMouseEvents)
        XCTAssertFalse(interaction.isDragging)
        XCTAssertFalse(interaction.setPinned(true))
        XCTAssertFalse(interaction.setPinned(false))
        XCTAssertFalse(interaction.ignoresMouseEvents)
    }
}

import XCTest
@testable import TraceflowCore

final class HUDGeometryStateTests: XCTestCase {
    func testRepeatedEdgeExpansionAndCollapseKeepsOriginalReference() throws {
        let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)
        for layout in HUDLayoutMode.allCases {
            let compact = CGRect(origin: layout == .horizontal ? .zero : CGPoint(x: 0, y: 420), size: HUDBackgroundAppearance(95).size(layout))
            let reference = HUDBackgroundAppearance.referenceFrame(compact, layout: layout)
            var state = HUDGeometryState(transparency: 95, pinned: false)
            state.restoreReference(reference)
            for _ in 0..<3 {
                state.setTransparency(80)
                let expanded = try XCTUnwrap(state.target(layout: layout, visible: visible))
                XCTAssertEqual(expanded, HUDPositionGeometry.clamped(reference, to: visible))
                state.setTransparency(95)
                XCTAssertEqual(state.target(layout: layout, visible: visible), compact)
                XCTAssertEqual(state.reference, reference)
            }
        }
    }

    func testHiddenDragCancellationRejectsLateMouseUpAndAllowsRestore() throws {
        let saved = CGRect(x: 100, y: 50, width: 420, height: 40)
        var state = HUDGeometryState(transparency: 80, pinned: false)
        state.restoreReference(saved)
        XCTAssertTrue(state.beginDrag())
        state.setTransparency(95)
        XCTAssertNil(state.target(layout: .horizontal, visible: nil))
        state.cancelDrag()
        XCTAssertFalse(state.finishDrag(frame: CGRect(x: 700, y: 50, width: 420, height: 40), moved: true, layout: .horizontal))
        state.restoreReference(saved)
        XCTAssertEqual(state.target(layout: .horizontal, visible: nil), CGRect(x: 140, y: 50, width: 380, height: 40))
        XCTAssertTrue(state.beginDrag())
    }

    func testDeferredGeometryKeepsLatestTargetAndCommitsDragUsingVisibleShape() {
        var state = HUDGeometryState(transparency: 80, pinned: false)
        state.restoreReference(CGRect(x: 100, y: 50, width: 420, height: 40))
        XCTAssertTrue(state.beginDrag())
        for value in [95, 89, 100] {
            state.setTransparency(value)
            // Also used by geometry updates when accessibility settings change.
            XCTAssertNil(state.target(layout: .horizontal, visible: nil))
        }
        let dragged = CGRect(x: 200, y: 70, width: 420, height: 40)
        XCTAssertTrue(state.finishDrag(frame: dragged, moved: true, layout: .horizontal))
        XCTAssertEqual(state.reference, dragged)
        XCTAssertEqual(state.target(layout: .horizontal, visible: nil), CGRect(x: 240, y: 70, width: 380, height: 40))
    }

    func testPinCancelsDeferredDragWithoutCommittingIt() {
        var state = HUDGeometryState(transparency: 95, pinned: false)
        let reference = CGRect(x: 100, y: 50, width: 420, height: 40)
        state.restoreReference(reference)
        XCTAssertTrue(state.beginDrag())
        state.setTransparency(80)
        XCTAssertTrue(state.setPinned(true))
        XCTAssertFalse(state.finishDrag(frame: .zero, moved: true, layout: .horizontal))
        XCTAssertEqual(state.reference, reference)
        XCTAssertEqual(state.target(layout: .horizontal, visible: nil), reference)
        XCTAssertTrue(state.interaction.ignoresMouseEvents)
    }
}

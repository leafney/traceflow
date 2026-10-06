import XCTest
@testable import TraceflowCore

final class HUDGeometryStateTests: XCTestCase {
    func testManualModeRoundTripsAtScreenEdgesPreserveReference() throws {
        let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)
        for layout in HUDLayoutMode.allCases {
            let reference = CGRect(x: -20, y: 500,
                                   width: layout.isHorizontal ? 420 : 40,
                                   height: layout.isHorizontal ? 40 : 420)
            var state = HUDGeometryState(transparency: 100, pinned: false, iconVisibilityMode: .alwaysShow)
            state.restoreReference(reference)
            let expanded = try XCTUnwrap(state.target(layout: layout, visible: visible))
            var collapsed: CGRect?
            for _ in 0..<3 {
                state.setIconVisibilityMode(.alwaysHide)
                let current = try XCTUnwrap(state.target(layout: layout, visible: visible))
                XCTAssertEqual(current.size, layout.isHorizontal ? CGSize(width: 380, height: 40) : CGSize(width: 40, height: 380))
                if let collapsed { XCTAssertEqual(current, collapsed) }
                collapsed = current
                state.setTransparency(0)
                XCTAssertEqual(state.target(layout: layout, visible: visible), current)
                state.setIconVisibilityMode(.alwaysShow)
                XCTAssertEqual(state.target(layout: layout, visible: visible), expanded)
                XCTAssertEqual(state.reference, reference)
            }
        }
    }

    func testDragDefersLatestIconModeUntilVisibleShapeIsCommitted() {
        var state = HUDGeometryState(transparency: 0, pinned: false)
        state.restoreReference(CGRect(x: 100, y: 200, width: 420, height: 40))
        XCTAssertTrue(state.beginDrag())
        for mode in [HUDIconVisibilityMode.alwaysHide, .alwaysShow, .alwaysHide] {
            state.setIconVisibilityMode(mode)
            XCTAssertNil(state.target(layout: .horizontalRight, visible: nil))
        }
        let dragged = CGRect(x: 200, y: 250, width: 420, height: 40)
        XCTAssertTrue(state.finishDrag(frame: dragged, moved: true, layout: .horizontalRight))
        XCTAssertEqual(state.reference, dragged)
        XCTAssertEqual(state.target(layout: .horizontalRight, visible: nil), CGRect(x: 240, y: 250, width: 380, height: 40))
        XCTAssertEqual(state.transparency, 0)
        XCTAssertEqual(state.iconVisibilityMode, .alwaysHide)
    }

    func testRepeatedEdgeExpansionAndCollapseKeepsOriginalReference() throws {
        let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)
        for layout in HUDLayoutMode.allCases {
            let compact = CGRect(origin: layout == .horizontalRight ? .zero : CGPoint(x: 0, y: 420), size: HUDBackgroundAppearance(95).size(layout))
            let reference = HUDBackgroundAppearance.referenceFrame(compact, layout: layout)
            var state = HUDGeometryState(transparency: 95, pinned: false)
            state.restoreReference(reference)
            for _ in 0..<3 {
                state.setTransparency(79)
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
        var state = HUDGeometryState(transparency: 79, pinned: false)
        state.restoreReference(saved)
        XCTAssertTrue(state.beginDrag())
        state.setTransparency(95)
        XCTAssertNil(state.target(layout: .horizontalRight, visible: nil))
        state.cancelDrag()
        XCTAssertFalse(state.finishDrag(frame: CGRect(x: 700, y: 50, width: 420, height: 40), moved: true, layout: .horizontalRight))
        state.restoreReference(saved)
        XCTAssertEqual(state.target(layout: .horizontalRight, visible: nil), CGRect(x: 140, y: 50, width: 380, height: 40))
        XCTAssertTrue(state.beginDrag())
    }

    func testDeferredGeometryKeepsLatestTargetAndCommitsDragUsingVisibleShape() {
        var state = HUDGeometryState(transparency: 79, pinned: false)
        state.restoreReference(CGRect(x: 100, y: 50, width: 420, height: 40))
        XCTAssertTrue(state.beginDrag())
        for value in [95, 89, 100] {
            state.setTransparency(value)
            // Also used by geometry updates when accessibility settings change.
            XCTAssertNil(state.target(layout: .horizontalRight, visible: nil))
        }
        let dragged = CGRect(x: 200, y: 70, width: 420, height: 40)
        XCTAssertTrue(state.finishDrag(frame: dragged, moved: true, layout: .horizontalRight))
        XCTAssertEqual(state.reference, dragged)
        XCTAssertEqual(state.target(layout: .horizontalRight, visible: nil), CGRect(x: 240, y: 70, width: 380, height: 40))
    }

    func testPinCancelsDeferredDragWithoutCommittingIt() {
        var state = HUDGeometryState(transparency: 95, pinned: false)
        let reference = CGRect(x: 100, y: 50, width: 420, height: 40)
        state.restoreReference(reference)
        XCTAssertTrue(state.beginDrag())
        state.setTransparency(79)
        XCTAssertTrue(state.setPinned(true))
        XCTAssertFalse(state.finishDrag(frame: .zero, moved: true, layout: .horizontalRight))
        XCTAssertEqual(state.reference, reference)
        XCTAssertEqual(state.target(layout: .horizontalRight, visible: nil), reference)
        XCTAssertTrue(state.interaction.ignoresMouseEvents)
    }
}

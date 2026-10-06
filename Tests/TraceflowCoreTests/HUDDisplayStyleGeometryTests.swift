import XCTest
import TraceflowCore

final class HUDDisplayStyleGeometryTests: XCTestCase {
    func testCompactSizesAndReferenceRoundTripInAllLayouts() {
        for layout in HUDLayoutMode.allCases {
            let reference = CGRect(x: 200, y: 300, width: layout.isHorizontal ? 420 : 40, height: layout.isHorizontal ? 40 : 420)
            var geometry = HUDGeometryState(transparency: 10, pinned: false)
            geometry.restoreReference(reference)
            for _ in 0..<10 {
                geometry.setDisplayStyle(.compact)
                let compact = geometry.target(layout: layout, visible: nil)!
                XCTAssertEqual(compact.size, layout.isHorizontal ? CGSize(width: 144, height: 40) : CGSize(width: 40, height: 144))
                XCTAssertEqual(HUDBackgroundAppearance.referenceFrame(compact, layout: layout), reference)
                for value in [0, 80, 100] {
                    geometry.setTransparency(value)
                    geometry.setIconVisibilityMode(.alwaysHide)
                    XCTAssertEqual(geometry.target(layout: layout, visible: nil), compact)
                }
                geometry.setDisplayStyle(.standard)
                geometry.setIconVisibilityMode(.alwaysShow)
                XCTAssertEqual(geometry.target(layout: layout, visible: nil), reference)
            }
            geometry.setDisplayStyle(.compact)
            XCTAssertTrue(geometry.beginDrag())
            let dragged = CGRect(x: 500, y: 600, width: layout.isHorizontal ? 144 : 40, height: layout.isHorizontal ? 40 : 144)
            XCTAssertTrue(geometry.finishDrag(frame: dragged, moved: true, layout: layout))
            XCTAssertEqual(geometry.target(layout: layout, visible: nil), dragged)
        }
    }
}

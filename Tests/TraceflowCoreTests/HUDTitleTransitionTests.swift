import XCTest
@testable import TraceflowCore

final class HUDTitleTransitionTests: XCTestCase {
    func testNonAnimatedDecisionDoesNotMoveTitle() {
        XCTAssertEqual(HUDTitleTransition.style(shouldAnimate: false, reduceMotion: false), .none)
    }

    func testAnimatedDecisionUsesDirectionalSlide() {
        XCTAssertEqual(HUDTitleTransition.style(shouldAnimate: true, reduceMotion: false), .slide)
    }

    func testReducedMotionAlwaysUsesFade() {
        XCTAssertEqual(HUDTitleTransition.style(shouldAnimate: false, reduceMotion: true), .fade)
        XCTAssertEqual(HUDTitleTransition.style(shouldAnimate: true, reduceMotion: true), .fade)
    }
}

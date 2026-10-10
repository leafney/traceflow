import XCTest
import TraceflowCore

final class HUDTitleMarqueeStateTests: XCTestCase {
    func testSessionsPauseIndependentlyAndSamplingDoesNotAccumulateTwice() {
        var state = HUDTitleMarqueeState()
        state.configure("a", title: "same", textLength: 176, now: 0)
        state.configure("b", title: "same", textLength: 136, now: 0)
        state.activate("a", now: 0)
        XCTAssertEqual(state.sample("a", now: 2).offset, -40, accuracy: 0.0001)
        XCTAssertEqual(state.sample("a", now: 2).offset, -40, accuracy: 0.0001)
        state.activate("b", now: 2)
        state.activate("a", now: 3)
        XCTAssertEqual(state.sample("a", now: 3).offset, -40, accuracy: 0.0001)
        XCTAssertEqual(state.sample("b", now: 100).offset, -20, accuracy: 0.0001)
        XCTAssertEqual(state.sample("a", now: 4).offset, -60, accuracy: 0.0001)
        state.pauseActive(now: 4)
        XCTAssertEqual(state.sample("a", now: 100).offset, -60, accuracy: 0.0001)
    }

    func testReconfigurationMapsRelativePhaseAndShortLayoutPreservesIt() {
        var state = HUDTitleMarqueeState()
        state.configure("a", title: "title", textLength: 176, now: 0)
        state.activate("a", now: 0)
        state.configure("a", title: "title", textLength: 276, now: 4)
        XCTAssertEqual(state.sample("a", now: 4).offset, -120, accuracy: 0.0001)
        state.activate("a", now: 4)
        XCTAssertEqual(state.sample("a", now: 5).offset, -140, accuracy: 0.0001)
        state.configure("a", title: "title", textLength: 88, now: 5)
        XCTAssertEqual(state.sample("a", now: 99).offset, 0)
        state.configure("a", title: "title", textLength: 276, now: 99)
        XCTAssertEqual(state.sample("a", now: 99).offset, -140, accuracy: 0.0001)
    }

    func testBoundariesWrapAndInvalidInputsStayStatic() {
        for length in [87.0, 88, 88.1, .nan, .infinity, -1] {
            var state = HUDTitleMarqueeState()
            state.configure("a", title: "title", textLength: length, now: 0)
            state.activate("a", now: 0)
            XCTAssertEqual(state.activeSessionID != nil, length == 88.1)
        }
        var state = HUDTitleMarqueeState()
        state.configure("a", title: "title", textLength: 176, now: 0)
        state.activate("a", now: 0)
        XCTAssertEqual(state.sample("a", now: 9.99).offset, -199.8, accuracy: 0.0001)
        XCTAssertEqual(state.sample("a", now: 10).offset, 0, accuracy: 0.0001)
        XCTAssertEqual(state.sample("a", now: 10.01).offset, -0.2, accuracy: 0.0001)
        state.activate("a", now: .nan)
        XCTAssertNil(state.activeSessionID)
    }

    func testBackgroundRenameAndDeletionOnlyResetAffectedRecords() {
        var state = HUDTitleMarqueeState()
        state.configure("a", title: "old", textLength: 176, now: 0)
        state.configure("b", title: "other", textLength: 176, now: 0)
        state.activate("a", now: 0)
        state.pauseActive(now: 4)
        state.synchronizeTitles(["a": "new", "b": "other"], now: 8)
        XCTAssertEqual(state.records["a"]?.phase, 0)
        state.activate("b", now: 8)
        state.synchronizeTitles(["a": "new"], now: 10)
        XCTAssertNil(state.activeSessionID)
        XCTAssertNil(state.records["b"])
        XCTAssertNotNil(state.records["a"])
    }

    func testRepeatedSameConfigurationAndActivationKeepOriginalClock() {
        var state = HUDTitleMarqueeState()
        state.configure("a", title: "title", textLength: 176, now: 0)
        state.activate("a", now: 0)
        state.configure("a", title: "title", textLength: 176, now: 1)
        state.activate("a", now: 1)
        XCTAssertEqual(state.sample("a", now: 2).offset, -40, accuracy: 0.0001)
    }
}

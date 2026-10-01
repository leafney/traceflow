import XCTest
@testable import TraceflowCore

final class HUDLightAnimationTests: XCTestCase {
    func testAttentionPhaseUsesUrgentHoldAndDarkPause() {
        let progress: [Double] = [0, 0.075, 0.15, 0.55, 0.625, 0.70, 0.99]
        let expected: [Double] = [0, 0.5, 1, 1, 0.5, 0, 0]

        for (value, result) in zip(progress, expected) {
            XCTAssertEqual(HUDLightAnimation.phase(for: .attention, referenceTime: value * 0.56), result, accuracy: 0.000_001)
        }

        let samples: [(progress: Double, body: Double, glow: Double, scale: Double)] = [
            (0.075, 0.775, 0.5, 1),
            (0.3, 1, 1, 1.1),
            (0.85, 0.55, 0, 0.9)
        ]
        for sample in samples {
            let visual = HUDLightAnimation.parameters(for: .attention, isActive: true, referenceTime: 0.56 * sample.progress, reduceMotion: false)
            XCTAssertEqual(visual.bodyOpacity, sample.body, accuracy: 0.000_001)
            XCTAssertEqual(visual.glowIntensity, sample.glow, accuracy: 0.000_001)
            XCTAssertEqual(visual.scale, sample.scale, accuracy: 0.000_001)
            XCTAssertFalse(visual.isTimelinePaused)
        }
    }

    func testRunningAndCompletedUseSmoothWave() {
        for state in [SessionRuntimeState.running, .completed] {
            XCTAssertEqual(HUDLightAnimation.phase(for: state, referenceTime: 0), 0, accuracy: 0.000_001)
            let period = state == .running ? 2.30 : 2.80
            XCTAssertEqual(HUDLightAnimation.phase(for: state, referenceTime: period * 0.25), 0.5, accuracy: 0.000_001)
            XCTAssertEqual(HUDLightAnimation.phase(for: state, referenceTime: period * 0.5), 1, accuracy: 0.000_001)
            XCTAssertEqual(HUDLightAnimation.phase(for: state, referenceTime: period * 0.75), 0.5, accuracy: 0.000_001)
        }
    }

    func testScaleRangeAndGlowModeIndependentAnimation() {
        let low = HUDLightAnimation.parameters(for: .running, isActive: true, referenceTime: 0, reduceMotion: false)
        let middle = HUDLightAnimation.parameters(for: .running, isActive: true, referenceTime: 2.30 * 0.25, reduceMotion: false)
        let high = HUDLightAnimation.parameters(for: .running, isActive: true, referenceTime: 2.30 * 0.5, reduceMotion: false)

        XCTAssertEqual(low.scale, 0.9, accuracy: 0.000_001)
        XCTAssertEqual(middle.scale, 1.0, accuracy: 0.000_001)
        XCTAssertEqual(high.scale, 1.1, accuracy: 0.000_001)
        XCTAssertEqual(low.bodyOpacity, 0.55, accuracy: 0.000_001)
        XCTAssertEqual(middle.bodyOpacity, 0.775, accuracy: 0.000_001)
        XCTAssertEqual(high.bodyOpacity, 1, accuracy: 0.000_001)
        XCTAssertEqual(low.glowIntensity, 0, accuracy: 0.000_001)
        XCTAssertEqual(middle.glowIntensity, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(high.glowIntensity, 1, accuracy: 0.000_001)
        for visual in [low, middle, high] {
            XCTAssertFalse(visual.isTimelinePaused)
        }
    }

    func testCompletedBodyAndGlowBreatheTogether() {
        let samples: [(time: Double, body: Double, glow: Double, scale: Double)] = [
            (0, 0.55, 0, 0.9),
            (0.7, 0.775, 0.5, 1),
            (1.4, 1, 1, 1.1),
            (2.1, 0.775, 0.5, 1)
        ]
        for sample in samples {
            let visual = HUDLightAnimation.parameters(for: .completed, isActive: true, referenceTime: sample.time, reduceMotion: false)
            XCTAssertEqual(visual.bodyOpacity, sample.body, accuracy: 0.000_001)
            XCTAssertEqual(visual.glowIntensity, sample.glow, accuracy: 0.000_001)
            XCTAssertEqual(visual.scale, sample.scale, accuracy: 0.000_001)
            XCTAssertFalse(visual.isTimelinePaused)
        }
    }

    func testInactiveAndReduceMotionVisualsAreStatic() {
        for state in [SessionRuntimeState.attention, .completed, .running] {
            for reduceMotion in [false, true] {
                let inactive = HUDLightAnimation.parameters(for: state, isActive: false, referenceTime: 1, reduceMotion: reduceMotion)
                XCTAssertEqual(inactive, HUDLightVisualParameters(scale: 1, bodyOpacity: 0.18, glowIntensity: 0, isTimelinePaused: true))
            }
            let reduced = HUDLightAnimation.parameters(for: state, isActive: true, referenceTime: 1, reduceMotion: true)
            XCTAssertEqual(reduced, HUDLightVisualParameters(scale: 1, bodyOpacity: 1, glowIntensity: 1, isTimelinePaused: true))
        }
    }

    func testNegativeReferenceTimeHasValidPhase() {
        let phase = HUDLightAnimation.phase(for: .running, referenceTime: -0.575)
        XCTAssertGreaterThanOrEqual(phase, 0)
        XCTAssertLessThanOrEqual(phase, 1)
    }
}

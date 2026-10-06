import XCTest
@testable import TraceflowCore

final class HUDBackgroundAppearanceTests: XCTestCase {
    func testReversalPreservesPositionAndVelocityInEveryLayout() {
        for layout in HUDLayoutMode.allCases {
            let reference = CGRect(origin: CGPoint(x: 100, y: 200), size: HUDPositionGeometry.size(for: layout))
            let compact = HUDBackgroundAppearance(80).displayFrame(reference, layout: layout)
            let shrinking = HUDSizeTransition(start: reference, target: compact, initialIconFraction: 1, targetIconFraction: 0)
            let middle = shrinking.sample(elapsed: 0.08)
            let velocity = shrinking.iconVelocity(elapsed: 0.08)
            let reversal = HUDSizeTransition(start: middle.frame, target: reference, initialIconFraction: middle.iconFraction,
                                             targetIconFraction: 1, initialIconVelocity: velocity)
            XCTAssertEqual(reversal.sample(elapsed: 0).frame, middle.frame)
            XCTAssertEqual(reversal.sample(elapsed: 0).iconFraction, middle.iconFraction)
            XCTAssertEqual(reversal.iconVelocity(elapsed: 0), velocity, accuracy: 0.000001)
            let first = reversal.sample(elapsed: 0.000001)
            XCTAssertEqual((first.iconFraction - middle.iconFraction) / 0.000001, velocity, accuracy: 0.01)
            XCTAssertLessThan(first.iconFraction, middle.iconFraction, "反向先平滑刹车，而非突然停止前一方向的运动")
            let end = reversal.sample(elapsed: reversal.activeDuration)
            XCTAssertEqual(end.frame, reference)
            XCTAssertEqual(end.iconFraction, 1)
            XCTAssertTrue(end.complete)
            XCTAssertEqual(reversal.iconVelocity(elapsed: reversal.activeDuration), 0)
        }
    }

    func testShortTransitionsSettleSoonerWithMinimumDuration() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 40)
        let half = HUDSizeTransition(start: frame, target: CGRect(x: 0, y: 0, width: 420, height: 40),
                                     initialIconFraction: 0.5, targetIconFraction: 1)
        XCTAssertEqual(half.activeDuration, 0.1)
        XCTAssertFalse(half.sample(elapsed: 0.05).complete)
        XCTAssertTrue(half.sample(elapsed: 0.1).complete)
        let short = HUDSizeTransition(start: frame, target: frame, initialIconFraction: 0.99, targetIconFraction: 1)
        XCTAssertEqual(short.activeDuration, 0.05)
        XCTAssertFalse(short.sample(elapsed: 0.01).complete)
        XCTAssertTrue(short.sample(elapsed: 0.05).complete)
        XCTAssertTrue(short.sample(elapsed: 0, reduceMotion: true).complete)
        XCTAssertEqual(short.sample(elapsed: 0, reduceMotion: true).iconFraction, 1)
    }

    func testInheritedVelocityNeverExceedsIconAndSizeBounds() {
        for layout in HUDLayoutMode.allCases {
            for fraction in [0.001, 0.5, 0.999] {
                for target in [0.0, 1.0] {
                    for velocity in [-7.5, 7.5] {
                        let start = CGRect(x: layout == .horizontalRight ? 100 + 40 * (1 - fraction) : 100,
                                           y: layout == .verticalTop ? 200 + 40 * (1 - fraction) : 200,
                                           width: layout.isHorizontal ? 380 + 40 * fraction : 40,
                                           height: layout.isHorizontal ? 40 : 380 + 40 * fraction)
                        let reference = CGRect(origin: CGPoint(x: 100, y: 200), size: HUDPositionGeometry.size(for: layout))
                        let end = target == 1 ? reference : HUDBackgroundAppearance(80).displayFrame(reference, layout: layout)
                        let transition = HUDSizeTransition(start: start, target: end, initialIconFraction: fraction,
                                                           targetIconFraction: target, initialIconVelocity: velocity)
                        for step in 0...100 {
                            let sample = transition.sample(elapsed: transition.activeDuration * Double(step) / 100)
                            XCTAssertGreaterThanOrEqual(sample.iconFraction, -0.000001)
                            XCTAssertLessThanOrEqual(sample.iconFraction, 1.000001)
                            let length = layout.isHorizontal ? sample.frame.width : sample.frame.height
                            XCTAssertGreaterThanOrEqual(length, 380 - 0.000001)
                            XCTAssertLessThanOrEqual(length, 420 + 0.000001)
                            if layout == .horizontalRight { XCTAssertEqual(sample.frame.maxX, 520, accuracy: 0.000001) }
                            if layout == .verticalTop { XCTAssertEqual(sample.frame.maxY, 620, accuracy: 0.000001) }
                        }
                    }
                }
            }
        }
    }

    func testIconModesAcrossTransparencyBoundariesAndFourLayouts() {
        for mode in HUDIconVisibilityMode.allCases {
            for value in [0, 79, 80, 81, 100] {
                let hidden = mode == .alwaysHide || (mode == .automatic && value >= 80)
                let appearance = HUDBackgroundAppearance(value, iconVisibilityMode: mode)
                XCTAssertEqual(appearance.compact, hidden)
                XCTAssertEqual(appearance.backgroundAlpha, 1 - Double(value) / 100)
                XCTAssertEqual(appearance.materialAlpha, Double(value) / 100)
                for layout in HUDLayoutMode.allCases {
                    let reference = CGRect(x: 100, y: 200,
                                           width: layout.isHorizontal ? 420 : 40,
                                           height: layout.isHorizontal ? 40 : 420)
                    let expected = CGRect(x: hidden && layout == .horizontalRight ? 140 : 100,
                                          y: hidden && layout == .verticalTop ? 240 : 200,
                                          width: layout.isHorizontal ? (hidden ? 380 : 420) : 40,
                                          height: layout.isHorizontal ? 40 : (hidden ? 380 : 420))
                    XCTAssertEqual(appearance.size(layout), expected.size)
                    XCTAssertEqual(appearance.displayFrame(reference, layout: layout), expected)
                    XCTAssertEqual(HUDBackgroundAppearance.referenceFrame(expected, layout: layout), reference)
                }
            }
        }
    }

    func testInterruptedAnimationStartsFromVisibleStateAndKeepsFixedEnd() {
        for layout in HUDLayoutMode.allCases {
            let reference = CGRect(origin: CGPoint(x: -800, y: 50), size: HUDPositionGeometry.size(for: layout))
            let compact = HUDBackgroundAppearance(80).displayFrame(reference, layout: layout)
            let shrinking = HUDSizeTransition(start: reference, target: compact, initialIconFraction: 1, targetIconFraction: 0)
            let middle = shrinking.sample(elapsed: 0.1)
            XCTAssertFalse(middle.complete)
            XCTAssertEqual(middle.iconFraction, 0.5)
            if layout == .verticalTop { XCTAssertEqual(middle.frame.maxY, reference.maxY) }
            else { XCTAssertEqual(middle.frame.minY, reference.minY) }
            if layout == .horizontalRight { XCTAssertEqual(middle.frame.maxX, reference.maxX) }
            if layout == .horizontalLeft { XCTAssertEqual(middle.frame.minX, reference.minX) }
            let expanding = HUDSizeTransition(start: middle.frame, target: reference, initialIconFraction: middle.iconFraction, targetIconFraction: 1)
            XCTAssertEqual(expanding.sample(elapsed: 0).frame, middle.frame)
            XCTAssertEqual(expanding.sample(elapsed: 0.2).frame, reference)
            XCTAssertEqual(expanding.sample(elapsed: 0, reduceMotion: true).frame, reference)
            XCTAssertTrue(expanding.sample(elapsed: 0, reduceMotion: true).complete)
        }
    }

    func testCompactEdgePositionSurvivesStoreReloadAndExpansionDoesNotOverwriteAnchor() throws {
        let name = "HUDAnchorTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let visible = CGRect(x: -1200, y: 0, width: 1200, height: 800)
        let screen = HUDScreenIdentity(uuid: "external", displayID: 7, name: "Display", pixelWidth: 1200, pixelHeight: 800)
        for layout in HUDLayoutMode.allCases {
            let origin = layout == .horizontalRight ? visible.origin : CGPoint(x: visible.minX, y: visible.maxY - 380)
            let compact = CGRect(origin: origin, size: HUDBackgroundAppearance(95).size(layout))
            let reference = HUDBackgroundAppearance.referenceFrame(compact, layout: layout)
            let relative = HUDPositionGeometry.relativePosition(of: reference, in: visible)
            let record = HUDPositionRecord(version: 3, displayUUID: "external", legacyDisplayID: 7, displayName: "Display", pixelWidth: 1200, pixelHeight: 800,
                relativeX: relative.x, relativeY: relative.y,
                anchorX: ((layout == .horizontalRight ? reference.maxX : reference.minX) - visible.minX) / visible.width,
                anchorY: ((layout == .verticalTop ? reference.maxY : reference.minY) - visible.minY) / visible.height)
            HUDPositionStore(defaults: defaults).save(record, for: layout)
            let loaded = HUDPositionStore(defaults: defaults).loadResult(layout)
            let restored = HUDPositionDecision.resolve(layout: layout, stored: loaded, screens: [screen], visibleFrames: [visible], mainIndex: 0)
            let frame = try XCTUnwrap(restored.frame)
            XCTAssertEqual(HUDBackgroundAppearance(95).displayFrame(frame, layout: layout), compact)
            _ = HUDPositionGeometry.clamped(HUDBackgroundAppearance(79).displayFrame(frame, layout: layout), to: visible)
            XCTAssertEqual(HUDPositionStore(defaults: defaults).load(layout), record)
            XCTAssertFalse(restored.shouldSave)
        }
    }

    func testPreferenceValidationAndReload() {
        let name = "HUDTransparencyTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = HUDPreferences(defaults: defaults)
        XCTAssertEqual(preferences.loadTransparency(), 10)
        for value in ["90" as Any, true, Double.nan] {
            defaults.set(value, forKey: HUDPreferences.transparencyKey)
            XCTAssertEqual(preferences.loadTransparency(), 10)
        }
        for (value, expected) in [(-20.0, 0), (150.0, 100), (89.6, 90)] {
            defaults.set(value, forKey: HUDPreferences.transparencyKey)
            XCTAssertEqual(preferences.loadTransparency(), expected)
        }
        preferences.saveTransparency(95)
        XCTAssertEqual(HUDPreferences(defaults: defaults).loadTransparency(), 95)
    }

    func testThresholdAndFixedEndRoundTrip() {
        let reference = CGRect(x: -500, y: 70, width: 420, height: 40)
        for value in [0, 79, 80, 89, 90, 99, 100] {
            let appearance = HUDBackgroundAppearance(value)
            XCTAssertEqual(appearance.compact, value >= 80)
            for layout in HUDLayoutMode.allCases {
                let original = CGRect(origin: reference.origin, size: HUDPositionGeometry.size(for: layout))
                let display = appearance.displayFrame(original, layout: layout)
                if layout == .verticalTop { XCTAssertEqual(display.maxY, original.maxY) }
                else { XCTAssertEqual(display.minY, original.minY) }
                if layout == .horizontalRight { XCTAssertEqual(display.maxX, original.maxX) }
                if layout == .horizontalLeft { XCTAssertEqual(display.minX, original.minX) }
                XCTAssertEqual(HUDBackgroundAppearance.referenceFrame(display, layout: layout), original)
            }
        }
        XCTAssertEqual(HUDBackgroundAppearance(0).backgroundAlpha, 1)
        XCTAssertEqual(HUDBackgroundAppearance(100).backgroundAlpha, 0)
    }
}

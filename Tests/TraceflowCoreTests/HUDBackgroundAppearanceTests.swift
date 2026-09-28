import XCTest
@testable import TraceflowCore

final class HUDBackgroundAppearanceTests: XCTestCase {
    func testInterruptedAnimationStartsFromVisibleStateAndKeepsFixedEnd() {
        for layout in HUDLayoutMode.allCases {
            let reference = CGRect(origin: CGPoint(x: -800, y: 50), size: HUDPositionGeometry.size(for: layout))
            let compact = HUDBackgroundAppearance(90).displayFrame(reference, layout: layout)
            let shrinking = HUDSizeTransition(start: reference, target: compact, initialIconFraction: 1, targetIconFraction: 0)
            let middle = shrinking.sample(elapsed: 0.1)
            XCTAssertFalse(middle.complete)
            XCTAssertEqual(middle.iconFraction, 0.5)
            XCTAssertEqual(middle.frame.minY, reference.minY)
            if layout == .horizontal { XCTAssertEqual(middle.frame.maxX, reference.maxX) }
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
            let origin = layout == .horizontal ? visible.origin : CGPoint(x: visible.minX, y: visible.maxY - 380)
            let compact = CGRect(origin: origin, size: HUDBackgroundAppearance(95).size(layout))
            let reference = HUDBackgroundAppearance.referenceFrame(compact, layout: layout)
            let relative = HUDPositionGeometry.relativePosition(of: reference, in: visible)
            let record = HUDPositionRecord(version: 3, displayUUID: "external", legacyDisplayID: 7, displayName: "Display", pixelWidth: 1200, pixelHeight: 800,
                relativeX: relative.x, relativeY: relative.y,
                anchorX: ((layout == .horizontal ? reference.maxX : reference.minX) - visible.minX) / visible.width,
                anchorY: (reference.minY - visible.minY) / visible.height)
            HUDPositionStore(defaults: defaults).save(record, for: layout)
            let loaded = HUDPositionStore(defaults: defaults).loadResult(layout)
            let restored = HUDPositionDecision.resolve(layout: layout, stored: loaded, screens: [screen], visibleFrames: [visible], mainIndex: 0)
            let frame = try XCTUnwrap(restored.frame)
            XCTAssertEqual(HUDBackgroundAppearance(95).displayFrame(frame, layout: layout), compact)
            _ = HUDPositionGeometry.clamped(HUDBackgroundAppearance(80).displayFrame(frame, layout: layout), to: visible)
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
        for value in [0, 80, 89, 90, 99, 100] {
            let appearance = HUDBackgroundAppearance(value)
            XCTAssertEqual(appearance.compact, value >= 90)
            for layout in HUDLayoutMode.allCases {
                let original = CGRect(origin: reference.origin, size: HUDPositionGeometry.size(for: layout))
                let display = appearance.displayFrame(original, layout: layout)
                XCTAssertEqual(display.minY, original.minY)
                if layout == .horizontal { XCTAssertEqual(display.maxX, original.maxX) }
                XCTAssertEqual(HUDBackgroundAppearance.referenceFrame(display, layout: layout), original)
            }
        }
        XCTAssertEqual(HUDBackgroundAppearance(0).backgroundAlpha, 1)
        XCTAssertEqual(HUDBackgroundAppearance(100).backgroundAlpha, 0)
    }
}

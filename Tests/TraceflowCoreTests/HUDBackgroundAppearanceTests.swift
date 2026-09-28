import XCTest
@testable import TraceflowCore

final class HUDBackgroundAppearanceTests: XCTestCase {
    func testPreferenceValidationAndReload() {
        let name = "HUDTransparencyTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = HUDPreferences(defaults: defaults)
        XCTAssertEqual(preferences.loadTransparency(), 80)
        for value in ["90" as Any, true, Double.nan] {
            defaults.set(value, forKey: HUDPreferences.transparencyKey)
            XCTAssertEqual(preferences.loadTransparency(), 80)
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

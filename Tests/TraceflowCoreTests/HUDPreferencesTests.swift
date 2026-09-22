import XCTest
@testable import TraceflowCore

final class HUDPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "HUDPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFreshInstallUsesAndPersistsDefaults() {
        let preferences = HUDPreferences(defaults: defaults)

        XCTAssertEqual(preferences.loadGlowMode(), .standard)
        XCTAssertEqual(defaults.string(forKey: HUDPreferences.glowKey), HUDGlowMode.standard.rawValue)
        XCTAssertEqual(preferences.loadLayoutMode(), .horizontal)
        XCTAssertEqual(defaults.string(forKey: HUDPreferences.layoutKey), HUDLayoutMode.horizontal.rawValue)
    }

    func testLegacyLowAndMediumMigrateToStandard() {
        for value in [0, 1] {
            defaults.removeObject(forKey: HUDPreferences.glowKey)
            defaults.set(value, forKey: HUDPreferences.legacyGlowKey)

            XCTAssertEqual(HUDPreferences(defaults: defaults).loadGlowMode(), .standard)
            XCTAssertEqual(defaults.string(forKey: HUDPreferences.glowKey), HUDGlowMode.standard.rawValue)
        }
    }

    func testLegacyHighMigratesToStrong() {
        defaults.set(2, forKey: HUDPreferences.legacyGlowKey)

        XCTAssertEqual(HUDPreferences(defaults: defaults).loadGlowMode(), .strong)
        XCTAssertEqual(defaults.string(forKey: HUDPreferences.glowKey), HUDGlowMode.strong.rawValue)
    }

    func testNewGlowValueAlwaysWinsOverLegacyValue() {
        defaults.set(HUDGlowMode.strong.rawValue, forKey: HUDPreferences.glowKey)
        defaults.set(0, forKey: HUDPreferences.legacyGlowKey)

        let preferences = HUDPreferences(defaults: defaults)
        XCTAssertEqual(preferences.loadGlowMode(), .strong)
        XCTAssertEqual(preferences.loadGlowMode(), .strong)
    }

    func testInvalidValuesFallBackAndPersistDefaults() {
        defaults.set("invalid", forKey: HUDPreferences.glowKey)
        defaults.set(2, forKey: HUDPreferences.legacyGlowKey)
        defaults.set("diagonal", forKey: HUDPreferences.layoutKey)

        let preferences = HUDPreferences(defaults: defaults)
        XCTAssertEqual(preferences.loadGlowMode(), .standard)
        XCTAssertEqual(preferences.loadLayoutMode(), .horizontal)
        XCTAssertEqual(defaults.string(forKey: HUDPreferences.glowKey), HUDGlowMode.standard.rawValue)
        XCTAssertEqual(defaults.string(forKey: HUDPreferences.layoutKey), HUDLayoutMode.horizontal.rawValue)
    }

    func testSavingNewValuesSurvivesRepeatedLoads() {
        let preferences = HUDPreferences(defaults: defaults)
        preferences.saveGlowMode(.strong)
        preferences.saveLayoutMode(.vertical)
        defaults.set(0, forKey: HUDPreferences.legacyGlowKey)

        XCTAssertEqual(preferences.loadGlowMode(), .strong)
        XCTAssertEqual(preferences.loadLayoutMode(), .vertical)
    }
}

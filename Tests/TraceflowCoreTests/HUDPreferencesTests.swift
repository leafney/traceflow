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

    func testInvalidLegacyTypesDoNotBecomeOldNumericChoice() {
        let preferences = HUDPreferences(defaults: defaults)
        defaults.set("2", forKey: HUDPreferences.legacyGlowKey)
        XCTAssertEqual(preferences.loadGlowMode(), .standard)
        defaults.removeObject(forKey: HUDPreferences.glowKey)
        defaults.set(true, forKey: HUDPreferences.legacyGlowKey)
        XCTAssertEqual(preferences.loadGlowMode(), .standard)
    }

    func testSavingNewValuesSurvivesRepeatedLoads() {
        let preferences = HUDPreferences(defaults: defaults)
        preferences.saveGlowMode(.strong)
        preferences.saveLayoutMode(.vertical)
        defaults.set(0, forKey: HUDPreferences.legacyGlowKey)

        XCTAssertEqual(preferences.loadGlowMode(), .strong)
        XCTAssertEqual(preferences.loadLayoutMode(), .vertical)
    }

    func testPinnedDefaultsToFalseRejectsInvalidStorageAndSurvivesReload() {
        let preferences = HUDPreferences(defaults: defaults)
        XCTAssertFalse(preferences.loadPinned())
        defaults.set("true", forKey: HUDPreferences.pinnedKey)
        XCTAssertFalse(preferences.loadPinned())
        defaults.set(1, forKey: HUDPreferences.pinnedKey)
        XCTAssertFalse(preferences.loadPinned())
        preferences.savePinned(true)
        XCTAssertTrue(HUDPreferences(defaults: defaults).loadPinned())
        preferences.savePinned(false)
        XCTAssertFalse(HUDPreferences(defaults: defaults).loadPinned())
    }

    func testTitleColorDefaultsToBlackAndRejectsInvalidStorage() {
        let preferences = HUDPreferences(defaults: defaults)
        XCTAssertEqual(preferences.loadTitleColor(), .black)
        XCTAssertNil(defaults.object(forKey: HUDPreferences.titleColorKey))
        for invalidValue: Any in ["blue", 1, true] {
            defaults.set(invalidValue, forKey: HUDPreferences.titleColorKey)
            XCTAssertEqual(preferences.loadTitleColor(), .black)
        }
    }

    func testTitleColorSavesBothChoicesAcrossInstances() {
        let preferences = HUDPreferences(defaults: defaults)
        preferences.saveTitleColor(.white)
        XCTAssertEqual(HUDPreferences(defaults: defaults).loadTitleColor(), .white)
        preferences.saveTitleColor(.black)
        XCTAssertEqual(HUDPreferences(defaults: defaults).loadTitleColor(), .black)
    }
}

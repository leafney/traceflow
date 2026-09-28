import XCTest
@testable import TraceflowCore

final class HUDTransparencyDraftTests: XCTestCase {
    func testMousePreviewReleaseSavesLatestValueOnly() {
        var draft = HUDTransparencyDraft(80)
        XCTAssertNil(draft.takeCommit())
        draft.setEditing(true)
        draft.preview(85)
        draft.preview(95)
        XCTAssertTrue(draft.isEditing)
        XCTAssertTrue(draft.isDirty)
        draft.setEditing(false)
        XCTAssertEqual(draft.takeCommit(), 95)
        XCTAssertNil(draft.takeCommit())
    }

    func testKeyboardCloseAndExitCommitSurviveReload() {
        let name = "HUDDraftTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = HUDPreferences(defaults: defaults)
        var draft = HUDTransparencyDraft(preferences.loadTransparency())
        // Keyboard changes do not enter continuous editing.
        draft.preview(91)
        XCTAssertFalse(draft.isEditing)
        preferences.saveTransparency(draft.takeCommit()!)
        XCTAssertEqual(preferences.loadTransparency(), 91)
        // Closing settings ends a continuous edit and commits the latest preview.
        draft.setEditing(true)
        draft.preview(99)
        draft.setEditing(false)
        preferences.saveTransparency(draft.takeCommit()!)
        XCTAssertEqual(preferences.loadTransparency(), 99)
        // Exit commits even when a mouse gesture has not ended.
        draft.setEditing(true)
        draft.preview(100)
        preferences.saveTransparency(draft.takeCommit()!)
        XCTAssertEqual(HUDPreferences(defaults: defaults).loadTransparency(), 100)
    }
}

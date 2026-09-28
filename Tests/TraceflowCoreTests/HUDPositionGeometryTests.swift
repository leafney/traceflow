import CoreGraphics
import XCTest
@testable import TraceflowCore

final class HUDPositionGeometryTests: XCTestCase {
    private let visible = CGRect(x: 100, y: 200, width: 1200, height: 800)

    func testHorizontalDefaultAtTopCenter() {
        XCTAssertEqual(HUDPositionGeometry.defaultFrame(for: .horizontal, visible: visible), CGRect(x: 490, y: 948, width: 420, height: 40))
    }

    func testSharedMetricsFillEachLayoutExactly() {
        XCTAssertEqual(HUDMetrics.iconLength + HUDMetrics.separatorThickness + HUDMetrics.titleLength + HUDMetrics.separatorThickness + HUDMetrics.lightAreaLength,
                       HUDMetrics.longAxis)
        XCTAssertEqual(HUDMetrics.lightDiameter * 3 + HUDMetrics.lightSpacing * 2,
                       HUDMetrics.lightAreaLength - 14)
        XCTAssertEqual(HUDMetrics.titleTextLength, HUDMetrics.titleLength - 12)
    }

    func testLayoutTransitionSavesBeforeResizeAndRestore() {
        XCTAssertEqual(HUDLayoutTransitionPlanner.steps(from: .horizontal, to: .vertical), [
            .save(.horizontal),
            .resize(.vertical, CGSize(width: 40, height: 420)),
            .restore(.vertical)
        ])
        XCTAssertEqual(HUDLayoutTransitionPlanner.steps(from: .vertical, to: .horizontal), [
            .save(.vertical),
            .resize(.horizontal, CGSize(width: 420, height: 40)),
            .restore(.horizontal)
        ])
        XCTAssertTrue(HUDLayoutTransitionPlanner.steps(from: .vertical, to: .vertical).isEmpty)
    }

    func testVerticalDefaultAtRightCenter() {
        XCTAssertEqual(HUDPositionGeometry.defaultFrame(for: .vertical, visible: visible), CGRect(x: 1248, y: 390, width: 40, height: 420))
    }

    func testRestoringRelativeCoordinatesClampsToVisibleScreen() {
        let frame = HUDPositionGeometry.restoredFrame(for: .vertical, relativeX: 0.75, relativeY: 0.25, visible: visible)
        let position = HUDPositionGeometry.relativePosition(of: frame, in: visible)
        XCTAssertEqual(position.x, 0.75, accuracy: 0.0001)
        XCTAssertEqual(position.y, 0.25, accuracy: 0.0001)
        XCTAssertTrue(visible.contains(frame))
    }

    func testSmallerScreenAndNonFinitePositionStayVisible() {
        let small = CGRect(x: 50, y: 100, width: 600, height: 500)
        let restored = HUDPositionGeometry.restoredFrame(for: .horizontal, relativeX: 1.5, relativeY: .nan, visible: small)
        XCTAssertEqual(restored.origin, CGPoint(x: 230, y: 100))
        XCTAssertTrue(small.contains(restored))
        let narrower = CGRect(x: 50, y: 100, width: 35, height: 300)
        XCTAssertEqual(HUDPositionGeometry.restoredFrame(for: .vertical, relativeX: 1, relativeY: 1, visible: narrower).origin, narrower.origin)
    }

    func testLayoutPositionRecordsRemainIndependent() {
        let name = "HUDPositionGeometryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = HUDPositionStore(defaults: defaults)
        let horizontal = record(x: 0.2)
        let vertical = record(x: 0.9)
        store.save(horizontal, for: .horizontal)
        store.save(vertical, for: .vertical)

        XCTAssertEqual(store.load(.horizontal), horizontal)
        XCTAssertEqual(store.load(.vertical), vertical)
        store.save(record(x: 0.4), for: .vertical)
        XCTAssertEqual(store.load(.horizontal), horizontal)
        XCTAssertEqual(store.load(.vertical)?.relativeX, 0.4)
    }

    func testResettingVerticalDoesNotChangeHorizontal() {
        let name = "HUDPositionResetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = HUDPositionStore(defaults: defaults)
        store.save(record(x: 0.2), for: .horizontal)
        store.save(record(x: 0.9), for: .vertical)
        let defaultFrame = HUDPositionGeometry.defaultFrame(for: .vertical, visible: visible)
        let relative = HUDPositionGeometry.relativePosition(of: defaultFrame, in: visible)
        store.save(record(x: relative.x, y: relative.y), for: .vertical)

        XCTAssertEqual(store.load(.horizontal)?.relativeX, 0.2)
        XCTAssertEqual(store.load(.vertical)?.relativeX, relative.x)
    }

    func testLegacyPositionMigratesOnlyToHorizontal() {
        let name = "HUDPositionLegacyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = HUDPositionStore(defaults: defaults)
        let legacy = record(x: 0.2)
        defaults.set(try! JSONEncoder().encode(legacy), forKey: HUDPositionStore.legacyKey)

        XCTAssertNil(store.load(.vertical))
        XCTAssertEqual(store.load(.horizontal), legacy)
        XCTAssertNotNil(defaults.data(forKey: HUDPositionStore.horizontalKey))
        store.save(record(x: 0.7), for: .horizontal)
        XCTAssertEqual(store.load(.horizontal)?.relativeX, 0.7)
    }

    func testCorruptedCurrentPositionIsDifferentFromMissingPosition() {
        let name = "HUDPositionCorruptionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = HUDPositionStore(defaults: defaults)
        XCTAssertEqual(store.loadResult(.vertical), .missing)
        defaults.set(Data("broken".utf8), forKey: HUDPositionStore.verticalKey)
        XCTAssertEqual(store.loadResult(.vertical), .corrupted)
        defaults.removeObject(forKey: HUDPositionStore.verticalKey)
        defaults.set("wrong type", forKey: HUDPositionStore.verticalKey)
        XCTAssertEqual(store.loadResult(.vertical), .corrupted)
        defaults.set(Data("broken legacy".utf8), forKey: HUDPositionStore.legacyKey)
        XCTAssertEqual(store.loadResult(.horizontal), .corrupted)
    }

    func testMissingDisplayRequiresDefaultPosition() {
        let saved = record(x: 0.6)
        let available = HUDScreenIdentity(uuid: "another-screen", displayID: 2, name: "External", pixelWidth: 3000, pixelHeight: 2000)
        XCTAssertNil(HUDPositionGeometry.matchingScreen(for: saved, among: [available]))
        XCTAssertEqual(HUDPositionGeometry.defaultFrame(for: .vertical, visible: visible),
                       CGRect(x: 1248, y: 390, width: 40, height: 420))
    }

    func testScreenMatchingPreservesFallbackOrder() {
        let saved = record(x: 0.6)
        let nameMatch = HUDScreenIdentity(uuid: "other", displayID: 2, name: "Main", pixelWidth: 2400, pixelHeight: 1600)
        let uuidMatch = HUDScreenIdentity(uuid: "screen", displayID: 3, name: "Elsewhere", pixelWidth: 1000, pixelHeight: 800)
        XCTAssertEqual(HUDPositionGeometry.matchingScreen(for: saved, among: [nameMatch, uuidMatch]), 1)
    }

    func testAmbiguousLegacyScreensDoNotGuessByDisplayID() {
        let saved = HUDPositionRecord(version: 3, displayUUID: nil, legacyDisplayID: 1, displayName: "Twin", pixelWidth: 2400, pixelHeight: 1600, relativeX: 0.2, relativeY: 0.8)
        let screens = [1, 2].map { HUDScreenIdentity(uuid: nil, displayID: UInt32($0), name: "Twin", pixelWidth: 2400, pixelHeight: 1600) }
        XCTAssertEqual(HUDPositionGeometry.screenMatch(for: saved, among: screens), .ambiguous)
        XCTAssertNil(HUDPositionGeometry.matchingScreen(for: saved, among: screens))
    }

    func testMissingUUIDDoesNotMatchDifferentPhysicalScreen() {
        let different = HUDScreenIdentity(uuid: "different", displayID: 1, name: "Main", pixelWidth: 2400, pixelHeight: 1600)
        XCTAssertEqual(HUDPositionGeometry.screenMatch(for: record(x: 0.6), among: [different]), .missing)
    }

    func testLegacyScreenRestoresAfterResolutionChangeWhenNameAndIDAgree() {
        let saved = HUDPositionRecord(version: 3, displayUUID: nil, legacyDisplayID: 7, displayName: "External", pixelWidth: 2400, pixelHeight: 1600, relativeX: 0.2, relativeY: 0.8)
        let resized = HUDScreenIdentity(uuid: "new", displayID: 7, name: "External", pixelWidth: 3000, pixelHeight: 2000)
        XCTAssertEqual(HUDPositionGeometry.screenMatch(for: saved, among: [resized]), .unique(0))
        let target = CGRect(x: -3000, y: 0, width: 1500, height: 1000)
        let decision = HUDPositionDecision.resolve(layout: .horizontal, stored: .loaded(saved), screens: [resized], visibleFrames: [target], mainIndex: 0)
        XCTAssertEqual(decision.frame, HUDPositionGeometry.restoredFrame(for: .horizontal, relativeX: 0.2, relativeY: 0.8, visible: target))
        XCTAssertFalse(decision.shouldSave)
    }

    func testLegacyResolutionChangeDoesNotGuessBetweenTwinScreens() {
        let saved = HUDPositionRecord(version: 3, displayUUID: nil, legacyDisplayID: 7, displayName: "External", pixelWidth: 2400, pixelHeight: 1600, relativeX: 0.2, relativeY: 0.8)
        let twins = [7, 8].map { HUDScreenIdentity(uuid: nil, displayID: UInt32($0), name: "External", pixelWidth: 3000, pixelHeight: 2000) }
        XCTAssertEqual(HUDPositionGeometry.screenMatch(for: saved, among: twins), .unique(0))
        let reassigned = [8, 9].map { HUDScreenIdentity(uuid: nil, displayID: UInt32($0), name: "External", pixelWidth: 3000, pixelHeight: 2000) }
        XCTAssertEqual(HUDPositionGeometry.screenMatch(for: saved, among: reassigned), .missing)
    }

    func testRetryStopsWhenRecoveredOrDeadlineReached() {
        let start = Date(timeIntervalSince1970: 100)
        let deadline = start.addingTimeInterval(HUDPositionRetryPolicy.duration)
        XCTAssertTrue(HUDPositionRetryPolicy.shouldRetry(isTemporary: true, now: start.addingTimeInterval(1), deadline: deadline))
        XCTAssertFalse(HUDPositionRetryPolicy.shouldRetry(isTemporary: false, now: start.addingTimeInterval(1), deadline: deadline))
        XCTAssertFalse(HUDPositionRetryPolicy.shouldRetry(isTemporary: true, now: deadline, deadline: deadline))
        XCTAssertFalse(HUDPositionRetryPolicy.shouldRetry(isTemporary: true, now: start, deadline: nil))
    }

    func testTemporaryFallbackDoesNotSaveAndReconnectRestoresRelativePosition() {
        let saved = record(x: 0.7, y: 0.3)
        let main = HUDScreenIdentity(uuid: "main", displayID: 2, name: "Laptop", pixelWidth: 1200, pixelHeight: 800)
        let external = HUDScreenIdentity(uuid: "screen", displayID: 3, name: "External", pixelWidth: 3000, pixelHeight: 2000)
        let fallback = HUDPositionDecision.resolve(layout: .horizontal, stored: .loaded(saved), screens: [main], visibleFrames: [visible], mainIndex: 0)
        XCTAssertTrue(fallback.isTemporary)
        XCTAssertFalse(fallback.shouldSave)
        let externalFrame = CGRect(x: -2000, y: 50, width: 1800, height: 1000)
        let restored = HUDPositionDecision.resolve(layout: .horizontal, stored: .loaded(saved), screens: [main, external], visibleFrames: [visible, externalFrame], mainIndex: 0)
        XCTAssertFalse(restored.isTemporary)
        XCTAssertFalse(restored.shouldSave)
        XCTAssertEqual(restored.frame, HUDPositionGeometry.restoredFrame(for: .horizontal, relativeX: 0.7, relativeY: 0.3, visible: externalFrame))
    }

    func testOnlyMissingRecordSavesInitialDefault() {
        let screen = HUDScreenIdentity(uuid: "main", displayID: 1, name: "Main", pixelWidth: 1200, pixelHeight: 800)
        XCTAssertTrue(HUDPositionDecision.resolve(layout: .vertical, stored: .missing, screens: [screen], visibleFrames: [visible], mainIndex: 0).shouldSave)
        XCTAssertFalse(HUDPositionDecision.resolve(layout: .vertical, stored: .corrupted, screens: [screen], visibleFrames: [visible], mainIndex: 0).shouldSave)
        XCTAssertNil(HUDPositionDecision.resolve(layout: .vertical, stored: .missing, screens: [], visibleFrames: [], mainIndex: nil).frame)
    }

    func testUserChoiceDuringFallbackReplacesTargetAndLayoutsStayIndependent() {
        let domain = "HUDRecoverySequence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = HUDPositionStore(defaults: defaults)
        let original = record(x: 0.7)
        store.save(original, for: .horizontal)
        let main = HUDScreenIdentity(uuid: "main", displayID: 2, name: "Laptop", pixelWidth: 1200, pixelHeight: 800)
        let external = HUDScreenIdentity(uuid: "screen", displayID: 1, name: "Main", pixelWidth: 2400, pixelHeight: 1600)
        for _ in 0..<3 {
            let decision = HUDPositionDecision.resolve(layout: .horizontal, stored: store.loadResult(.horizontal), screens: [main], visibleFrames: [visible], mainIndex: 0)
            XCTAssertTrue(decision.isTemporary)
            XCTAssertFalse(decision.shouldSave)
            XCTAssertEqual(store.load(.horizontal), original)
        }
        let vertical = HUDPositionDecision.resolve(layout: .vertical, stored: store.loadResult(.vertical), screens: [main], visibleFrames: [visible], mainIndex: 0)
        XCTAssertTrue(vertical.shouldSave)
        XCTAssertEqual(store.load(.horizontal), original)

        let chosen = HUDPositionRecord(version: 3, displayUUID: "main", legacyDisplayID: 2, displayName: "Laptop", pixelWidth: 1200, pixelHeight: 800, relativeX: 0.25, relativeY: 0.4)
        store.save(chosen, for: .horizontal)
        let afterReconnect = HUDPositionDecision.resolve(layout: .horizontal, stored: store.loadResult(.horizontal), screens: [main, external], visibleFrames: [visible, visible.offsetBy(dx: 2000, dy: 0)], mainIndex: 0)
        XCTAssertEqual(afterReconnect.frame, HUDPositionGeometry.restoredFrame(for: .horizontal, relativeX: 0.25, relativeY: 0.4, visible: visible))
        XCTAssertFalse(afterReconnect.shouldSave)
    }

    private func record(x: Double, y: Double = 0.5) -> HUDPositionRecord {
        HUDPositionRecord(version: 3, displayUUID: "screen", legacyDisplayID: 1, displayName: "Main", pixelWidth: 2400, pixelHeight: 1600, relativeX: x, relativeY: y)
    }

    func testDragUsesGlobalPointerDeltaAcrossScreens() {
        let drag = HUDDragTracking(pointer: CGPoint(x: 900, y: 300), origin: CGPoint(x: 800, y: 250))
        XCTAssertEqual(drag.origin(at: CGPoint(x: -500, y: 700)), CGPoint(x: -600, y: 650))
        XCTAssertEqual(drag.origin(at: CGPoint(x: 900, y: 300)), drag.initialOrigin)
    }
}

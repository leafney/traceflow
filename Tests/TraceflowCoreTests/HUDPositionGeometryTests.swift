import CoreGraphics
import XCTest
@testable import TraceflowCore

final class HUDPositionGeometryTests: XCTestCase {
    private let visible = CGRect(x: 100, y: 200, width: 1200, height: 800)

    func testHorizontalDefaultAtTopCenter() {
        XCTAssertEqual(HUDPositionGeometry.defaultFrame(for: .horizontal, visible: visible), CGRect(x: 490, y: 948, width: 420, height: 40))
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

    private func record(x: Double, y: Double = 0.5) -> HUDPositionRecord {
        HUDPositionRecord(version: 3, displayUUID: "screen", legacyDisplayID: 1, displayName: "Main", pixelWidth: 2400, pixelHeight: 1600, relativeX: x, relativeY: y)
    }
}

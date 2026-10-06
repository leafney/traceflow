import XCTest
@testable import TraceflowCore

final class SessionMarkerColorTests: XCTestCase {
    func testNormalizationAndBoundedFallback() throws {
        XCTAssertEqual(SessionMarkerColor.normalized(" #aB12ef\n"), "#AB12EF")
        for invalid in ["red", "#fff", "#12345678", "#GG0000"] { XCTAssertNil(SessionMarkerColor.normalized(invalid)) }
        XCTAssertEqual(try SessionMarkerColor.allocate(occupied: []), "#477EE8")
        let occupied = Set(SessionMarkerColor.candidates)
        XCTAssertEqual(try SessionMarkerColor.allocate(occupied: occupied), "#000000")
        XCTAssertEqual(try SessionMarkerColor.firstUnused(occupied: ["#000000"], upperBound: 1), "#000001")
        XCTAssertThrowsError(try SessionMarkerColor.firstUnused(occupied: ["#000000", "#000001"], upperBound: 1))
    }

    func testBatchRetainsDuplicateManualColorsAndAssignsStableUniqueColors() throws {
        let date = Date(timeIntervalSince1970: 100)
        let records = (0..<12).map { index in
            PersistedSession(sessionID: "s\(index)", markerColorHex: index < 2 ? "#123456" : nil,
                             discoveredAt: date, lastUpdatedAt: date, rotationIndex: index)
        }
        let assigned = try SessionMarkerColor.fillingMissing(in: records.reversed())
        XCTAssertEqual(assigned.filter { $0.markerColorHex == "#123456" }.count, 2)
        XCTAssertEqual(Set(assigned.compactMap(\.markerColorHex)).count, 11)
        XCTAssertFalse(assigned.contains { $0.markerColorHex == SessionMarkerColor.placeholder })
        XCTAssertEqual(try SessionMarkerColor.fillingMissing(in: assigned), assigned)
        let normalOrder = try SessionMarkerColor.fillingMissing(in: records)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: assigned.map { ($0.id, $0.markerColorHex) }),
                       Dictionary(uniqueKeysWithValues: normalOrder.map { ($0.id, $0.markerColorHex) }))
        for record in assigned { XCTAssertEqual(record.lastUpdatedAt, date) }
    }

    func testLegacyAndInvalidColorFieldsDecodeWithoutMaskingOtherCorruption() throws {
        let date = Date(timeIntervalSince1970: 100)
        let record = PersistedSession(sessionID: "old", customTitle: "保留标题", discoveredAt: date, lastUpdatedAt: date, rotationIndex: 2)
        let data = try JSONEncoder().encode(record)
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for invalid: Any in [NSNull(), 123, true, "bad"] {
            var object = base
            object["markerColorHex"] = invalid
            let decoded = try JSONDecoder().decode(PersistedSession.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(decoded, record)
        }
        XCTAssertEqual(try JSONDecoder().decode(PersistedSession.self, from: data), record)
        var corrupted = base
        corrupted["rotationIndex"] = "bad"
        XCTAssertThrowsError(try JSONDecoder().decode(PersistedSession.self, from: JSONSerialization.data(withJSONObject: corrupted)))
    }
}
